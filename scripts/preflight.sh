#!/usr/bin/env bash
# preflight.sh — read-only checks before deploying the STAR BARS range.
# Safe to run repeatedly. Exits non-zero if a hard requirement is missing.
set -uo pipefail

pass=0; warn=0; fail=0
ok()   { printf '  [ OK ] %s\n' "$1"; pass=$((pass+1)); }
note() { printf '  [WARN] %s\n' "$1"; warn=$((warn+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

echo "== Ludus CLI =="
if command -v ludus >/dev/null 2>&1; then ok "ludus CLI present ($(command -v ludus))"
else bad "ludus CLI not found in PATH"; fi

echo "== br_netfilter (Proxmox host) =="
if lsmod 2>/dev/null | grep -q '^br_netfilter'; then ok "br_netfilter loaded"
else note "br_netfilter not loaded (inter-host filtering/router may misbehave) — see CLAUDE.md"; fi
vnf=$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo "?")
if [ "$vnf" = "1" ]; then ok "net.bridge.bridge-nf-call-iptables = 1"
else note "net.bridge.bridge-nf-call-iptables = $vnf (expected 1) — see CLAUDE.md fix"; fi

echo "== Ansible collections (pinned) =="
if command -v ansible-galaxy >/dev/null 2>&1; then
  installed=$(ansible-galaxy collection list 2>/dev/null)
  for c in microsoft.ad ansible.windows community.windows community.mysql ansible.posix; do
    if printf '%s' "$installed" | grep -q "^$c "; then ok "collection $c installed"
    else note "collection $c missing — run: ansible-galaxy collection install -r ansible/requirements.yml"; fi
  done
else note "ansible-galaxy not found — cannot verify collections"; fi

echo "== passlib (password_hash filter) =="
if python3 -c 'import passlib' 2>/dev/null; then ok "passlib present"
else note "passlib not importable — Bogan/Wookie password_hash may fail; install python3-passlib"; fi

echo "== Templates =="
if command -v ludus >/dev/null 2>&1; then
  tl=$(ludus templates list 2>/dev/null || true)
  if [ -n "$tl" ]; then
    for t in win2019-server-x64 win10-22h2-x64-enterprise win2016-server-x64 \
             debian-12-x64-server rocky-9-x64-server; do
      line=$(printf '%s' "$tl" | grep -E "\b${t}(-template)?\b" | head -1)
      if   printf '%s' "$line" | grep -qi 'built'   ; then ok "template $t: built"
      elif [ -n "$line" ]                            ; then note "template $t: not built yet"
      else note "template $t: not found (check name / no-security-updates variant)"; fi
    done
  else note "could not read 'ludus templates list'"; fi
fi

echo
printf 'preflight: %d ok, %d warn, %d fail\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ]
