#!/usr/bin/env bash
# Build a Clash Verge profile from the WhiteDNS subscription where every node
# is dialed THROUGH Aether's WARP SOCKS5 proxy (dialer-proxy).
#
# Why a script: mihomo only accepts `dialer-proxy` on individual proxies[]
# entries, never on proxy-groups. The subscription keeps all its nodes inline
# in `proxies:`, so the field has to be injected into each entry. Re-run this
# to pick up node changes; the output path is stable, so the Verge profile
# keeps working without re-importing.
set -euo pipefail

SUB_URL="https://sub.iampedi5.live/sub/mihomo.yaml"
OUT="/Users/hosseinsamani/dev/aether-gui/verge-aether.yaml"
AETHER_NAME="Aether-WARP"
AETHER_PORT="1819"

echo "→ fetching subscription"
curl -sS -m 60 -L "$SUB_URL" -o /tmp/aether-sub-raw.yaml
echo "  $(grep -c '^  - ' /tmp/aether-sub-raw.yaml) list items, $(wc -l < /tmp/aether-sub-raw.yaml) lines"

python3 - /tmp/aether-sub-raw.yaml "$OUT" "$AETHER_NAME" "$AETHER_PORT" <<'PY'
import sys, io, re

raw_path, out_path, name, port = sys.argv[1:5]
lines = io.open(raw_path, encoding='utf-8').read().split('\n')

# A YAML block scalar (`key: >-`, `key: |`, with optional chomping indicator).
# Continuation lines are indented deeper than the key and may be separated
# from it by blank lines, so a naive "last non-blank line" cut lands inside
# the scalar and corrupts the file.
BLOCK_SCALAR = re.compile(r'^\s*[^\s:#][^:]*:\s*[>|][+-]?\d*\s*(#.*)?$')

def logical_end(block):
    """Index just past the last line of this mapping, scalar-aware."""
    i, n, end = 0, len(block), 0
    while i < n:
        line = block[i]
        if not line.strip():
            i += 1
            continue
        end = i + 1
        m = BLOCK_SCALAR.match(line)
        if m:
            key_indent = len(line) - len(line.lstrip())
            j = i + 1
            while j < n:
                nxt = block[j]
                if not nxt.strip():
                    j += 1
                    continue
                if len(nxt) - len(nxt.lstrip()) <= key_indent:
                    break
                j += 1
            i = j
        else:
            i += 1
    return end

start = next(i for i, l in enumerate(lines) if l == 'proxies:')
end = next((i for i in range(start + 1, len(lines))
            if lines[i] and not lines[i][0].isspace()), len(lines))
body = lines[start + 1:end]

starts = [i for i, l in enumerate(body) if l.startswith('  - ')]
dialer = '    dialer-proxy: %s' % name
new_body, injected = [], 0
for k, s in enumerate(starts):
    e = starts[k + 1] if k + 1 < len(starts) else len(body)
    block = body[s:e]
    if not any('dialer-proxy' in l for l in block):
        block[logical_end(block):logical_end(block)] = [dialer]
        injected += 1
    new_body += block

proxy_entry = [
    '  - name: "%s"' % name,
    '    type: socks5',
    '    server: 127.0.0.1',
    '    port: %s' % port,
    '    udp: true',
]
out = lines[:start + 1] + proxy_entry + [''] + new_body + lines[end:]
io.open(out_path, 'w', encoding='utf-8').write('\n'.join(out))
print("  injected dialer-proxy into %d of %d proxy entries" % (injected, len(starts)))
print("  wrote %s" % out_path)
PY

echo "→ validating config with the mihomo binary"
MIHOMO="/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo"
if [ -x "$MIHOMO" ]; then
  if "$MIHOMO" -t -f "$OUT" -d /tmp/aether-mihomo-test 2>&1 | tail -5; then
    echo "  config OK"
  else
    echo "  VALIDATION FAILED"; exit 1
  fi
else
  echo "  (mihomo not found, skipped)"
fi
