# CLAUDE.md — CCDC STAR BARS range (Ludus)

Guidance for a Claude agent working on this repository, including an
autonomous agent running on the Ludus / Proxmox server that deploys and
validates the range.

## What this repo is

A 9-host CCDC practice range for **defensive training**, built on
[Ludus](https://docs.ludus.cloud) (Proxmox). It is modeled on the WRCCDC Inv6 /
STAR BARS team packet. Every host has a realistic dependency on another so the
intentional weaknesses **chain** rather than sitting on isolated boxes.

`README.md` is the human overview. `docs/topology.md` is the per-host intent.
`docs/RUNBOOK.md` is the step-by-step deploy + validate procedure. This file is
the operating contract.

## Golden rules (do not break these)

1. **Static vulnerable configs only. No attack tooling.** This repo stands up
   intentionally weak services and seeds target data. It must never contain
   exploit code, red-team automation, reverse shells, C2, or scripts that
   *perform* attacks. The owner does manual red-teaming separately. Validation
   checks service health and that the intended-weak state is present — it does
   not exploit anything.
2. **Isolated range only.** Every credential here is a deliberately weak,
   synthetic lab secret and is committed on purpose. Never reuse these anywhere
   real, and never expose the range to a production or shared network.
3. **Card/PII data is synthetic.** Card numbers are the well-known public TEST
   PANs (Luhn-valid, never issued). PII is invented. Never replace with real
   data.
4. **One source of truth for shared identities/secrets.** They live in
   `global_role_vars` in `ludus-range-config.yml`. Roles READ them; they never
   hardcode their own copy. Change a value there once and every consuming role
   picks it up on redeploy. This is what keeps the leaked creds matching the
   live accounts.
5. **Roles must stay idempotent and version-pinned.** Re-running a deploy must
   not drift. App-layer versions are pinned hard; OS package level floats to
   the template. See "Conventions" below.

## Architecture (quick reference)

Flat single `/24` behind the Ludus native router (packet's pfSense replaced by
Ludus's router by design). Exact packet last-octets preserved. Ludus addresses
hosts as `10.<range_second_octet>.<vlan>.<ip_last_octet>`; all hosts are on
VLAN 10, so the segment is `10.x.10.0/24`.

| Host | OS template | Octet | Service | Intended weakness (static) |
|------|-------------|-------|---------|----------------------------|
| Deathstar | win2019 (see Templates) | .105 | AD DC / DNS / auth | weak pw policy, crackable hashes, kerberoastable SPN, reused local-admin value |
| Tat10ine | win10-22h2 | .9 | Accounting / boss WS | reused local-admin account, sensitive files + owner note |
| Kamino | win2016 | .11 | Karaoke droid (canned AI stub) | weak service account (IIS app pool), SMBv1 enabled |
| Tython | debian-12 | .201 | Payment web | SQLi (pay.php); deployed from Gitea; served .git/ |
| Ashla | debian-12 | .202 | Shared MariaDB | over-privileged app user; CC+PII seed |
| Bogan | debian-12 | .203 | Mail (Postfix/Dovecot) | mailboxes mirror AD users, reused pw; plaintext auth |
| Sing3PO | rocky-9 | .134 | Karaoke web | stores svc_karaoke cred (ties to kerberoastable SPN) |
| Wookie | debian-12 | .20 | Site/menu + FTP | weak FTP w/ write to webroot -> readable config.php |
| Corellia | rocky-9 | .253 | Gitea | repo w/ committed DB creds, anonymous browse, weak admin |

### The four chains (must stay intact)

1. Two paths into the shared DB: Tython SQLi, and Wookie weak-FTP -> readable
   `config.php` creds.
2. Creds-leak bridge: Corellia Gitea committed `config.php`, and Tython's
   served `.git/`, both expose the live Ashla DB credential.
3. Mail <-> AD overlap: Bogan mailboxes mirror Deathstar AD users with reused
   passwords.
4. AD <-> workstation: Tat10ine reused local-admin (+ owner note disclosing
   it); Sing3PO stores the kerberoastable svc_karaoke credential.

## Repo layout

```
ludus-range-config.yml     Range: 9 VMs, flat /24, Ludus router, global_role_vars
ansible/
  requirements.yml         Version-pinned collections
  roles/<host>/            One role per host (tasks/defaults/vars/handlers/templates/files)
docs/
  topology.md              Per-host intent + chain map
  RUNBOOK.md               Deploy + validate procedure
scripts/
  preflight.sh             Pre-deploy host/env checks (read-only)
  validate-range.sh        Post-deploy chain/service validation (read-only)
.claude/
  settings.json.example    Recommended agent permissions (opt-in; see below)
README.md                  Human overview
```

## Agent permissions

A recommended permission set lives in `.claude/settings.json.example`. On the
Ludus server, review it and copy it into place to reduce prompting:

```bash
cp .claude/settings.json.example .claude/settings.json
```

It pre-approves read-only Ludus reads, the validation scripts, role
registration, and `ludus range config set`; it makes `ludus range deploy`
prompt; and it denies `ludus range rm` outright. Widen it only deliberately.

## Build / deploy workflow (Ludus)

Full detail and ordering is in `docs/RUNBOOK.md`. The essential flow:

```bash
# 0. Prereqs (once / after edits)
ansible-galaxy collection install -r ansible/requirements.yml   # in the ludus user context
for r in ansible/roles/*/ ; do ludus ansible roles add -d "$r" --force ; done

# 1. Set the range config and deploy
ludus range config set -f ludus-range-config.yml
ludus range deploy
ludus range logs -f          # follow; or: ludus range status

# 2. Validate
./scripts/validate-range.sh 10.<second_octet>.10      # pass the range /24 prefix
```

**IMPORTANT — Ludus caches role code.** Editing a role in this repo does NOT
update Ludus's stored copy. After any change under `ansible/roles/`, re-add it
(`ludus ansible roles add -d ./ansible/roles/<role> --force`) before
redeploying, or the change won't take effect.

### Deploy order / dependencies

`ludus range deploy` handles the whole range, and Ludus's native `primary-dc` /
`member` config makes domain join + DNS automatic. The dependencies that matter
when validating (and if deploying host-by-host):

1. **Deathstar** first — forest root; everything authenticating depends on it.
2. **Ashla** before Corellia/Tython/Wookie — it owns the DB creds + data.
3. **Corellia** before **Tython** — Tython clones its app (and the committed
   creds) from Corellia's Gitea at deploy time. If Tython deploys first its
   clone task retries, but Corellia should be healthy first.
4. Bogan, Tat10ine, Kamino, Sing3PO depend on Deathstar for AD identity.

## Templates

As of the last check, several referenced templates were still building. Confirm
with `ludus templates list` before deploy. Notes:

- **Deathstar** references `win2019-server-x64-template`. If your Ludus only
  offers `win2019-server-x64-no-security-updates-template`, use that — an
  unpatched DC is a better fit for this range anyway. Update the `template:` in
  `ludus-range-config.yml` if so.
- The `*-no-defender` and `*-no-security-updates` variants are good fits here:
  they stop a patched OS / Defender from fighting the intentional weaknesses.
- `win10-22h2`, `win2016`, and `rocky-9` were building and are expected to be
  available; no config change needed once built.

## Known gotchas (read before deploying)

- **br_netfilter / persistence (Proxmox host).** The Ludus router + NAT depend
  on the host having `br_netfilter` loaded and
  `net.bridge.bridge-nf-call-iptables = 1`. It can regress on host reboot.
  `scripts/preflight.sh` checks it; the fix (needs root on the Proxmox host):
  ```
  echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
  printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\n' \
    | sudo tee /etc/sysctl.d/99-ludus-bridge-nf.conf
  sudo modprobe br_netfilter && sudo sysctl --system
  ```
- **Flat network = no VLAN isolation.** Every host can reach every host (as in
  the real competition). Do not assume network-level containment.
- **passlib/crypt** must be present in the ludus user's Ansible environment:
  Bogan and Wookie use the `password_hash('sha512')` filter.
- **Gitea checksum** `corellia_gitea_sha256` is intentionally blank (downloads
  unverified). Fill it from `https://dl.gitea.com/gitea/<version>/` to pin.
- **Corellia secrets persist.** app.ini is written only on first install so the
  generated SECRET_KEY/INTERNAL_TOKEN are never clobbered. To regenerate, remove
  `/etc/gitea/app.ini` on the host and redeploy.

## Conventions for editing roles

- Read shared values from `global_role_vars`; never hardcode a second copy.
- Pin app-layer versions (release tags, package versions, checksums) in the
  role's `defaults/main.yml`. OS package level floats to the template.
- Keep every task idempotent (declarative modules, `creates:`/guards for shell,
  `update_password: on_create`, `INSERT IGNORE` for seed SQL).
- `no_log: true` on any task handling a credential.
- Validate YAML before committing. Prefer running the repo's own checks
  (`ansible-lint`, `yamllint`) if installed.
- After editing a role, re-add it to Ludus (see above) before redeploy.

## Git

- Work on the feature branch already in use; do not push to the default branch
  without explicit permission.
- Commit in small, described steps. Match the existing commit style in
  `git log`. Never commit real credentials (the lab creds here are synthetic
  and intentional; anything resembling real data does not belong in the repo).

## When unsure

Ask the owner before: destroying a range (`ludus range rm`), changing the
network model, adding any offensive/attack capability (do not), or widening a
host's exposure beyond what the chain needs. Finish everything else and report
what was done and what was validated.
