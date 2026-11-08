# hypr-overview

A Windows-style task switcher for Hyprland, written for [Quickshell](https://quickshell.org).

Press **Super+Tab** and every monitor shows live thumbnails of all the windows that
live on it, from every workspace. Click one and its monitor switches to that window's
workspace and focuses it; the other monitors keep what they were showing. Or keep
Super held, tap Tab / Shift+Tab to move the highlight through every window on every
monitor (most recently used first), and let go of Super to switch.

- **Esc** or a click on empty space: cancel
- **Middle click** on a tile: close that window
- Arrow keys / Enter also work while it is open

## Running

```sh
qs -p /path/to/hypr-overview              # the daemon (stays resident, hidden)
qs -p /path/to/hypr-overview ipc call overview open   # bind to SUPER, Tab
qs -p /path/to/hypr-overview ipc call overview prev   # bind to SUPER SHIFT, Tab
```

IPC functions: `open`, `prev`, `toggle`, `commit`, `close`, `state` (JSON, for debugging).

Windows on special workspaces (scratchpads) are skipped, except `special:minimized`
windows tagged `glade-min-<monitor>`, which show on the monitor they came from.

## Theme

`~/.config/hypr-overview/theme.json` overrides any of `backdrop`, `tile`, `tileHover`,
`accent`, `text`, `dim` (colours, `#aarrggbb` allowed), `radius`, `font`. It is
reloaded when it changes.

Packaged for NixOS in
[landonreekstin/nixos-config](https://github.com/landonreekstin/nixos-config)
(`pkgs/hypr-overview`).
