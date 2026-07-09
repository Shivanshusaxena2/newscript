# Windows VM Infra (Terraform) — End-to-End

Provisions 2 Windows Server 2022 VMs on Azure entirely via `for_each`, matching:

| Requirement | Implementation |
|---|---|
| 2 Windows VMs via `for_each` | `var.vm_config` map (`vm1`, `vm2`) drives every VM-related resource |
| Size `Standard_D2s_v3`, Windows Server 2022-datacenter | `azurerm_windows_virtual_machine` |
| Location: Central US (configurable) | `var.location` (default `"Central US"`) |
| NSG with RDP (3389) | `azurerm_network_security_group` + rule `Allow-RDP-3389` |
| OS disk = 256 GB | `os_disk { disk_size_gb = var.os_disk_size_gb }` (default 256) |
| 10 GB data (file share) disk mounted as F: | `azurerm_managed_disk` + `azurerm_virtual_machine_data_disk_attachment`, formatted as `F:` by the extension script |
| DVD drive re-lettered to Z: on all VMs | Extension script re-letters the CD-ROM volume to `Z:` |
| C: extended from 128 GB to the full 256 GB OS disk | Extension script runs `Resize-Partition` on `C:` |
| IIS only on VM1 | `install_iis = true` only for `vm1` in `var.vm_config`; script checks the flag |
| Single extension, no conflicts | One `azurerm_virtual_machine_extension` (`CustomScriptExtension`) per VM does all three post-deploy tasks |

## File layout

```
terraform-winvm/
├── main.tf                     # provider + resource group
├── variables.tf                 # all configurable inputs (incl. admin_password, script_raw_url)
├── network.tf                   # VNet, subnet, NSG (RDP 3389)
├── vm.tf                        # NICs, public IPs, VMs, disks, extension
├── outputs.tf                   # public IPs, VM names, admin username
├── terraform.tfvars.example     # copy to terraform.tfvars and edit
└── scripts/
    └── setup.ps1                # pushed to your own GitHub repo, pulled at runtime
```

## Why GitHub instead of Azure Storage

An earlier version of this config base64-encoded the whole PowerShell script
into the extension's `commandToExecute`. That hit Azure's Custom Script
Extension command-line length limit ("The command line is too long").
The fix used here avoids **both** that limit and the cost of an Azure
Storage account: the script is hosted in your own GitHub repo and the
extension downloads it via `fileUris`, then runs a short command:

```
powershell -ExecutionPolicy Bypass -File setup.ps1 -InstallIIS <true|false>
```

**One-time setup before `terraform apply`:**

This repo already points at a working script by default:

```
https://raw.githubusercontent.com/Shivanshusaxena2/terraformtest01/main/setup.ps1
```

That's baked in as the `default` for `var.script_raw_url` in `variables.tf`,
so you don't need to set anything unless you want to use your own copy —
in which case: push `setup.ps1` (unmodified) to your own **public** GitHub
repo or gist, get its raw URL, and override `script_raw_url` in
`terraform.tfvars`.

The repo must be public (or otherwise reachable without auth) since the
extension's `fileUris` download has no credentials attached in this config.
If you need a private repo, you'd append a GitHub personal access token or
use `?token=...`-style raw URLs, but treat that token as a secret the same
way as the VM password below.

## What the script does

Because it's a single shared script (not rendered per-VM), IIS installation
is controlled by the `-InstallIIS` argument passed in each VM's
`commandToExecute`, which comes from that VM's `install_iis` value in
`var.vm_config`. The script is idempotent — safe to re-run on a VM that
was already partially or fully configured.

1. **Extends `C:`** to fill the full OS disk (e.g. 128 GB → 256 GB) using
   `Resize-Partition`, only if it isn't already at max size.
2. **Data (file share) disk → `F:`**: initializes/formats the raw disk if
   it hasn't been touched yet, or finds an already-initialized data volume
   under a different letter and moves it to `F:`.
3. **DVD/CD-ROM → `Z:`**: re-letters the CD-ROM volume regardless of its
   current letter (`E:`, `F:`, etc.).
4. Installs the `Web-Server` (IIS) Windows feature only when `-InstallIIS true`
   is passed — which happens only for `vm1` by default, and only if IIS
   isn't already installed.

## VM admin password

Per request, `admin_password` has a **hardcoded default** in `variables.tf`:

```
default = "P@ssw0rd1234!"
```

This is convenience over security — anyone with read access to this repo
can see it. For anything beyond a personal sandbox, override it in
`terraform.tfvars` (which you keep out of source control) or via
`TF_VAR_admin_password`, and rotate it if this code is ever shared publicly.

## Prerequisites

- Terraform >= 1.5.0
- Azure CLI logged in (`az login`) or a service principal, with
  `ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`
  set if not using the CLI session
- Contributor rights on the target subscription/resource group
- `scripts/setup.ps1` already pushed to a public GitHub repo/gist (see above)

## Setup

```bash
cd terraform-winvm

# 1. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set script_raw_url to your GitHub raw URL,
# optionally override admin_password, and ideally restrict
# allowed_rdp_source_address_prefix to your own IP/32

# 2. Init, format, validate
terraform init
terraform fmt
terraform validate

# 3. Plan and review
terraform plan -out=tfplan

# 4. Apply
terraform apply tfplan
```

## Outputs

After apply:

```bash
terraform output vm_public_ips
terraform output vm_names
terraform output admin_username
```

Use the public IP + `admin_username` / `admin_password` to RDP into
each VM (port 3389, already allowed by the NSG rule).

## Re-running the script on VMs that already ran it once

Azure's CustomScriptExtension only re-executes when Terraform sees a
change in the extension's settings. Since `commandToExecute`/`fileUris`
don't change just because the *content* of the GitHub-hosted script
changed, this config sets:

```hcl
force_update_tag = filemd5("${path.module}/scripts/setup.ps1")
```

So: edit `scripts/setup.ps1` locally, push the **same content** to your
GitHub repo, then `terraform plan`/`apply` — Terraform will detect the
md5 change and force the extension to re-run on every VM, even ones
where it already succeeded before.

## Verifying the config on a VM

RDP in, then:

- `Get-Volume` → confirms `C:` shows the full 256 GB, `F:` (data disk,
  NTFS) and `Z:` (DVD) exist
- `Get-Partition -DriveLetter C | Select Size` → should be ~256 GB
- `Get-WindowsFeature Web-Server` → `Installed` on `vm1`, not installed on `vm2`
- Extension log: `C:\WindowsAzure\Logs\vm-config.log`
- Extension download/exec logs (if you need to debug the fileUris pull):
  `C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\<version>\`

## Adding more VMs

Add another entry to `vm_config` in `terraform.tfvars`:

```hcl
vm_config = {
  vm1 = { install_iis = true }
  vm2 = { install_iis = false }
  vm3 = { install_iis = false }
}
```

Every dependent resource (NIC, public IP, VM, data disk, extension) is
created automatically via `for_each` — no other file needs to change.

## Notes / things to adjust for production

- `allowed_rdp_source_address_prefix` defaults to `"*"` (open to the
  internet) purely so the demo works out of the box — lock this down to a
  specific CIDR before using this anywhere real.
- Consider Azure Bastion instead of public IPs + open RDP for production.
- The hardcoded `admin_password` default and the public GitHub script are
  both convenience trade-offs requested for this setup — swap in a secrets
  manager (Key Vault, TF Cloud variables, etc.) and a private artifact
  store for anything beyond personal testing.
- Storage account type for disks is `StandardSSD_LRS`; change to
  `Premium_LRS` if you need higher IOPS.
