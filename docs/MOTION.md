# Motion measurements and verification

The private reference is a 2880×1800 Retina recording, nominally 60 fps with variable frame timing. Analysis uses the complete decoded timeline, resampled to 60 fps at 1440×900 logical resolution. Fast input seeking was not used for time-critical frame comparisons. No reference video, wallpaper, or private captures are distributed.

## Geometry and interaction

| Element | Logical measurement |
|---|---|
| Search surface | 640×56 px |
| Separated search surface | 384×56 px |
| Category circles | 27.5 px radius, 64 px center spacing |
| Surface corner radius | 28 px, including expanded results |
| Search text origin | 60 px from surface left |
| First selected result | x=10, y=67, width=620, height=56, radius=18 |
| Result text origin | 71 px from surface left |
| Result icons | 32 px; original installed application icons |
| Result viewport | up to seven rows; 13 px bottom inset |
| Placement | horizontal center; top=129/900 of screen height |
| Glass | base alpha=0.785 with a separate edge and shadow |

A prefix match remains in the capsule with a completion suffix and Open action. Down expands the results without removing that action. Backspace first dismisses the completion, preserving the typed query. Hovering a category changes the placeholder and exposes the corresponding Linux shortcut. Reopening restores the remembered query and expanded/compact state.

## Fitted transitions

The canonical models use an underdamped second-order step response. The capsule width, each bead center, and each bead radius have independent parameters; a single easing progress value cannot reproduce the measured liquid shape.

- **Opening:** oversized-to-rest scale, frequency 22.0400 rad/s, damping ratio 0.6792, fitted onset offset 21.78 ms. The scale briefly dips below one. It is fixed at one after 500 ms. Scale-fit RMS error against the reference trace was 0.00023 (about 0.15 px across 640 px). Opacity is a separate 150 ms ramp.
- **Closing:** 100 ms fade with a small outward scale. Content stays intact through the fade and is cleared only once the layer is hidden.
- **Separation:** starts after 750 ms idle. The main width uses frequency 16.2205 rad/s and damping 0.6267; it reaches approximately 364 px before returning to 384. Four independently delayed beads form the right side. Their contour model was fitted to sampled reference outlines: RMS signed-distance residual 0.55 px, median 0.32 px. The smoothing radius decays so settled circles do not retain liquid bridges.
- **Merge:** beads move inward and shrink while the main capsule expands. The overall silhouette initially contracts. The main width uses frequency 16.1753 rad/s and damping 0.9176; independent bead parameters are in Motion.js. Fitted contour RMS residual was 0.79 px.
- **Result collapse:** frequency 22.0697 rad/s and damping 0.8338, including the small undershoot before settling. Fitted bottom-edge RMS residual was 1.26 px. The same model controls expansion. Data refreshes are coalesced so clearing and repopulating a model in one event does not create a false height pulse.
- **Interruption:** a new gesture starts at the previous position and velocity. Canonical delays apply to uninterrupted transitions; interrupted gestures use a continuous spring retarget.

These fit errors describe specific measured traces, not a claim that the entire UI is pixel-identical. Live captures also compare the shader-rendered silhouette at fixed phases; nominal model fit alone is not sufficient validation.

The reference's material regression against the raw wallpaper estimated alpha near 0.715. Applying that value directly through Hyprland was too bright and blue. A second calibration compared actual composited captures against the same reference background and selected alpha 0.785 with a compensated base color. In fixed text-free regions, mean absolute 8-bit channel error fell from 1.18 to 0.94 in the header and from 1.69 to 0.76 in the body. This is a measured correction for this compositor configuration, not a universally identical material across arbitrary blur settings.

## Verification

`node tests/test_motion.js` checks measured width samples, opening/collapse undershoot, finite geometry, settled endpoints, and position/velocity continuity on interruption. `python3 tests/test_install.py` checks isolated install/update/uninstall restoration.

Live checks cover physical-keycode Super+Space open/close and rapid toggles, prefix completion, staged Backspace, Down expansion, retained inline actions, reopening, empty-field dragging with position retention, nonempty text selection, clickable inline Open, Unicode filename lookup, actual desktop-entry discovery/launching, clipboard navigation, and native selection/input response protocols. Testing uses two 1920×1080 scale-1 monitors. Higher and fractional scales are not visually certified on this machine.

## Limits still under review

Inter and Inter Display are used instead of San Francisco. Qt text rasterization and Hyprland backdrop blur differ from macOS. The recording cannot reveal the exact physical input timestamps or Apple's internal animation parameters. Search contents reflect local Linux applications and Omarchy providers. Live opening verification exposed and corrected two integration errors: a Behavior could start with the previous direction’s duration/easing, and an unmapped PanelWindow could report zero dimensions. Opening/closing now use explicit animations and dimensions come from the screen. Unchanged result models are retained and icon rescans are deferred past the opening.

Those differences must not be hidden by calling the entire result pixel-identical.

Sources: [Apple Spotlight guide](https://support.apple.com/guide/mac-help/find-what-you-need-with-spotlight-mchlp1008/mac), [Qt ShaderEffect](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html), [Qt MultiEffect](https://doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html), [Hyprland layer rules](https://wiki.hypr.land/Configuring/Basics/Window-Rules/).
