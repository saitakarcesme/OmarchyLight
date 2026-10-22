# OmarchyLight

A Spotlight-inspired Super+Space launcher for Omarchy. A translucent search capsule separates into four category buttons, merges when typing, offers inline application completion, and expands into results when requested.

![OmarchyLight](docs/preview.png)

[Watch the actual 60 fps desktop capture](docs/demo.mp4) · [Results view](docs/results.png)

Media is captured from the running desktop over a neutral test background.

## What it does

- Searches installed desktop applications using their original local artwork. Icon padding and rounded backgrounds are prepared automatically; existing icon frames are preserved.
- Opens existing Omarchy actions, nested menus, providers and user menu extensions.
- Searches local filenames in Desktop, Documents, Downloads, Pictures, Music and Videos.
- Reads the existing Omarchy clipboard history; it does not add a clipboard recorder.
- Keeps Omarchy's `menu select` and `menu input` protocols working for system workflows.
- Opens on the focused monitor, supports text selection/paste/IME, remembers the last root query during the session, and accepts keyboard or pointer navigation.

## Controls

| Input | Action |
|---|---|
| Super+Space | Open / close |
| Type | Search applications and Omarchy actions |
| Tab | Next category |
| Ctrl+1 / 2 / 3 / 4 | Applications / files / actions / clipboard |
| Up / Down | Select a result; Down expands a compact match while keeping its inline action |
| Backspace on a completion | Dismiss completion first; subsequent presses edit the query |
| Right on a completion | Accept the suggested suffix |
| Page Up / Page Down | Move six rows |
| Enter | Run selected result |
| Escape | Clear query, return to root, then close |
| Ctrl+Delete | Show native uninstall confirmation for an application |
| Drag the upper edge | Move the panel within the monitor |

## Motion and fidelity

Geometry and transitions were measured from a supplied 60 fps Spotlight recording. The implementation uses a single signed-distance-field glass surface, not overlapping opaque rectangles. Main dimensions are 640×56 logical pixels; the compact search area is 384 pixels and category circles have a 27.5 pixel radius inside 56 pixel hit targets. Result rows are 56 pixels. The top edge stays fixed while the result body changes height.

Opening, liquid separation, merging and result resizing use independent damped spring models fitted to reference frames. Separation first contracts the capsule, then releases four beads with different delays and overshoot. Typing reverses the visual flow: the beads move inward before the capsule fills its final width. Interrupted gestures preserve position and velocity. The glass uses approximately 78.5% base opacity, calibrated against the compositor output. See [measurements and verification](docs/MOTION.md).

**This is a measured visual recreation, not Apple's Spotlight implementation.** Font rasterization, compositor blur, display scaling and frame scheduling differ. It does not claim mathematically identical pixels or animation frames. File search is bounded filename search, not a full content index; Siri, Apple Intelligence, cloud search, calculator and native macOS quick actions are not implemented. Omarchy actions remain available through their existing providers.

The file scan skips hidden/dependency directories, limits depth to five, and stops after about 1.2 seconds or 30,000 entries. No network search or telemetry is added.

## Get it

```sh
git clone https://github.com/saitakarcesme/OmarchyLight.git
cd OmarchyLight
```

Extra dependencies: ImageMagick, `gtk-launch`, `uwsm-app`. The compiled shader is included; rebuild after shader edits with:

```sh
/usr/lib/qt6/bin/qsb --qt6 -o plugin/shaders/glass.frag.qsb plugin/shaders/glass.frag
```

## Requirements

This targets **Omarchy's Quickshell desktop and Hyprland Lua configuration**, tested with Hyprland 0.56.2, Quickshell 0.3.2 and Qt 6.12. Older Waybar/Walker Omarchy releases are not supported. Python 3 and the normal Omarchy command-line tools must be installed. The UI uses Inter and Inter Display (with the system font fallback if unavailable). ImageMagick prepares installed artwork into the user cache; no replacement brand assets are bundled.

## Install / update

```sh
./install.sh --dry-run
./install.sh
```

Run as your normal desktop user, not root. The installer checks dependencies, backs up replaced files under `~/.local/state/`, writes only user configuration, and reloads the affected shell. Running it again updates the installation while retaining the original uninstall baseline. It never edits `/usr/share/omarchy` or installs packages automatically.

## Uninstall

```sh
./uninstall.sh
```

The installer restores original files, removes its marked Lua blocks and preserves unrelated settings. Locally modified source files are retained with a message; use `./uninstall.sh --force` only to discard those edits. Backups remain available. `--no-reload` is available for offline installation. Install the three companion projects in any order; each can also be used independently.

## Development

```sh
python3 tests/test_install.py
```

The installer test uses a temporary home directory and never touches the real desktop. Test UI changes in a running Omarchy session; QML imports depend on the installed Omarchy shell.

## License and attribution

MIT; see [LICENSE](LICENSE) and [NOTICE](NOTICE). Portions derive from [Omarchy](https://github.com/basecamp/omarchy). Independent community work, not affiliated with or endorsed by Apple. No Apple fonts, SF Symbols, wallpapers, recordings or application icon packs are distributed. Applications retain their owners' branding and resolve their artwork from the local installation.

## Companion projects

- [Omarchy-MacOS-Dock](https://github.com/saitakarcesme/Omarchy-MacOS-Dock)
- [Omarchy-MacOS-MenuBar](https://github.com/saitakarcesme/Omarchy-MacOS-MenuBar)

Motion regression checks: `node tests/test_motion.js`. Installer round trip: `python3 tests/test_install.py`.
