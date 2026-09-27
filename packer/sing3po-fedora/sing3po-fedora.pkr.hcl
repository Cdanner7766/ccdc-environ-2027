###############################################################################
# Packer template: Sing3PO — Fedora 40 Server (CUSTOM; no official Ludus image)
#
# Add + build via Ludus:
#   ludus templates add -d ./packer/sing3po-fedora
#   ludus templates build
#
# Produces template name: fedora-40-x64-server-template
# (referenced by Sing3PO's `template:` in ludus-range-config.yml)
#
# CLEAN, patched Fedora base only. App/service tier and any intentional
# misconfig are applied later by the ccdc-sing3po-app Ansible role.
###############################################################################

packer {
  required_plugins {
    proxmox = {
      version = "= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url"              { type = string }
variable "proxmox_username"         { type = string }
variable "proxmox_password"         { type = string  sensitive = true }
variable "proxmox_node"             { type = string }
variable "proxmox_pool"             { type = string  default = "" }
variable "proxmox_storage_pool"     { type = string  default = "local-lvm" }
variable "proxmox_storage_format"   { type = string  default = "raw" }
variable "proxmox_skip_tls_verify"  { type = bool     default = true }
variable "iso_storage_pool"         { type = string  default = "local" }
variable "cores"                    { type = string  default = "2" }
variable "memory"                   { type = string  default = "2048" }

variable "iso_url" {
  type    = string
  default = "https://download.fedoraproject.org/pub/fedora/linux/releases/40/Server/x86_64/iso/Fedora-Server-dvd-x86_64-40-1.14.iso"
}
variable "iso_checksum" {
  type    = string
  default = "sha256:0000000000000000000000000000000000000000000000000000000000000000" # TODO: real Fedora 40 Server checksum
}

source "proxmox-iso" "sing3po-fedora" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  pool                     = var.proxmox_pool
  insecure_skip_tls_verify = var.proxmox_skip_tls_verify

  vm_name              = "fedora-40-x64-server-template"
  template_description  = "CCDC range base — Fedora 40 Server (Sing3PO). Clean base; app tier by Ansible."

  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  iso_storage_pool = var.iso_storage_pool
  unmount_iso      = true

  cores  = var.cores
  memory = var.memory
  os     = "l26"
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "15G"
    storage_pool = var.proxmox_storage_pool
    format       = var.proxmox_storage_format
    type         = "scsi"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr1000"
  }

  # --- Automated install: Anaconda kickstart served over HTTP ------------
  http_directory = "http"
  boot_wait      = "10s"
  boot_command = [
    "<up><wait>",
    "e<wait>",
    "<down><down><end>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kickstart.ks",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]

  ssh_username = "root"
  ssh_password = "packer"        # TODO: move to build var / vault; must match kickstart
  ssh_timeout  = "30m"
}

build {
  sources = ["source.proxmox-iso.sing3po-fedora"]

  provisioner "shell" {
    inline = [
      "dnf -y install python3 openssh-server sudo",
      "systemctl enable sshd",
      "dnf -y update",
    ]
  }
}
