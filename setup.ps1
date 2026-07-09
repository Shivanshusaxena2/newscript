param(
    [Parameter(Mandatory = $false)]
    [string]$InstallIIS = "false"
)

# ============================================================
# VM configuration script, downloaded from GitHub and run on each
# VM via the CustomScriptExtension. Idempotent: safe to re-run.
#   1. Extends C: to use all available disk space
#   2. Brings the data ("file share") disk online -> F:
#   3. Moves the DVD/CD-ROM drive letter -> Z:
#   4. Installs IIS only when -InstallIIS true is passed
# ============================================================

$ErrorActionPreference = "Stop"
$logDir  = "C:\WindowsAzure\Logs"
$logFile = Join-Path $logDir "vm-config.log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File -FilePath $logFile -Append
}

Write-Log "===== Starting VM configuration script. InstallIIS=$InstallIIS ====="

# ------------------------------------------------------------
# 1. Extend C: (OS) partition to use all available space.
#    Azure disk may be 256 GB while the Windows partition is
#    still the original 128 GB image size — grow it to match.
# ------------------------------------------------------------
try {
    $cPartition = Get-Partition -DriveLetter C
    $maxSize    = (Get-PartitionSupportedSize -DriveLetter C).SizeMax

    if ($maxSize -gt $cPartition.Size) {
        $beforeGb = [math]::Round($cPartition.Size / 1GB, 2)
        $afterGb  = [math]::Round($maxSize / 1GB, 2)
        Write-Log "Extending C: from $beforeGb GB to $afterGb GB."
        Resize-Partition -DriveLetter C -Size $maxSize
        Write-Log "C: partition extended successfully to $afterGb GB."
    }
    else {
        $currentGb = [math]::Round($cPartition.Size / 1GB, 2)
        Write-Log "C: is already at maximum size ($currentGb GB). No resize needed."
    }
}
catch {
    Write-Log "ERROR while extending C: drive: $_"
}

# ------------------------------------------------------------
# 2. Bring the data ("file share") disk online, initialize if
#    needed, and ensure it ends up mounted as F:.
# ------------------------------------------------------------
try {
    if (Get-Volume -DriveLetter F -ErrorAction SilentlyContinue) {
        Write-Log "F: already exists. Assuming data disk is already mounted correctly."
    }
    else {
        $rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' }

        if ($rawDisks) {
            foreach ($disk in $rawDisks) {
                Write-Log "Initializing raw disk number $($disk.Number)."
                Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru |
                    New-Partition -DriveLetter F -UseMaximumSize |
                    Format-Volume -FileSystem NTFS -NewFileSystemLabel "DataDisk" -Confirm:$false | Out-Null
                Write-Log "Data disk (number $($disk.Number)) initialized and formatted as F:."
            }
        }
        else {
            # Disk may already be initialized under a different drive
            # letter from an earlier run (e.g. D:) — find the non-OS,
            # non-DVD fixed volume and move it to F:.
            $candidate = Get-Partition | Where-Object {
                $_.DriveLetter -and $_.DriveLetter -notin @('C', 'F')
            } | Where-Object {
                $vol = Get-Volume -Partition $_ -ErrorAction SilentlyContinue
                $vol -and $vol.DriveType -eq 'Fixed'
            } | Select-Object -First 1

            if ($candidate) {
                Write-Log "Found existing data volume on $($candidate.DriveLetter): — moving it to F:."
                Set-Partition -DriveLetter $candidate.DriveLetter -NewDriveLetter F
                Write-Log "Data disk moved to F: successfully."
            }
            else {
                Write-Log "No raw disk and no existing data volume found to mount as F:."
            }
        }
    }
}
catch {
    Write-Log "ERROR while configuring the data (file share) disk: $_"
}

# ------------------------------------------------------------
# 3. Move the DVD/CD-ROM drive letter to Z:
# ------------------------------------------------------------
try {
    $dvdDrives = Get-WmiObject -Class Win32_Volume -Filter "DriveType=5"

    if ($dvdDrives) {
        foreach ($drive in $dvdDrives) {
            if ($drive.DriveLetter -ne "Z:") {
                Write-Log "Changing DVD drive letter from '$($drive.DriveLetter)' to Z:."
                $drive.DriveLetter = "Z:"
                $drive.Put() | Out-Null
                Write-Log "DVD drive letter changed to Z: successfully."
            }
            else {
                Write-Log "DVD drive is already Z:. No change needed."
            }
        }
    }
    else {
        Write-Log "No DVD/CD-ROM drive found on this VM."
    }
}
catch {
    Write-Log "ERROR while changing DVD drive letter: $_"
}

# ------------------------------------------------------------
# 4. Conditionally install IIS (only when -InstallIIS true, e.g. VM1)
# ------------------------------------------------------------
$installIisNormalized = $InstallIIS.Trim().ToLower()

if ($installIisNormalized -eq "true") {
    try {
        if ((Get-WindowsFeature -Name Web-Server).Installed) {
            Write-Log "IIS already installed. Skipping."
        }
        else {
            Write-Log "InstallIIS = true. Installing IIS (Web-Server role)."
            Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
            Write-Log "IIS installed successfully."
        }
    }
    catch {
        Write-Log "ERROR while installing IIS: $_"
    }
}
else {
    Write-Log "InstallIIS = false. Skipping IIS installation on this VM."
}

Write-Log "===== VM configuration script completed ====="
