# AetherGUI

A native macOS menu-bar front end for [Aether](https://github.com/CluvexStudio/Aether) — a Rust userspace WARP client built for censored networks.

Aether ships as a command-line tool. It works, but it lives in a terminal: to
connect you open a shell, type a command, and leave it running. This app puts it
in the menu bar where it belongs. Click the bolt icon to connect, switch
presets, watch the log, and go back to work.

## What it does

- **One-click connect** with live status in the menu bar title, including your
  exit IP and country once the tunnel is up.
- **Protocol, transport, scan mode, and obfuscation presets** — everything
  Aether exposes as flags, as a plain submenu with a checkmark on the current
  choice. Changes apply on the next connect.
- **The log, three ways**: a separate window (`⌘L`), or live *inside* the
  dropdown menu with `Show log inside menu` — useful when you just want proof
  the tunnel is actually running, without a window in your face. Resizable
  between 80 and 480 px.
- **System proxy control**: set and clear the macOS SOCKS5 proxy for every
  network service in one click, so browsers pick up the tunnel immediately.
- **Restart the tunnel** without relaunching the app.
- **Start at login**, plus an option to connect automatically on launch.
- **Remembers everything** in `UserDefaults`. No config file to hand-edit.

Everything is read-only or one-click — the log never takes input, and there is
no preferences window. The few advanced values (gateway override, listen
address, extra flags) live under **Advanced…** in the menu, each as a small
native prompt.

## Requirements

- macOS 13 or later, Apple Silicon or Intel
- Aether installed at `~/bin/aether/aether`

Install Aether by grabbing the release archive for your platform:

```bash
mkdir -p ~/bin/aether
curl -L https://github.com/CluvexStudio/Aether/releases/download/v2.3.0/aether-macos-arm64.tar.gz \
  | tar -xz -C ~/bin/aether
chmod +x ~/bin/aether/aether
```

On Intel Macs use `aether-macos-x86_64.tar.gz`. The archive also contains the
`pt/` helper binaries, which Aether needs — keep the folder layout intact.

If the binary is missing, the app tells you where it expected it and quits
rather than failing silently.

## Build

```bash
./build.sh
```

This compiles `main.swift` with `swiftc -O`, bundles it as
`~/Applications/Aether.app` with an `LSUIElement` (menu-bar only, no Dock icon),
and ad-hoc signs it. Requires Xcode command-line tools.

Because the signature is ad-hoc, the first launch may need a right-click →
**Open**. After that it opens normally.

## Usage

Click the bolt icon in the menu bar. The title shows your state:

| Title | Meaning |
|---|---|
| `Aether` | Idle |
| `Connecting…` | Scan running, gateway being found |
| `IP · CC` | Connected, e.g. `104.28.192.78 · ES` |

Presets worth knowing:

- **Scan mode** — how hard Aether hunts for a reachable gateway. `Turbo` is
  fast but fragile, `Ironclad` tests each candidate with real traffic before
  trusting it. `Balanced` is the default and a good compromise.
- **Obfuscation** — how the traffic is disguised. `Off` is fastest, `GFW` and
  `Aggressive` are for heavy DPI environments.
- **Gateway override** — under **Advanced…**. Leave it empty to let Aether
  scan. Set it to pin a specific gateway, e.g. `162.159.192.1:443`.

## Chaining through Clash Verge

A common setup: Aether gets you past the local block, then you want a specific
country exit on top. You can run Aether underneath Clash Verge so that *every
Verge node* is reachable through the tunnel.

Run `./make-verge-profile.sh` to fetch your subscription, inject
`dialer-proxy: Aether-WARP` into every node, and write `verge-aether.yaml`:

```bash
./make-verge-profile.sh
```

Then in Verge: **Profiles → New → Local**, pick `verge-aether.yaml`, activate
it. Keep Aether connected and pick any node — the traffic goes
`browser → Clash → WARP → node → site`, so **the site sees the node's IP, not
WARP's**. This is the mechanism for reaching nodes whose server IP is blocked.

Two things to know:

- **Use Verge's TUN mode**, not just System Proxy, if you want everything
  tunneled including apps that ignore proxy settings. But TUN also captures
  Aether's own outbound, which risks a routing loop. Add
  `IP-CIDR,162.159.192.0/24,direct,no-resolve` to Verge's rules to keep the
  WARP gateway outside the tunnel.
- **Latency rankings will look odd**: Verge's url-test probes now measure the
  node *through* WARP, so fast-looking nodes are the ones with the least WARP
  overhead. That is expected, not a fault.

Re-run the script whenever your subscription's nodes change. `verge-aether.yaml`
is deliberately gitignored — it contains live credentials.

## License

AGPL-3.0. This app drives Aether, which is AGPL-3.0, so it inherits the same
terms: if you modify this and let others use it over a network, you must offer
them your source.
