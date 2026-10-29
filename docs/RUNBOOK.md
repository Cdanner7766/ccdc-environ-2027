# Deploy & validate runbook

Procedure for standing up the STAR BARS range on Ludus and confirming the
intended-weak state is present. Read `CLAUDE.md` first for the rules.

All `ludus` commands run as the Ludus user that owns the range (the one whose
`ludus` CLI is configured with an API key). br_netfilter/sysctl fixes need root
on the Proxmox host.

## 1. Preflight (before deploy)

```bash
./scripts/preflight.sh
```

Confirms: `ludus` CLI present, br_netfilter loaded + sysctl set, required
collections installed, and which templates are built. Resolve anything it flags
(especially br_netfilter — see CLAUDE.md for the persistent fix).

## 2. Load collections and roles

```bash
# Pinned collections, in the ludus user's ansible environment
ansible-galaxy collection install -r ansible/requirements.yml

# Register every role with Ludus (--force so edits are picked up)
for r in ansible/roles/*/ ; do ludus ansible roles add -d "$r" --force ; done
```

## 3. Confirm templates

```bash
ludus templates list
```

Every `template:` named in `ludus-range-config.yml` must be BUILT. If only
`win2019-server-x64-no-security-updates-template` exists (not the plain 2019),
set Deathstar's `template:` to it. See CLAUDE.md "Templates".

## 4. Set config and deploy

```bash
ludus range config set -f ludus-range-config.yml
ludus range deploy
ludus range logs -f           # follow progress; Ctrl-C to stop following
ludus range status            # VM/role state
```

Ludus promotes the DC and joins members automatically. Deploy is idempotent;
re-run after fixing a failed role (re-add the role first if you edited it).

Deploy order that matters: Deathstar (AD) -> Ashla (DB) -> Corellia (Gitea) ->
Tython/Wookie -> the rest. Ludus sequences most of this; Tython's Gitea clone
retries if Corellia is not up yet.

## 5. Validate the chains

From a client on the range VPN (so the `10.x.10.0/24` is reachable):

```bash
./scripts/validate-range.sh 10.<second_octet>.10
```

It checks, read-only, that each service is up and the intended-weak state is
present (DB reachable, payment app serving, Tython `.git/` fetchable, Gitea repo
browsable with committed creds, mail ports open, menu/droid/karaoke pages up).
It does NOT exploit anything — manual red-teaming is separate and done by the
owner.

Manual spot checks worth doing once:

- Browse `http://corellia.bars.local:3000/wuher/payments` and confirm
  `config.php` shows the DB creds (the leak).
- Confirm the DB creds from the repo connect to Ashla and the `cards` table has
  the test PANs.
- Log into a Bogan mailbox with an AD user's password (same credential).

## 6. Reset / teardown

```bash
ludus range deploy            # re-converge (idempotent) after fixes
# Destructive — ask the owner first:
# ludus range rm
```

## Troubleshooting

- **A role change didn't take effect** — you didn't re-add it to Ludus. Run
  `ludus ansible roles add -d ./ansible/roles/<role> --force` then redeploy.
- **Inter-host traffic behaves oddly / router flaky** — check br_netfilter on
  the Proxmox host (preflight), reapply the persistent fix, verify after host
  reboots.
- **Tython has no app / clone failed** — Corellia/Gitea wasn't up or the repo
  wasn't seeded. Confirm Gitea health, then redeploy Tython.
- **Mail users can't log in** — confirm the Bogan system users exist and
  passlib is installed in the ludus ansible env.
- **Gitea push/seed failed** — check the service is up on :3000 and
  `/etc/gitea/app.ini` has generated tokens; remove app.ini and redeploy to
  regenerate.
