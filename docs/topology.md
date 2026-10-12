# Topology & attack-chain detail

Records the *why* behind each host so cross-host dependencies stay intact as
roles are filled in one at a time. Nothing here is an attack script — it
documents the static conditions each role must create. Source of truth for
host facts is the WRCCDC Inv6 / STAR BARS team packet.

## Network / addressing

- **Flat single subnet** (packet: `192.168.1.0/24` behind pfSense "Routooine"
  .2). Here: Ludus native router, all hosts on VLAN 10 → `10.<range>.10.0/24`.
- Exact packet last octets preserved.

| Host      | OS                  | Last octet | Packet role |
|-----------|---------------------|-----------|-------------|
| Routooine | pfSense (→ Ludus router) | .2   | Router / firewall |
| Deathstar | Windows Server 2019 | .105      | AD / DNS / Auth |
| Kamino    | Windows Server 2016 | .11       | Karaoke droid + local AI customer support |
| Tat10ine  | Windows 10          | .9        | Accounting + the BOSS's computer |
| Tython    | Debian              | .201      | Payment system app |
| Ashla     | Debian              | .202      | Data exchange + DB server |
| Bogan     | Debian              | .203      | Mail server |
| Sing3PO   | Rocky 9 (pkt Fedora)| .134      | THE karaoke machine |
| Wookie    | Debian 12 (pkt Alpine)| .20     | Corporate site + menu + FTP |
| Corellia  | Rocky               | .253      | Gitea |

## Per-host intent (what each role wires)

### Deathstar (AD/DNS, .105)
- Forest root DC (`bars.local`), native Ludus `primary-dc`.
- Creates the AD user set that **Bogan** mailboxes mirror.
- Static weaknesses: kerberoastable SPN account (weak pw), local-admin pw
  reused on Tat10ine, realistic weak passwords so AD hash / SAM recovery
  (scored -50 in the packet) is feasible.

### Tat10ine (workstation, .9)
- Accounting + the boss's box. Native domain join.
- Local-admin credential reuse + cached domain creds → DC⇄workstation pivot.
- Sensitive accounting/corporate files on disk (config/corporate data -25,
  PII -200).

### Kamino (legacy Win2016, .11)
- Karaoke droid host with a local AI customer-support app. Domain member.
- Legacy/unpatched service config + weak service account.

### Tython (payment web, .201) — SQLi path #1
- Payment app with string-concatenated SQL against **Ashla**.
- Source lives in Corellia Gitea with committed Ashla creds.

### Ashla (DB, .202) — shared crown jewel
- MariaDB/MySQL (3306) serving Tython + Wookie.
- Seeds customer **credit-card numbers + PII** (scored -50 / -200).
- App DB account over-privileged so SQLi is impactful.
- Creds equal the ones committed in Corellia.

### Bogan (mail, .203) — mail⇄AD overlap
- Mailbox accounts == Deathstar AD usernames, reused/weak passwords.

### Sing3PO (karaoke machine, .134) — Rocky 9 (packet: Fedora)
- Karaoke app server. May consume Ashla data-exchange (decide at buildout;
  keep scope tight — one chained weakness, not many).

### Wookie (site/menu/FTP, .20) — read path #2 — Debian 12 (packet: Alpine)
- Corporate site + menu reading **Ashla** (second DB foothold) + FTP service.

### Corellia (Gitea, .253) — creds-leak bridge
- Hosts Tython's repo; committed secrets (real Ashla creds) in history and/or
  an exposed `.git/`. Bridges low-priv web foothold → DB creds.

## Logical reachability (flat network)

The network is flat, so **every host can reach every other host** — there are
no router-enforced inter-host rules (matching the real competition). The chains
below are therefore *service-level / logical* dependencies, not firewall rules.
If you choose to practice containment, enforce it host-based and verify it.

| Logical dependency        | Why it exists |
|---------------------------|---------------|
| all hosts → Deathstar     | auth / DNS |
| Tython → Ashla (3306)     | SQLi path #1 |
| Wookie → Ashla (3306)     | read path #2 |
| Tython → Corellia (22/3000) | creds-leak bridge |
| Bogan → Deathstar (LDAP)  | mail⇄AD account mapping |

> When Ashla's engine/port is finalized (MariaDB:3306 assumed), update this
> table and the README together.
