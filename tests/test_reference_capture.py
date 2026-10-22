"""Portable analysis tests. These do not compile or validate the macOS recorder."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('capture_analysis', Path(__file__).parents[1] / 'tools/reference-mac/analyze.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def capture():
    return [
        {'type': 'metadata', 'schema': 1, 'machTimebaseNumer': 125, 'machTimebaseDenom': 3},
        {'type': 'input', 'eventIndex': 0, 'eventTimestampNs': 1_000_000_000, 'action': 'spotlight', 'edge': 'down'},
        {'type': 'frame', 'frameIndex': 0, 'displayMachTicks': 23_880_000, 'sourcePTSValue': 100, 'sourcePTSTimescale': 60, 'written': True},
        {'type': 'frame', 'frameIndex': 1, 'displayMachTicks': 24_280_000, 'sourcePTSValue': 101, 'sourcePTSTimescale': 60, 'written': False},
        {'type': 'frame', 'frameIndex': 2, 'displayMachTicks': 24_680_000, 'sourcePTSValue': 102, 'sourcePTSTimescale': 60, 'written': True},
        {'type': 'writer_end', 'status': 2},
        {'type': 'end', 'exitStatus': 0},
    ]


class AnalysisTests(unittest.TestCase):
    def test_summary_does_not_guess_response(self):
        report = module.analyze(capture())
        self.assertIsNone(report['measurement'])
        self.assertEqual(report['writtenFrames'], 2)
        self.assertEqual(len(report['warnings']), 1)

    def test_clock_conversion_and_movie_mapping(self):
        report = module.analyze(capture(), 0, 2)
        measure = report['measurement']
        self.assertAlmostEqual(measure['eventToSelectedDisplayFrameMs'], 28.3333333333)
        self.assertEqual(measure['movieFrameOrdinalZeroBased'], 1)
        self.assertAlmostEqual(measure['movieTimeSeconds'], 2 / 60)
        self.assertEqual(measure['previousWrittenFrameRelativeToEventMs'], -5)
        self.assertTrue(measure['captureHasWarnings'])

    def test_rejects_unavailable_frame(self):
        with self.assertRaisesRegex(ValueError, 'absent'):
            module.analyze(capture(), 0, 1)

    def test_rejects_response_before_input(self):
        with self.assertRaisesRegex(ValueError, 'predates'):
            module.analyze(capture(), 0, 0)

    def test_requires_both_selectors(self):
        with self.assertRaisesRegex(ValueError, 'both'):
            module.analyze(capture(), 0)

    def test_missing_clock(self):
        rows = capture()
        del rows[4]['displayMachTicks']
        with self.assertRaisesRegex(ValueError, 'no display'):
            module.analyze(rows, 0, 2)

    def test_flags_capture_failures(self):
        rows = capture()[:-2] + [{'type': 'event_tap_gap'}, {'type': 'capture_error'}]
        report = module.analyze(rows)
        self.assertEqual(len(report['warnings']), 5)

    def test_metadata_can_follow_first_event(self):
        rows = capture()
        rows[0], rows[1] = rows[1], rows[0]
        self.assertEqual(module.analyze(rows)['inputEvents'], 1)

    def test_rejects_duplicate_ids(self):
        rows = capture()
        rows.insert(4, copy.deepcopy(rows[3]))
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            module.analyze(rows)

    def test_rejects_invalid_timebase(self):
        rows = capture()
        rows[0]['machTimebaseDenom'] = 0
        with self.assertRaisesRegex(ValueError, 'timebase'):
            module.analyze(rows)

    def test_unknown_selection(self):
        with self.assertRaisesRegex(ValueError, 'not found'):
            module.analyze(capture(), 999, 2)

    def test_does_not_lose_precision_at_large_uptime(self):
        rows = capture()
        offset = 10**18
        rows[1]['eventTimestampNs'] += offset
        for row in rows:
            if row.get('type') == 'frame':
                row['displayMachTicks'] += offset * 3 // 125
        self.assertAlmostEqual(module.analyze(rows, 0, 2)['measurement']['eventToSelectedDisplayFrameMs'], 28.3333333333)


if __name__ == '__main__':
    unittest.main()
