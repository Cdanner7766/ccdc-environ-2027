###############################################################################
# Packer template: Wookie — Alpine Linux 3.19 (CUSTOM; no official Ludus image)
#
# Add + build via Ludus:
#   ludus templates add -d ./packer/wookie-alpine
#   ludus templates build
#
# Produces template name: alpine-319-x64-server-template
# (referenced by Wookie's `template:` in ludus-range-config.yml)
#
# This template is a CLEAN, patched Alpine base image only. It installs no
# vulnerable service — all intentional-misconfig wiring happens later in the
# ccdc-wookie-web-ftp Ansible role, so the base image stays reusable and the
# vuln state lives in version-controlled, re-runnable Ansible.
###############################################################################

packer {
  required_plugins {
    proxmox = {
      # Pinned so re-running the build does not drift.
      version = "= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# --- Variables (Proxmox connection is injected by Ludus at build time) ------
variable "proxmox_url"                { type = string }
variable "proxmox_username"           { type = string }
variable "proxmox_password"           { type = string  sensitive = true }
variable "proxmox_host"               { type = string }
variable "proxmox_node"               { type = string }
variable "proxmox_pool"               { type = string  default = "" }
variable "proxmox_storage_pool"       { type = string  default = "local-lvm" }
variable "proxmox_storage_format"     { type = string  default = "raw" }
variable "proxmox_skip_tls_verify"    { type = bool     default = true }
variable "iso_storage_pool"           { type = string  default = "local" }
variable "cores"                      { type = string  default = "1" }
variable "memory"                     { type = string  default = "1024" }

# Pinned ISO. TODO: confirm checksum against alpinelinux.org before first build.
variable "iso_url" {
  type    = string
  default = "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.1-x86_64.iso"
}
variable "iso_checksum" {
  type    = string
  default = "sha256:ab89d6d18e6e8d1c9a3c48f4c2b0e2b0e0d1c8f6c5a4b3e2d1c0f9e8d7c6b5a4b" # TODO: replace with real published checksum
}

source "proxmox-iso" "wookie-alpine" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  pool                     = var.proxmox_pool
  insecure_skip_tls_verify = var.proxmox_skip_tls_verify

  vm_name  = "alpine-319-x64-server-template"
  template_description = "CCDC range base — Alpine 3.19 (Wookie). Clean base; vulns applied by Ansible."

  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  iso_storage_pool = var.iso_storage_pool
  unmount_iso      = true

  cores  = var.cores
  memory = var.memory
  os     = "l26"
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "8G"
    storage_pool = var.proxmox_storage_pool
    format       = var.proxmox_storage_format
    type         = "scsi"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr1000"    # Ludus build bridge; overridden by Ludus at build
  }

  # --- Automated install: Alpine answerfile served over HTTP -------------
  http_directory = "http"
  boot_wait      = "20s"
  boot_command = [
    "root<enter><wait>",
    "setup-alpine -f http://{{ .HTTPIP }}:{{ .HTTPPort }}/answers<enter><wait5>",
    "<wait10>",
    "y<enter><wait60>",           # confirm disk erase
    "reboot<enter>"
  ]

  # SSH creds used post-install for provisioning handoff (set in answers file).
  ssh_username = "root"
  ssh_password = "packer"        # TODO: move to a build var / vault before real use
  ssh_timeout  = "20m"
}

build {
  sources = ["source.proxmox-iso.wookie-alpine"]

  # Minimal base prep. Python3 is required for Ansible to manage this host.
  provisioner "shell" {
    inline = [
      "apk update",
      "apk add --no-cache python3 openssh sudo",
      "rc-update add sshd default",
    ]
  }
}
