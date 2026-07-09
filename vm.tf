resource "azurerm_public_ip" "pip" {
  for_each = var.vm_config

  name                = "pip-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  for_each = var.vm_config

  name                = "nic-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[each.key].id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  for_each = var.vm_config

  name                = each.key
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.nic[each.key].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_managed_disk" "data_disk" {
  for_each = var.vm_config

  name                 = "disk-data-${each.key}"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attach" {
  for_each = var.vm_config

  managed_disk_id    = azurerm_managed_disk.data_disk[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.vm[each.key].id
  lun                = 0
  caching            = "ReadWrite"
}

# ------------------------------------------------------------------
# Single Custom Script Extension per VM (no conflicting extensions).
# One shared script (scripts/setup.ps1) handles everything:
#   1. Extends C: to use the full 256 GB OS disk
#   2. Brings the data ("file share") disk online -> F:
#   3. Moves the DVD/CD-ROM drive letter -> Z:
#   4. Installs IIS only when -InstallIIS true is passed (VM1 only)
#
# The script is pulled at runtime from a raw GitHub URL (var.script_raw_url)
# via fileUris — no Azure Storage account/blob is created, so there's no
# extra storage cost.
#
# force_update_tag is set to the local script's md5 hash so that editing
# scripts/setup.ps1 (and pushing the same content to GitHub) forces this
# extension to re-run on VMs where it already succeeded once — otherwise
# Terraform sees no diff in commandToExecute/fileUris and skips it.
# ------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "config" {
  for_each = var.vm_config

  name                       = "config-${each.key}"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm[each.key].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  force_update_tag           = filemd5("${path.module}/scripts/setup.ps1")

  settings = jsonencode({
    fileUris = [var.script_raw_url]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -File setup.ps1 -InstallIIS ${each.value.install_iis}"
  })

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.data_disk_attach
  ]
}
