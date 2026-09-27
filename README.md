# CCDC practice range — WRCCDC Inv6 / STAR BARS topology (Ludus)

A 9-host defensive-training range for CCDC practice, built on
[Ludus](https://docs.ludus.cloud) (Proxmox). Modeled on the WRCCDC Inv6 /
STAR BARS team-packet topology: every host has a realistic dependency on at
least one other, so the intentional weaknesses **chain** rather than sitting
on isolated vuln boxes.

> Scope: this range is a **static, intentionally-vulnerable target
> environment** for hands-on blue-team / manual red-team practice inside an
> isolated Proxmox lab. It contains no automated attack tooling — vulnerable
> configs only. Do not expose it to any production or shared network.

## Hosts

| # | Host      | OS / template                         | Role                                  | VLAN | Template source |
|---|-----------|---------------------------------------|---------------------------------------|------|-----------------|
| 1 | Deathstar | Windows Server 2019                   | AD DC + DNS + auth                    | 10   | native          |
| 2 | Tat10ine  | Windows 10                            | Domain-joined workstation             | 10   | native          |
| 8 | Kamino    | Windows Server 2016                   | Legacy app/service host               | 10   | native          |
| 3 | Tython    | Debian 12                             | Payment web app (SQLi)                | 20   | native          |
| 7 | Wookie    | Alpine 3.19                           | Web/menu + FTP (reads Ashla)          | 20   | **custom Packer** |
| 5 | Bogan     | Debian 12                             | Mail server (accounts tied to AD)     | 20   | native          |
| 4 | Ashla     | Debian 12                             | DB backend (serves Tython + Wookie)   | 30   | native          |
| 6 | Corellia  | Rocky Linux 9                         | Gitea (leaked DB creds in source)     | 30   | native          |
| 9 | Sing3PO   | Fedora 40                             | App server                            | 30   | **custom Packer** |

Plus the **Ludus native router** providing inter-VLAN routing and the built-in
firewall (no manual iptables).

## Network segmentation

Three VLANs, default-deny between them (`inter-vlan-default: REJECT`). Only the
dependency paths the topology needs are opened, in `ludus-range-config.yml`
under `network.rules` (Ludus's built-in firewall on the router):

- **VLAN 10 — Internal / AD:** Deathstar, Tat10ine, Kamino
- **VLAN 20 — DMZ / public services:** Tython, Wookie, Bogan
- **VLAN 30 — Backend / data:** Ashla, Corellia, Sing3PO

## Dependency & attack-chain map (what must be preserved)

```
                 +-------------------- Deathstar (DC/DNS/auth, VLAN10) --------------------+
                 | (native domain join + DNS for every member/authenticating host)        |
                 |                          |                        |                     |
            Tat10ine(10)                 Kamino(10)               Bogan(20) mail
        local-admin/cred reuse      legacy domain member     mailbox users == AD users
                                                                    (reused creds)

   Tython(20) payment web  --SQLi-->  Ashla(30) DB  <--reads--  Wookie(20) web/menu/FTP
        |                                  ^
        | source hosted on                 | same creds leaked in
        v                                  |
   Corellia(30) Gitea  --committed secrets (Ashla DB creds)--> bridges web foothold to DB
```

Chains to keep intact:
1. **Two paths into one DB:** Tython (SQLi) and Wookie both read Ashla — same
   backend, two independent front-end footholds.
2. **Creds-leak bridge:** low-priv web access on Tython → its source in Corellia
   Gitea → committed Ashla DB creds → direct DB access.
3. **Mail ⇄ AD overlap:** Bogan mailbox accounts map 1:1 to Deathstar AD users
   with reused/weak passwords, so either compromise crosses over.
4. **AD ⇄ workstation:** Tat10ine local-admin / cached-cred reuse against
   Deathstar.

## Build order (dependencies matter)

The AD forest must exist before anything joins or authenticates against it.

0. **Prereqs (once):**
   - Install pinned Ansible collections: `ansible-galaxy collection install -r ansible/requirements.yml`
   - Add the custom role code to Ludus: `for r in ansible/roles/*; do ludus ansible roles add -d "$r"; done`
   - Build custom templates:
     `ludus templates add -d ./packer/wookie-alpine && ludus templates add -d ./packer/sing3po-fedora && ludus templates build`
     (wait for both to reach a built state before deploying)
1. **Deathstar** — forest root DC + DNS. Everything else depends on it.
2. **Tat10ine, Kamino, Bogan** — domain members / AD-tied accounts (need #1).
3. **Ashla** — DB backend (standup has no deps; needed by #5, #7, #6-creds).
4. **Corellia** — Gitea; its leaked creds must match Ashla (needs #3 decided).
5. **Tython, Wookie** — front ends that read Ashla (need #3).
6. **Sing3PO** — app server.

Ludus deploys the whole range from `ludus range deploy`; the ordering above is
what to respect when filling in roles and when validating chains. Deathstar's
`role: primary-dc` and the members' `role: member` make Ludus handle domain
join + DNS natively, so the ordering is mostly enforced for you — but validate
that members actually joined before testing the mail/AD and workstation chains.

## Known Ludus/Proxmox isolation gotchas (flagged from prior experience)

You mentioned prior `br_netfilter` / persistence issues. This design's
segmentation depends on exactly that, so:

- **Inter-VLAN `REJECT` is only enforced if the Proxmox host filters bridged
  traffic.** That requires the `br_netfilter` module loaded **and**
  `net.bridge.bridge-nf-call-iptables = 1`. If either is missing, VMs talk
  across VLANs even though the range config says REJECT — the range looks
  segmented but isn't. Verify after every host reboot:
  ```
  lsmod | grep br_netfilter
  sysctl net.bridge.bridge-nf-call-iptables    # must be 1
  ```
- **Persistence across host reboot:** make it stick, don't rely on runtime state:
  ```
  echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
  printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\n' \
    | sudo tee /etc/sysctl.d/99-ludus-bridge-nf.conf
  sudo modprobe br_netfilter && sudo sysctl --system
  ```
- **Validate segmentation, don't assume it.** After deploy, from a VLAN-20 host
  confirm you *can* reach Ashla on the DB port and *cannot* reach a VLAN-30 host
  on a port with no rule. Treat a passing "cannot reach" test as the real proof
  the firewall is live.
- **Custom templates:** Wookie/Alpine and Sing3PO/Fedora are the two most likely
  to surface issues (no official image = no Ludus-tested guest agent path).
  Confirm the QEMU guest agent and Python3 are present in the built template, or
  Ansible/Ludus post-deploy steps will hang.

## Layout

```
ludus-range-config.yml         Range definition: 9 VMs, VLANs, firewall rules
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

Scaffold only. VM definitions, VLANs, and firewall rules are complete; each
Ansible role is a documented skeleton to be filled in one at a time. The two
Packer ISO checksums are placeholders — replace with published checksums
before the first build.
