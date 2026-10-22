# Motion measurements and verification

The private reference is a 2880×1800 Retina recording, nominally 60 fps with variable frame timing. Analysis uses the complete decoded timeline, resampled to 60 fps at 1440×900 logical resolution. Fast input seeking was not used for time-critical frame comparisons. No reference video, wallpaper, or private captures are distributed.

## Geometry and interaction

| Element | Logical measurement |
|---|---|
| Search surface | 640×56 px |
| Separated search surface | 384×56 px |
| Category circles | 27.5 px radius, 64 px center spacing |
| Surface corner radius | 28 px, including expanded results |
| Search text origin | 59.5 px (60 px with static font fallback) |
| First selected result | x=10, y=67, width=620, height=56, radius=18 |
| Result text origin | 71 px from surface left |
| Result icons | 29 px; original installed application icons |
| Inline app icon | 26 px |
| Inline Open button | 82×30 px, y=12, radius=11 |
| Result viewport | up to seven rows; 13 px bottom inset |
| Placement | horizontal center; top=129/900 of screen height |
| Glass | base alpha=0.785 with a separate edge and shadow |

A prefix match remains in the capsule with a completion suffix and Open action. Down expands the results without removing that action. Backspace first dismisses the completion, preserving the typed query. Hovering a category changes the placeholder and exposes the corresponding Linux shortcut. Reopening restores the remembered query and expanded/compact state.

## Fitted transitions

The canonical models use an underdamped second-order step response. The capsule width, each bead center, and each bead radius have independent parameters; a single easing progress value cannot reproduce the measured liquid shape.

- **Opening:** oversized-to-rest scale, frequency 22.0400 rad/s, damping ratio 0.6792, fitted onset offset 21.78 ms. The scale briefly dips below one. It is fixed at one after 500 ms. Scale-fit RMS error against the reference trace was 0.00023 (about 0.15 px across 640 px). Opacity is a separate 150 ms ramp.
- **Closing:** 100 ms fade with a small outward scale. Content stays intact through the fade and is cleared only once the layer is hidden.
- **Separation:** the initial empty opening waits 750 ms. Clearing a nonempty query starts separation immediately, overlapping the body collapse. The main width uses frequency 16.2205 rad/s and damping 0.6267; it reaches approximately 364 px before returning to 384. Four independently delayed beads form the right side. Their contour model was fitted to sampled reference outlines: RMS signed-distance residual 0.55 px, median 0.32 px. The smoothing radius decays so settled circles do not retain liquid bridges.
- **Merge:** beads move inward and shrink while the main capsule expands. The overall silhouette initially contracts. The main width uses frequency 16.1753 rad/s and damping 0.9176; independent bead parameters are in Motion.js. Fitted contour RMS residual was 0.79 px.
- **Result collapse:** frequency 22.0697 rad/s and damping 0.8338, including the small undershoot before settling. Fitted bottom-edge RMS residual was 1.26 px. The same model controls expansion. Interrupted result-count changes carry the existing height velocity into the next spring instead of restarting from rest. Data refreshes are coalesced so clearing and repopulating a model in one event does not create a false height pulse.
- **Surface interruption:** a new gesture starts at the previous position and velocity. Canonical delays apply to uninterrupted transitions; interrupted gestures use a continuous spring retarget.
- **Glyph reveal:** opacity is independent of the bead springs, using monotone interpolation through sampled reference contrast. Around 300 ms it is 0.49; at 400 ms, 0.785. All four glyphs share the reveal clock. Gaussian sigma falls from approximately 6.4 logical px at 267 ms to 1.51 px at 400 ms, then settles to zero. The former per-glyph stagger and generic Qt blur did not match this trace.
- **Visibility reversal:** repeated Super+Space preserves the current scale and its velocity. A Hermite correction rejoins the canonical opening/closing curve with zero residual offset and velocity; it does not change an uninterrupted opening.

These fit errors describe specific measured traces, not a claim that the entire UI is pixel-identical. Live captures also compare the shader-rendered silhouette at fixed phases; nominal model fit alone is not sufficient validation.

Glyph blur uses two separable Gaussian shader passes with padded, at-least-2× sources. A neutral-background calibration rendered sigma values 0–7.5 px and fitted the output against the unblurred glyph: requested 0.75, 1.5, 3 and 4.5 measured as 0.75, 1.5, 3 and 4.5 px. This validates the renderer's blur units; it does not establish that our glyph artwork equals Apple's. On the installed launcher at 300/400/500 ms, the first glyph measured contrast 0.476/0.779/0.985 and sigma 4.4/1.5/0.6 px. The moving surface and pixel registration limit low-opacity and subpixel estimates.

Opening is now deferred until Qt submits the window's first transparent frame (`Window.frameSwapped`), avoiding progression while Wayland maps it. In a four-repeat GPU-recorded expanded-panel test, the first visible scale was 1.0925–1.0935; before synchronization, two repeats started at 1.072. Some captures still omit an intermediate motion step. This is not a guarantee of zero dropped frames or exact physical-key latency.

The reference's material regression against the raw wallpaper estimated alpha near 0.715. Applying that value directly through Hyprland was too bright and blue. A second calibration compared actual composited captures against the same reference background and selected alpha 0.785 with a compensated base color. In fixed text-free regions, mean absolute 8-bit channel error fell from 1.18 to 0.94 in the header and from 1.69 to 0.76 in the body. This is a measured correction for this compositor configuration, not a universally identical material across arbitrary blur settings.

### Clear-query sequencing

The initial delay must not be reused after every deletion. Reference analysis matched the empty placeholder against a stable template, then detected the first silhouette narrower than 630 px. Nine clear-query transitions showed 50–117 ms from visible placeholder to that width threshold (most 50–67 ms). The earlier code restarted a 750 ms idle timer on every clear, which introduced a long pause after the body collapsed. It now distinguishes an initial empty opening from clearing an existing query.

A GPU-recorded installed run measured 49.984 ms with the same placeholder/width method. The width threshold includes the first visible portion of the spring; this is not a measurement of keyboard input latency. Native key testing confirms the initial idle wait still applies. Rapid result-count changes also verified nonzero carried height velocity, finite positive heights and settled endpoints.

## Typography and small controls

The input uses the installed Inter Variable face at 25 px, weight axis 475 and optical-size axis 24, with −0.25 px letter spacing. The placeholder and completion use the same rendering path. If that face is absent, the existing Inter Display 26 px fallback remains. Three reference queries (chatgpt, spotify, discord) were evaluated together so one string could not determine the choice. In the neutral font-grid fit, combined grayscale RMS fell from 23.80 to 19.64 intensity levels. Live RGB crops measured 22.51, 16.77 and 17.91 respectively; these residuals still show that this is not San Francisco.

The Open label uses Inter 15 px/500 with independently positioned dash and text. Its fixed-region mean absolute RGB error fell from 8.87 to 2.44 before the input-font change. The search mark's measured circle radius is 8.35 px with a 1.9 px stroke; its handle uses a 2.66 px stroke. Live grayscale RMS in the search-mark crop fell from 16.43 to 3.73. The reference video and all comparison crops stay private.

Selected rows use a small action description and keycap. They describe actual Linux behavior: Open, Paste, Run or Select with Enter. They do not advertise macOS's app-specific “Search …”/Tab integration, which is absent here. Original local app artwork remains the source; its drawing can differ from the Mac app's asset. For Spotify's unframed circle, the automatically added plate is near black so its silhouette remains visible on dark glass.

## Verification

`node tests/test_motion.js` checks measured width samples, opening/collapse undershoot, finite geometry, settled endpoints, position/velocity continuity on interruption, measured glyph contrast/blur, and visibility-reversal continuity. `python3 tests/test_install.py` checks isolated install/update/uninstall restoration.

Live checks cover physical-keycode Super+Space open/close and rapid toggles, prefix completion, staged Backspace, Down expansion, retained inline actions, reopening, empty-field dragging with position retention, nonempty text selection, clickable inline Open, Unicode filename lookup, actual desktop-entry discovery/launching, clipboard navigation, and native selection/input response protocols. Testing uses two 1920×1080 scale-1 monitors. Higher and fractional scales are not visually certified on this machine.

## Limits still under review

Inter Variable, Inter and Inter Display are used instead of San Francisco. Qt text rasterization and Hyprland backdrop blur differ from macOS. The recording cannot reveal the exact physical input timestamps or Apple's internal animation parameters. Search contents reflect local Linux applications and Omarchy providers. Live opening verification exposed and corrected two integration errors: a Behavior could start with the previous direction’s duration/easing, and an unmapped PanelWindow could report zero dimensions. Opening/closing now use explicit animations and dimensions come from the screen. Unchanged result models are retained and icon rescans are deferred past the opening.

Those differences must not be hidden by calling the entire result pixel-identical.

Sources: [Apple Spotlight guide](https://support.apple.com/guide/mac-help/find-what-you-need-with-spotlight-mchlp1008/mac), [Qt variable font axes](https://doc.qt.io/qt-6/qml-font.html#variableAxes-prop), [Qt ShaderEffect](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html), [Qt Window frame signals](https://doc.qt.io/qt-6/qml-qtquick-window.html#frameSwapped-signal), [Hyprland layer rules](https://wiki.hypr.land/configuring/core/rules/layer-rules/).
