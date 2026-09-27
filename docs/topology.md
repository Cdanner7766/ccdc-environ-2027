# Topology & attack-chain detail

This file records the *why* behind each host so that, as roles are filled in
one at a time, the cross-host dependencies stay intact. Nothing here is an
attack script — it documents the static conditions each role must create.

## Naming / addressing

- Domain: `bars.local` (forest root on Deathstar)
- Ludus assigns `10.<range_octet>.<vlan>.<ip_last_octet>`

| Host      | VLAN | last octet | Notes |
|-----------|------|-----------|-------|
| Deathstar | 10   | 10        | DC, DNS, forest root |
| Tat10ine  | 10   | 20        | Domain member (Win10) |
| Kamino    | 10   | 30        | Domain member (Win2016 legacy) |
| Tython    | 20   | 10        | Payment web front end |
| Wookie    | 20   | 20        | Web/menu + FTP front end |
| Bogan     | 20   | 30        | Mail |
| Ashla     | 30   | 10        | Shared DB |
| Corellia  | 30   | 20        | Gitea |
| Sing3PO   | 30   | 30        | App server |

## Per-host intent (what each role wires)

### Deathstar (AD/DNS)
- Forest root DC. Native Ludus `primary-dc`.
- Creates the AD user set that **Bogan** mailboxes mirror.
- Realistic AD weaknesses to seed (static): a service account with an SPN and a
  weak password (kerberoast target), and a local-admin password reused on
  Tat10ine. No attack tooling — just the accounts/config that make those paths
  exist.

### Tat10ine (workstation)
- Native domain join to Deathstar.
- Local-admin credential reuse + cached domain creds → DC⇄workstation pivot.

### Kamino (legacy Win2016)
- Domain member. Legacy service with an outdated/weak config appropriate to a
  box left behind (decide specifics at buildout).

### Tython (payment web) — SQLi path #1
- Web app with string-concatenated SQL against **Ashla**.
- Its **source lives in Corellia Gitea** with committed Ashla creds.

### Wookie (web/menu/FTP) — read path #2
- Separate front end that also reads **Ashla** → same DB, second foothold.
- FTP service (static vulnerable config).

### Bogan (mail) — mail⇄AD overlap
- Mailbox accounts == Deathstar AD usernames, reused/weak passwords.

### Ashla (DB) — the shared crown jewel
- Serves Tython + Wookie. App DB account over-privileged so SQLi is impactful.
- Creds must equal the ones committed in Corellia.

### Corellia (Gitea) — creds-leak bridge
- Hosts Tython's repo; committed secrets (real Ashla creds) in history and/or
  an exposed `.git/`. Bridges low-priv web foothold → DB creds.

### Sing3PO (app server)
- App tier; specific service + dependency decided at buildout.

## Firewall rules ↔ chains (must stay in sync with ludus-range-config.yml)

| Rule | Enables chain |
|------|---------------|
| DMZ→DC, Data→DC (to .10) | auth/DNS for all tiers |
| Tython→Ashla:3306 | SQLi path #1 |
| Wookie→Ashla:3306 | read path #2 |
| Tython→Corellia:22,3000 | creds-leak bridge |

> When Ashla's DB engine/port is finalized, update the `3306` rules and the
> README/topology tables together.
