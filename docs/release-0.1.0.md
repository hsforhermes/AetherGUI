# v0.1.0 — first public release

A native macOS menu-bar front end for the [Aether](https://github.com/CluvexStudio/Aether)
CLI WARP client.

## Features

- One-click connect; the menu title shows live state, plus exit IP and country
  once the tunnel is up.
- Protocol (MASQUE / WireGuard / Gool / MIM), transport (H3 / H2), scan mode,
  and obfuscation presets as submenus with a checkmark on the current choice.
- Live log in a separate window (`⌘L`) or embedded directly in the dropdown
  menu, resizable 80–480 px, read-only and auto-scrolling.
- Set and clear the macOS system SOCKS5 proxy across every network service in
  one click.
- Restart the tunnel without relaunching. Start at login. Connect on launch.
- **Advanced…** submenu for gateway override, listen address, and extra flags.
  No preferences window.
- Settings persist in `UserDefaults`.

## Included

`make-verge-profile.sh` — chains Aether underneath Clash Verge so every
subscription node is reachable through the tunnel. See the README.

## Notes

- Requires the Aether binary at `~/bin/aether/aether`.
- Ad-hoc signed, so the first launch needs right-click → **Open**.
- Version `0.1.0` because the app is young; `1.0.0` will mean feature-complete
  and proven on restricted networks.
