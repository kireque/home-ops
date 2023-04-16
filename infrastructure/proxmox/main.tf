data "sops_file" "proxmox_secrets" {
  source_file = "secret.sops.yaml"
}

provider "proxmox" {
  pm_api_url = data.sops_file.proxmox_secrets.data["pm_api_url"]
  # pm_api_token_id     = data.sops_file.proxmox_secrets.data["token_id"]
  # pm_api_token_secret = data.sops_file.proxmox_secrets.data["token_secret"]
  pm_user         = data.sops_file.proxmox_secrets.data["pm_user"]
  pm_password     = data.sops_file.proxmox_secrets.data["pm_password"]
  pm_tls_insecure = true
}

resource "proxmox_vm_qemu" "talos_master" {
  count = length(var.master_hostname)
  name  = var.master_hostname[count.index]

  target_node = var.proxmox_host[count.index]
  vmid        = var.master_vmid + count.index
  iso         = "local:iso/talos-amd64.iso"

  agent    = 0
  os_type  = "linux"
  cores    = 2
  sockets  = 1
  cpu      = "host"
  balloon  = 0
  memory   = 4096
  scsihw   = "virtio-scsi-pci"
  boot     = "cdn"
  bootdisk = "scsi0"
  oncreate = true
  tablet   = false

  disk {
    slot    = 0
    size    = "20G"
    type    = "scsi"
    storage = var.master_storage[count.index]
    discard = "on"
  }

  network {
    model   = "virtio"
    bridge  = "vmbr0"
    macaddr = var.master_mac[count.index]
  }
}

resource "proxmox_vm_qemu" "talos_worker" {
  count = length(var.worker_hostname)
  name  = var.worker_hostname[count.index]

  target_node = var.proxmox_host[count.index]
  vmid        = var.worker_vmid + count.index
  iso         = "local:iso/talos-amd64.iso"

  agent    = 0
  os_type  = "linux"
  cores    = 2
  sockets  = 1
  cpu      = "host"
  balloon  = 0
  memory   = 12288
  scsihw   = "virtio-scsi-pci"
  boot     = "cdn"
  bootdisk = "scsi0"
  oncreate = true
  tablet   = false

  disk {
    slot    = 0
    size    = "20G"
    type    = "scsi"
    storage = var.worker_storage[count.index]
    discard = "on"
  }

  disk {
    slot    = 1
    size    = "100G"
    type    = "scsi"
    storage = var.worker_storage[count.index]
    discard = "on"
  }

  network {
    model   = "virtio"
    bridge  = "vmbr0"
    macaddr = var.worker_mac[count.index]
  }
}
