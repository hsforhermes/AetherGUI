## v0.1.2 — "port already in use" fix

If you force-quit or the app crashed, its `aether` tunnel could be left
running — reparented to launchd, still holding the SOCKS5 port. Every later
launch then hit a dead-end error:

> Another program is listening on 127.0.0.1:1819. Stop it, or change the
> SOCKS5 address in Advanced.

…when the "another program" was Aether's own leftover from an earlier session.

### What changed

- **The tunnel can no longer outlive the app.** It now runs inside a tiny
  `/bin/sh` wrapper that watches the app's pid and takes the tunnel down the
  moment the app disappears — so a force-quit or crash can't strand it. A
  watchdog inside the app can't do this job; it dies the instant the app does.
- **If the port is somehow still held**, the app checks whether the holder is a
  leftover Aether tunnel and offers to **stop it and reconnect**, instead of the
  old dead-end message. A genuinely foreign program is still reported by name.
- **The port check was also wrong.** It treated any `lsof` line containing a
  colon as "busy", which matched the header row and unrelated entries — so it
  could claim the port was in use when it was free. It now matches the exact
  `host:port`.

Verified: with a live tunnel, `SIGKILL`-ing the app takes both the tunnel and
the port down (no orphan, port free); the wrapper logic was also tested in
isolation before wiring it in. Regression suite still passes.
