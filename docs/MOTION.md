# Motion measurements and verification

The supplied private reference was 2880×1800 at nominal 60 fps. Geometry was compared at 1440×900 logical resolution. Reference frames and wallpaper are deliberately not included.

| Property | Implemented |
|---|---|
| Search surface | 640×56 logical px |
| Split search surface | 384×56 logical px |
| Category buttons | 56 px diameter, 8 px gaps |
| Search offset | centered; top = 129/900 of screen height |
| Results | up to seven 56 px rows |
| Opening | 1.08 scale to 1, damped settling, 320 ms |
| Opacity | 150 ms opening / 100 ms closing |
| Results resize | 260 ms, cubic Bézier (0.22, 0, 0.18, 1) |
| Category separation | 300 ms, cubic in/out |
| Idle category reveal | 650 ms |
| Exact match | 420 ms after last edit |

Iterations corrected: opening animation direction (oversize-to-rest instead of undersize-to-rest), top alignment, body-resize curve, glass brightness and border, icon margins, first-result scroll positioning, cloned-plugin application discovery, and remembered-query timing.

The reference result collapse took roughly 250 ms: approximately 84% of its height remained after 33 ms, 55% after 67 ms, 30% after 100 ms and near zero after 250 ms. The chosen curve approximates that trace. Native compositor effects are disabled on this layer so they do not double-animate the QML surface.

Live checks cover physical-keycode Super+Space open/close and rapid toggles, exact-match collapse, Down to expand, Escape stages, Unicode filename lookup, discovery and launching of a temporary desktop entry, clipboard navigation, and the native selection/input response protocols. Validation was performed at scale 1 on two 1920×1080 monitors. Other scales are supported by Qt/SVG rendering but were not visually certified on this machine.

Remaining differences: Inter instead of Apple's San Francisco, platform blur and antialiasing, approximate spring timing, and different application/search data. The result is intentionally described as Spotlight-inspired rather than pixel-identical.

Sources: [Apple Spotlight guide](https://support.apple.com/guide/mac-help/find-what-you-need-with-spotlight-mchlp1008/mac), [Qt ShaderEffect](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html), [Hyprland layer rules](https://wiki.hypr.land/Configuring/Basics/Window-Rules/).
