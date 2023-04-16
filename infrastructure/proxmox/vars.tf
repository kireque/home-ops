variable "proxmox_host" {
  description = "Name of the proxmost host inside the proxmox datacenter"
  type        = list(string)
  default     = ["pve1","pve2","pve3"]
}

# master variables
variable "master_hostname" {
  description = "Talos Master VM's to be created"
  type        = list(string)
  default     = ["talos-mstr-01","talos-mstr-02","talos-mstr-03"]
}

variable "master_vmid" {
  description = "Starting ID for Master VM's"
  type        = number
  default     = 301
}

variable "master_storage" {
  description = "Talos Master VM's to be created"
  type        = list(string)
  default     = ["nvme", "nvme","local"]
}

variable "master_mac" {
  description = "MAC's for Master VM's"
  type        = list(string)
  default     = ["52:05:42:00:02:01","52:05:42:00:02:02","52:05:42:00:02:03"]
}

# Worker variables
variable "worker_hostname" {
  description = "Talos Worker VM's to be created"
  type        = list(string)
  default     = ["talos-wrkr-01", "talos-wrkr-02"]
}

variable "worker_vmid" {
  description = "Starting ID for Worker VM's"
  type        = number
  default     = 311
}

variable "worker_storage" {
  description = "Talos Worker VM's to be created"
  type        = list(string)
  default     = ["nvme", "nvme"]
}

variable "worker_mac" {
  description = "MAC's for Worker VM's"
  type        = list(string)
  default     = ["52:05:42:00:02:11", "52:05:42:00:02:12"]
}