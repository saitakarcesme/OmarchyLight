#!/usr/bin/env python3
"""Summarize an opt-in capture; measure a manually identified response frame."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import sys


def analyze(rows, event_index=None, response_frame=None):
    metadata = [row for row in rows if row.get('type') == 'metadata']
    if len(metadata) != 1 or metadata[0].get('schema') != 1:
        raise ValueError('Expected exactly one schema-1 metadata record')
    meta = metadata[0]
    numer, denom = meta.get('machTimebaseNumer', 0), meta.get('machTimebaseDenom', 0)
    if not isinstance(numer, int) or not isinstance(denom, int) or min(numer, denom) <= 0:
        raise ValueError('Invalid Mach timebase')
    tick_ns = Fraction(numer, denom)
    frames = [row for row in rows if row.get('type') == 'frame']
    events = [row for row in rows if row.get('type') == 'input']
    for records, key in ((frames, 'frameIndex'), (events, 'eventIndex')):
        indices = [row.get(key) for row in records]
        if any(not isinstance(i, int) or i < 0 for i in indices) or len(set(indices)) != len(indices):
            raise ValueError(f'Invalid or duplicate {key}')
        if indices != sorted(indices):
            raise ValueError(f'Non-monotonic {key}')
    written = [row for row in frames if row.get('written') is True]
    warnings = []
    if len(written) != len(frames):
        warnings.append('Some complete frames were not written to the movie')
    if any('displayMachTicks' not in row for row in frames):
        warnings.append('Some frames have no display timestamp')
    if any(row.get('type') == 'event_tap_gap' for row in rows):
        warnings.append('Input event tap had a gap')
    if any(row.get('type') == 'capture_error' for row in rows):
        warnings.append('Capture reported an error')
    ends = [row for row in rows if row.get('type') == 'end']
    if len(ends) != 1 or ends[0].get('exitStatus') != 0:
        warnings.append('Recording did not finish successfully')
    writer_ends = [row for row in rows if row.get('type') == 'writer_end']
    if len(writer_ends) != 1 or writer_ends[0].get('status') != 2:
        warnings.append('Video writer did not confirm completion')
    report = {
        'completeFrames': len(frames), 'writtenFrames': len(written), 'inputEvents': len(events),
        'warnings': warnings,
        'shortcutEvents': [{key: row.get(key) for key in ('eventIndex', 'action', 'edge', 'eventTimestampNs')}
                           for row in events if row.get('action') not in ('typing', 'pointer_move')],
        'measurement': None,
    }
    if event_index is None and response_frame is None:
        return report
    if event_index is None or response_frame is None:
        raise ValueError('Select both --event-index and --response-frame')
    event = next((row for row in events if row['eventIndex'] == event_index), None)
    frame = next((row for row in frames if row['frameIndex'] == response_frame), None)
    if event is None or frame is None:
        raise ValueError('Selected input event or response frame was not found')
    if frame.get('written') is not True:
        raise ValueError('Selected response frame is absent from the movie')
    if 'displayMachTicks' not in frame:
        raise ValueError('Selected response frame has no display timestamp')
    event_ns = event.get('eventTimestampNs')
    if not isinstance(event_ns, int) or event_ns < 0:
        raise ValueError('Invalid input timestamp')
    response_ns = frame['displayMachTicks'] * tick_ns
    delta_ms = (response_ns - event_ns) / 1_000_000
    if delta_ms < 0:
        raise ValueError('Response predates input; check event/frame selection and clock alignment')
    ordinal = written.index(frame)
    first = written[0]
    for row in (first, frame):
        if row.get('sourcePTSTimescale', 0) <= 0:
            raise ValueError('Invalid movie PTS timescale')
    movie_time = Fraction(frame['sourcePTSValue'], frame['sourcePTSTimescale']) - Fraction(first['sourcePTSValue'], first['sourcePTSTimescale'])
    previous = written[ordinal - 1] if ordinal else None
    previous_ms = None
    if previous and 'displayMachTicks' in previous:
        previous_ms = (previous['displayMachTicks'] * tick_ns - event_ns) / 1_000_000
        if previous_ms >= delta_ms:
            raise ValueError('Display timestamps are not increasing')
    report['measurement'] = {
        'eventIndex': event_index, 'responseFrameIndex': response_frame,
        'movieFrameOrdinalZeroBased': ordinal, 'movieTimeSeconds': float(movie_time),
        'eventToSelectedDisplayFrameMs': float(delta_ms),
        'previousWrittenFrameRelativeToEventMs': float(previous_ms) if previous_ms is not None else None,
        'responseSelection': 'manual: the analyst must identify the first visible response',
        'scope': 'CGEvent to WindowServer display timestamp; not switch-to-photon latency',
        'captureHasWarnings': bool(warnings),
    }
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('timeline', type=Path)
    parser.add_argument('--event-index', type=int)
    parser.add_argument('--response-frame', type=int)
    args = parser.parse_args()
    try:
        rows = [json.loads(line) for line in args.timeline.read_text().splitlines() if line.strip()]
        print(json.dumps(analyze(rows, args.event_index, args.response_frame), indent=2))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Invalid capture: {error}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
