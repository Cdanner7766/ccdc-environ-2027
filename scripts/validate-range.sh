#!/usr/bin/env bash
# validate-range.sh <range_/24_prefix>   e.g. ./validate-range.sh 10.2.10
#
# Read-only, post-deploy validation. Confirms each service is up and the
# intended-weak state is present. Does NOT exploit anything — it checks the lab
# was provisioned correctly. Run from a host on the range VPN.
set -uo pipefail

PFX="${1:-}"
if [ -z "$PFX" ]; then
  echo "usage: $0 <range /24 prefix, e.g. 10.2.10>" >&2; exit 2
fi

# host octets (match ludus-range-config.yml)
DC=$PFX.105; TAT=$PFX.9; KAM=$PFX.11
TYT=$PFX.201; ASH=$PFX.202; BOG=$PFX.203; SING=$PFX.134; WOO=$PFX.20; COR=$PFX.253

pass=0; fail=0
ok()  { printf '  [ OK ] %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

port() { # host port label
  if timeout 5 bash -c ">/dev/tcp/$1/$2" 2>/dev/null; then ok "$3 ($1:$2 open)"; else bad "$3 ($1:$2 closed)"; fi
}
http() { # url label [grep-string]
  body=$(curl -fsS --max-time 8 "$1" 2>/dev/null) || { bad "$2 ($1 no response)"; return; }
  if [ -n "${3:-}" ]; then
    printf '%s' "$body" | grep -qi "$3" && ok "$2 (serving, matched '$3')" || bad "$2 (served but missing '$3')"
  else ok "$2 (serving)"; fi
}

echo "== Core / AD =="
port "$DC" 53 "Deathstar DNS"
port "$DC" 389 "Deathstar LDAP"

echo "== Shared DB (Ashla) =="
port "$ASH" 3306 "Ashla MariaDB"

echo "== Payment web (Tython) — SQLi front end =="
http "http://$TYT/" "Tython site"
http "http://$TYT/pay.php?id=1" "Tython pay.php" "memo\|amount\|Query"
# intended exposure: the served .git/ on the web host
http "http://$TYT/.git/config" "Tython served .git/ (intended leak)" "repositoryformatversion"

echo "== Gitea (Corellia) — committed creds leak =="
port "$COR" 3000 "Corellia Gitea"
http "http://$COR:3000/wuher/payments/raw/branch/main/config.php" \
     "Corellia committed config.php (intended leak)" "pass"

echo "== Menu/site + FTP (Wookie) — DB read path #2 =="
http "http://$WOO/menu.php" "Wookie menu" "Menu\|Blue Milk"
port "$WOO" 21 "Wookie FTP"

echo "== Mail (Bogan) — AD overlap =="
port "$BOG" 25 "Bogan SMTP"
port "$BOG" 143 "Bogan IMAP"

echo "== Kamino droid / Sing3PO karaoke =="
http "http://$KAM/" "Kamino droid page" "Droid"
http "http://$SING/" "Sing3PO karaoke page" "Karaoke"

echo
printf 'validation: %d ok, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
