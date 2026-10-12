# CCDC practice range — WRCCDC Inv6 / STAR BARS topology (Ludus)

A 9-host defensive-training range for CCDC practice, built on
[Ludus](https://docs.ludus.cloud) (Proxmox). Modeled on the WRCCDC Inv6 /
STAR BARS team-packet topology: every host has a realistic dependency on at
least one other, so the intentional weaknesses **chain** rather than sitting
on isolated vuln boxes.

> Scope: a **static, intentionally-vulnerable target environment** for
> hands-on blue-team / manual red-team practice inside an isolated Proxmox lab.
> No automated attack tooling — vulnerable configs only. Do not expose it to
> any production or shared network.

## Network

Faithful to the packet: **one flat subnet** behind a single router. The packet
uses `192.168.1.0/24` behind pfSense ("Routooine", .2); here we use the
**Ludus native router** (no pfSense, no manual iptables) and Ludus's own
addressing. All hosts share one VLAN, so the segment is flat exactly as in the
competition. We preserve each host's **exact last octet** from the packet.

Ludus addresses hosts as `10.<range_second_octet>.<vlan>.<ip_last_octet>`; with
every host on VLAN 10 the range lands on `10.x.10.0/24`.

Any micro-segmentation you practice is **host-based** (firewalld / ufw /
Windows Firewall inside the roles) — matching how a blue team hardens a flat
CCDC network, rather than re-architecting it into VLANs.

## Hosts

| # | Host      | OS / template            | Last octet | Role (per packet)                         | Template source |
|---|-----------|--------------------------|------------|-------------------------------------------|-----------------|
| 1 | Deathstar | Windows Server 2019      | .105       | AD / DNS / Auth services                  | native          |
| 2 | Tat10ine  | Windows 10               | .9         | Accounting + the BOSS's computer          | native          |
| 8 | Kamino    | Windows Server 2016      | .11        | Karaoke droid + local AI customer support | native          |
| 3 | Tython    | Debian 12                | .201       | Payment system app (SQLi)                 | native          |
| 4 | Ashla     | Debian 12                | .202       | Data exchange + DB server (CC/PII)        | native          |
| 5 | Bogan     | Debian 12                | .203       | Mail server (accounts tied to AD)         | native          |
| 9 | Sing3PO   | Fedora 40                | .134       | THE karaoke machine                       | **custom Packer** |
| 7 | Wookie    | Alpine 3.19              | .20        | Corporate site + menu + FTP (reads Ashla) | **custom Packer** |
| 6 | Corellia  | Rocky Linux 9            | .253       | Gitea (leaked DB creds in source)         | native          |

Plus the **Ludus native router** (replacing the packet's pfSense "Routooine").

## Dependency & attack-chain map (what must be preserved)

```
                 +-------------------- Deathstar (DC/DNS/auth, .105) ---------------------+
                 | (native domain join + DNS for every member/authenticating host)        |
                 |                          |                        |                     |
            Tat10ine(.9)                 Kamino(.11)              Bogan(.203) mail
       accounting/boss box          legacy droid+AI host    mailbox users == AD users
       local-admin/cred reuse       weak service account        (reused creds)

   Tython(.201) payment web  --SQLi-->  Ashla(.202) DB  <--reads--  Wookie(.20) site/menu/FTP
        |                                   ^
        | source hosted on                  | same creds leaked in
        v                                   |
   Corellia(.253) Gitea  --committed secrets (Ashla DB creds)--> bridges web foothold to DB
```

Chains to keep intact:
1. **Two paths into one DB:** Tython (SQLi) and Wookie both read Ashla — same
   backend, two independent front-end footholds.
2. **Creds-leak bridge:** low-priv web access on Tython → its source in Corellia
   Gitea → committed Ashla DB creds → direct DB access.
3. **Mail ⇄ AD overlap:** Bogan mailbox accounts map 1:1 to Deathstar AD users
   with reused/weak passwords.
4. **AD ⇄ workstation:** Tat10ine local-admin / cached-cred reuse against
   Deathstar.

### Target data model (from the packet's Red Team deduction table)

The scored recovery targets tell us what data to seed:

- **Ashla / Tython:** customer **credit-card numbers** (-50) and **PII**
  name/address/phone (-200), plus the DB itself (-25, +25 if decryptable).
- **Deathstar:** crackable **AD hashes / SAM** (-50) — seed realistic weak
  passwords so cracking is feasible.
- **Tat10ine, Corellia, others:** sensitive **config files / corporate data**
  (-25) — accounting files, committed secrets.

## Build order (dependencies matter)

AD forest must exist before anything joins or authenticates against it.

0. **Prereqs (once):**
   - Install pinned collections: `ansible-galaxy collection install -r ansible/requirements.yml`
   - Add custom role code to Ludus: `for r in ansible/roles/*; do ludus ansible roles add -d "$r"; done`
   - Build custom templates:
     `ludus templates add -d ./packer/wookie-alpine && ludus templates add -d ./packer/sing3po-fedora && ludus templates build`
     (wait for both to reach a built state before deploying)
1. **Deathstar** — forest root DC + DNS. Everything else depends on it.
2. **Tat10ine, Kamino, Bogan** — domain members / AD-tied accounts (need #1).
3. **Ashla** — shared DB (no standup deps; needed by #5, #7, and Corellia creds).
4. **Corellia** — Gitea; its leaked creds must match Ashla (needs #3 decided).
5. **Tython, Wookie** — front ends that read Ashla (need #3).
6. **Sing3PO** — karaoke app server.

`ludus range deploy` builds the whole range; `role: primary-dc` / `role: member`
make Ludus handle domain join + DNS natively, so ordering is mostly enforced for
you. Still validate members actually joined before testing the mail/AD and
workstation chains.

## Known Ludus/Proxmox gotchas (flagged from prior experience)

You mentioned prior `br_netfilter` / persistence issues. Even on a flat network
these still apply to Ludus:

- **The Ludus native router + NAT and any host-level filtering depend on the
  Proxmox host bridging correctly.** `br_netfilter` must be loaded and
  `net.bridge.bridge-nf-call-iptables = 1` for bridged traffic to traverse
  the host's netfilter as expected. Verify after every host reboot:
  ```
  lsmod | grep br_netfilter
  sysctl net.bridge.bridge-nf-call-iptables    # expect 1
  ```
- **Persistence across host reboot** — make it stick, don't rely on runtime:
  ```
  echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
  printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\n' \
    | sudo tee /etc/sysctl.d/99-ludus-bridge-nf.conf
  sudo modprobe br_netfilter && sudo sysctl --system
  ```
- **Flat network = no VLAN isolation to rely on.** Because every host can reach
  every other host (as in the real competition), do not assume any network-level
  containment between boxes. If you want to practice segmentation, add it
  host-based inside the roles and verify it, rather than trusting the range to
  isolate anything for you.
- **Custom templates:** Wookie/Alpine and Sing3PO/Fedora are the two most likely
  to surface issues (no official image = no Ludus-tested guest-agent path).
  Confirm the QEMU guest agent and Python3 are in the built template, or
  Ansible/Ludus post-deploy steps will hang.

## Layout

```
ludus-range-config.yml         Range: 9 VMs on a flat /24, Ludus native router
packer/
  wookie-alpine/               Custom Alpine 3.19 template (Wookie)
  sing3po-fedora/              Custom Fedora 40 template (Sing3PO)
ansible/
  requirements.yml             Version-pinned collections
  ansible.cfg
  roles/                       One role per host (skeletons; filled one at a time)
docs/
  topology.md                  Detailed topology + chain notes
```

## Status

Scaffold. VM definitions and addressing (exact packet octets, flat /24) are
complete; each Ansible role is a documented skeleton to be filled one at a
time. The two Packer ISO checksums are placeholders — replace with published
checksums before the first build.
