variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "Central US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-winvm-demo"
}

variable "admin_username" {
  description = "Local administrator username for the VMs"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Local administrator password for the VMs. Must meet Azure complexity requirements (12-123 chars, 3 of: upper/lower/digit/special). A default is provided here per request — for anything beyond a personal test environment, override it via terraform.tfvars, -var, or TF_VAR_admin_password instead of leaving a real password checked into source control."
  type        = string
  sensitive   = true
  default     = "P@ssw0rd1234!"
}

variable "script_raw_url" {
  description = "Raw GitHub URL to setup.ps1. Must be publicly reachable so the VM extension can download it without credentials — use a public repo or public gist."
  type        = string
  default     = "https://raw.githubusercontent.com/Shivanshusaxena2/newscript/blob/main/setup.ps1"
}

variable "vm_size" {
  description = "VM SKU size"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 256
}

variable "data_disk_size_gb" {
  description = "Data (file share) disk size in GB, mounted as F: on every VM"
  type        = number
  default     = 10
}

variable "allowed_rdp_source_address_prefix" {
  description = "Source address prefix (CIDR or an IP, e.g. '203.0.113.5/32') allowed to RDP over 3389. Defaults to '*' (open to internet) — restrict this for real deployments."
  type        = string
  default     = "*"
}

variable "vm_config" {
  description = "Map of VMs to create. Key = VM name. install_iis = true installs IIS on that VM only (VM1 in the requirements)."
  type = map(object({
    install_iis = bool
  }))
  default = {
    vm1 = { install_iis = true }
    vm2 = { install_iis = false }
  }
}
