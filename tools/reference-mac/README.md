# Optional Mac reference measurement

**Experimental: the Swift recorder has not been compiled or run on a Mac.** The portable Python analyzer has synthetic clock, dropped-frame and failure-case tests. Those tests do not validate ScreenCaptureKit integration. This tool is not installed by OmarchyLight and is not needed to use the launcher.

The original reference movie has no input-event timestamps and occasionally skips an intermediate motion frame. This tool is intended to capture a new, explicitly started reference session containing both input-event and display-frame timestamps. It cannot measure physical key-switch or screen-photon latency.

## Capture

Requires macOS 13 or later, Apple Command Line Tools, and a main display on which Spotlight is visible. The default crop is 720×580 logical points, horizontally centered, 70 points from the top; it is recorded at the display's backing scale. Move Spotlight into that region before recording. For comparisons against the existing reference, use a 1440×900 logical display at 2× scale.

```sh
./tools/reference-mac/build.sh
./tools/reference-mac/reference-probe "$HOME/Desktop/spotlight-reference-01" 30 60
```

The output directory must not exist; its parent must already exist. The process exits after 30 seconds. Ctrl+C stops and finalizes it early. Duration can be 5–120 seconds and requested rate 30–120 fps; ScreenCaptureKit may deliver fewer frames. Screen Recording and Input Monitoring access must be granted to the executable or invoking terminal in macOS System Settings. A permission failure exits with an explanation; the tool does not change permissions itself. If a failed attempt created the output folder, choose a new name on the next attempt.

A short comparison sequence:

1. Open Spotlight with Command+Space. Leave it empty for two seconds.
2. Hover each category, then type a known application prefix. Wait one second.
3. Press Down to expand results, then clear the query. Wait for separation.
4. Type another query, clear it, and type again during the transition.
5. Close and reopen during the closing animation. Finish with a normal close.

F8 requests a lossless PNG of the next complete frame. On keyboards that reserve F8 for media, use Fn+F8. The listener does not consume the key, so its normal system action may also occur.

The output contains `reference.mov` (ProRes 4444), `timeline.jsonl`, and any requested `still-*.png` files. The recorder has no network code, audio capture or input injection. The timeline logs shortcut names, generic typing edges and pointer coordinates, without arbitrary letter/digit keycodes or Unicode text. **The video itself contains everything visible inside the crop, including search text and results.** Keep reference output outside this repository; review it before sharing.

## Analyze

Run the analyzer on either Linux or macOS with Python 3:

```sh
python3 tools/reference-mac/analyze.py /path/to/capture/timeline.jsonl
```

This summarizes frame loss, missing timestamps, errors and named input events. It deliberately does not infer that the first frame after a keypress contains a visual response.

After inspecting the movie frame by frame, identify the first visible response and the corresponding `frameIndex` from the timeline. Then select the initiating input event:

```sh
python3 tools/reference-mac/analyze.py /path/to/capture/timeline.jsonl \
  --event-index 12 --response-frame 83
```

The numbers above are examples. The report gives the selected frame's zero-based movie ordinal, movie time, event-to-display interval and preceding written frame's time relative to the event. A `frameIndex` counts complete captured frames, including frames the writer rejected; it is not necessarily the movie ordinal. `movieTimeSeconds` is computed from source PTS relative to the first written frame.

Before using any Mac result, verify that display timestamps are present and increasing, the writer completed, the movie crop/scale is correct, and the selected frame really is the first visual response. The analyzer exposes capture warnings rather than treating an incomplete recording as clean evidence. Clock conversion uses integer fractions to avoid losing precision at long machine uptimes. A manually selected response frame remains limited by frame cadence; the preceding frame provides the relevant sampling interval only when visual inspection confirms it has no response.

The first Mac run must also validate that the SDK's `SCStreamFrameInfo.displayTime` units and the `CGEvent` timebase align on that machine. Callback arrival times are retained for diagnosis but are not substituted for display timestamps. Do not compare the resulting WindowServer interval with Linux's Qt `frameSwapped` callback as if they measured the same pipeline stage. A physical latency guarantee would require a separate hardware measurement.

## Validation

```sh
python3 tests/test_reference_capture.py
```

On Linux, `build.sh` intentionally refuses to build. A successful Mac build and a short real capture remain required before this recorder can be considered validated.

API references: [ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [displayTime](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/displaytime), [CGEvent timestamp](https://developer.apple.com/documentation/coregraphics/cgevent/timestamp).
