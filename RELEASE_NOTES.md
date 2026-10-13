# AetherGUI

A native macOS menu-bar front end for [Aether](https://github.com/CluvexStudio/Aether),
the Rust userspace WARP client for censored networks. Aether is a CLI tool;
this puts connect/disconnect, preset switching, and a live log in the menu bar.

Single Swift file, no dependencies, built with `swiftc`.

## Install

Requires the Aether binary at `~/bin/aether/aether`:

```bash
mkdir -p ~/bin/aether
curl -L https://github.com/CluvexStudio/Aether/releases/download/v2.3.0/aether-macos-arm64.tar.gz \
  | tar -xz -C ~/bin/aether
chmod +x ~/bin/aether/aether
```

## Build

```bash
./build.sh
```

Compiles `main.swift`, bundles `~/Applications/Aether.app` (menu-bar only, no
Dock icon), ad-hoc signs it. The ad-hoc signature means the first launch may
need right-click → **Open**; after that it opens normally.

## Features

- One-click connect; menu title shows state, plus exit IP and country once up.
- Protocol (MASQUE / WireGuard / Gool / MIM), transport (H3 / H2), scan mode,
  and obfuscation presets, all as submenus with a checkmark on the current
  choice.
- Live log in a separate window (`⌘L`) *or* embedded directly in the dropdown
  menu — resize 80–480 px, read-only, auto-scrolling.
- Set and clear the macOS system SOCKS5 proxy for every network service in one
  click.
- Restart the tunnel without relaunching. Start at login. Connect on launch.
- Advanced values (gateway override, listen address, extra flags) under
  **Advanced…** as small native prompts — no preferences window.
- All settings persist in `UserDefaults`.

## Chaining through Clash Verge

Run Aether underneath Clash Verge so every Verge node is reachable through the
tunnel:

```bash
./make-verge-profile.sh   # writes verge-aether.yaml
```

Then Verge → **Profiles → New → Local** → `verge-aether.yaml`, and activate.
Keep Aether connected. Traffic goes `browser → Clash → WARP → node → site`, so
the site sees the **node's** IP, not WARP's — this is how you reach nodes whose
server IP is blocked.

- Use Verge's **TUN mode** to tunnel everything including apps that ignore
  proxy settings. TUN also captures Aether's own outbound, so add
  `IP-CIDR,162.159.192.0/24,direct,no-resolve` to Verge's rules to keep the
  WARP gateway out of the tunnel and avoid a routing loop.
- Latency rankings will skew: Verge's probes now measure node-over-WARP.

`verge-aether.yaml` is gitignored — it holds live subscription credentials.
Re-run the script when your nodes change.

## License

AGPL-3.0. Inherits Aether's terms: modified copies served over a network must
publish their source.
