# Fidelity acceptance audit

Status: **the requested pixel-for-pixel and frame-for-frame equivalence has not been established.** The installed launcher works and several measured differences have been corrected. Neither repository delivery nor passing functional tests closes the visual-fidelity goal.

This audit covers the launcher implementation at `fc3c50b`, tested on the local Omarchy/Hyprland desktop with two 1920×1080, scale-1 monitors. It is evidence about that configuration, not certification for every display or compositor setup.

| Requirement | Evidence | Remaining limit |
|---|---|---|
| Search and compact geometry | 640×56 search; 384×56 compact; measured row/icon/control positions | Model dimensions do not establish equality of every rendered edge |
| Opening motion | Fitted scale RMS 0.00023; four live repeats first visible scale 1.0925–1.0935 after frame synchronization | Captures can omit intermediate steps; no reference input timestamps |
| Liquid separation / merge | Reference contour-fit RMS 0.55 / 0.79 logical pixels | Nonzero residual; exact intermediate source frames are unavailable |
| Query-clear sequencing | Installed clear-to-width-threshold 49.984 ms; reference examples 50–117 ms | Visible-frame timing, not physical input latency |
| Interrupted gestures | Runtime and math checks preserve position/velocity; rapid key toggles and result changes checked | Does not prove equality to Apple's internal response under every input sequence |
| Glyph reveal | Independent opacity and calibrated Gaussian blur; live phase comparisons recorded | Glyph artwork and rasterization differ |
| Glass | Fixed, text-free same-background MAE 0.94 header / 0.76 body, 8-bit channels | One calibrated backdrop; different blur pipelines |
| Search typography | Inter Variable tuned jointly against three queries | Actual crop RMS remains 22.51 / 16.77 / 17.91 for chatgpt / spotify / discord; font shapes visibly differ |
| Application artwork | Resolved from installed desktop entries, normalized without replacing source assets | Linux and Mac application assets can differ |
| Input and launch behavior | Physical Super+Space, pointer Open, Enter launch, completion, staged Backspace, drag, file search, clipboard and menu protocols exercised | Some macOS-specific actions are absent and are not represented by fake controls |
| Installation / delivery | Installer round trip passed; 17 installed plugin files byte-identical to source; three repository remote heads verified | This proves delivery, not visual identity |

RMS and MAE numbers above measure different regions and quantities. They must not be averaged into a single similarity percentage. Details are in [MOTION.md](MOTION.md).

## Reference evidence limits

The source movie is variable-frame-rate, nominally 60 fps. An audit of original timestamps—not resampled output—found the following within moving intervals:

| Motion | Source frames | Median interval | Maximum interval | Intervals over 25 ms |
|---|---:|---:|---:|---:|
| Opening | 31 | 16.667 ms | 33.333 ms | 1 |
| Separation | 41 | 16.667 ms | 33.333 ms | 2 |
| Query clear | 38 | 16.667 ms | 33.333 ms | 1 |
| Closing | 10 | 16.667 ms | 33.334 ms | 1 |

Resampling repeats available frames; it cannot recover the missing images. The movie also has no timestamp for the originating physical key or pointer event. Aligning two visible onsets can compare animation shape but cannot establish equal input latency.

Compression noise does not explain the remaining font mismatch. Across 25 stable reference frames per query, temporal grayscale RMS medians were 0.00, 4.18 and 4.23; maxima were 0.00, 5.10 and 6.95. These are not directly interchangeable with the RGB reproduction metric, but the stable chatgpt sample alone rules out attributing all of its residual to temporal source noise. The reference uses Apple's system typography; this machine has Inter, not San Francisco. No Apple font assets are bundled.

## Next evidence needed

The optional [Mac reference capture tool](../tools/reference-mac/README.md) prepares a way to record display and input timestamps together and obtain lossless stills. Its Python analysis is tested; its Swift recorder is **not yet compiled or run on a Mac**. A successful real Mac run is necessary before trusting its output. Event-to-WindowServer timing would still not certify switch-to-photon latency.

A new reference can resolve sampling and event-alignment questions. It will not by itself make Qt/Inter glyphs identical to macOS system text or guarantee identical blur across all wallpapers. Those remaining differences must be assessed explicitly; they must not be hidden by declaring the goal complete.

No private reference video, backdrop or comparison crop is included in the repository.
