# Run as Administrator
$BootLabel = 'Boot'                         # FAT32 partition label
$WimLabel  = 'WIM'                          # NTFS partition label
$WimRel    = '\sources\WinIRCollector.wim'  # Path to WIM on the NTFS partition
$Desc      = 'Windows RAM (WIM)'

function Fail($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# Locate volumes by label (returns \\?\Volume{GUID}\ style paths in .Path)
$bootVol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq $BootLabel }
$wimVol  = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq $WimLabel  }
if(!$bootVol){ Fail "FAT32 volume labeled '$BootLabel' not found." }
if(!$wimVol){  Fail "NTFS volume labeled '$WIMLabel' not found."    }

if($bootVol.FileSystem -ne 'FAT32'){ Fail "Volume '$BootLabel' must be FAT32. Found $($bootVol.FileSystem)." }
if($wimVol.FileSystem  -ne 'NTFS'){  Fail "Volume '$WimLabel' must be NTFS. Found $($wimVol.FileSystem)."    }

$bootRoot = $bootVol.Path.TrimEnd('\')  # e.g. \\?\Volume{GUID}
$wimRoot  = $wimVol.Path.TrimEnd('\')

# Validate required boot files (allow either UEFI or BIOS artifacts)
$okBoot = @(
  Test-Path "$bootRoot\EFI\Boot\bootx64.efi",
  Test-Path "$bootRoot\EFI\Microsoft\Boot\bootmgfw.efi",
  Test-Path "$bootRoot\bootmgr.efi",
  Test-Path "$bootRoot\bootmgr"
) -contains $true
if(-not $okBoot){ Fail "No UEFI/BIOS boot file found on '$BootLabel' (expected one of: \EFI\Boot\bootx64.efi, \EFI\Microsoft\Boot\bootmgfw.efi, \bootmgr.efi, \bootmgr)" }

# Need boot.sdi for RAMDISK
if(!(Test-Path "$bootRoot\boot\boot.sdi")){ Fail "Missing $bootRoot\boot\boot.sdi (copy entire \boot from ISO)" }

# Validate WIM location (on NTFS)
if(!(Test-Path "$wimRoot$WimRel")){ Fail "Missing $wimRoot$WimRel (place your WIM there)" }

# Prepare BCD locations for UEFI and BIOS
$BcdUefi = "$bootRoot\EFI\Microsoft\Boot\BCD"
$BcdBios = "$bootRoot\boot\BCD"

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "$bootRoot\EFI\Microsoft\Boot" | Out-Null
New-Item -ItemType Directory -Force -Path "$bootRoot\boot"              | Out-Null

# Helper: run bcdedit against a store and fail on error
function BE { param([string]$Store, [string[]]$Args)
  $all = @('/store', $Store) + $Args
  $p = Start-Process bcdedit.exe -ArgumentList $all -NoNewWindow -Wait -PassThru
  if($p.ExitCode -ne 0){ Fail ("bcdedit failed: " + ($all -join ' ')) }
}

# Create both stores fresh (UEFI + BIOS)
foreach($store in @($BcdUefi,$BcdBios)){
  if(Test-Path $store){ Copy-Item $store "$store.bak" -Force; Remove-Item $store -Force }
  & bcdedit /createstore $store | Out-Null
  if($LASTEXITCODE -ne 0){ Fail "createstore failed for $store" }

  # {bootmgr}
  BE $store @('/create','{bootmgr}','/d','Windows Boot Manager')
  BE $store @('/set','{bootmgr}','device','boot')
  BE $store @('/set','{bootmgr}','timeout','5')
  BE $store @('/set','{bootmgr}','displaybootmenu','yes')

  # {ramdiskoptions}
  BE $store @('/create','{ramdiskoptions}','/d','Ramdisk Options')
  BE $store @('/set','{ramdiskoptions}','ramdisksdidevice','boot')
  BE $store @('/set','{ramdiskoptions}','ramdisksdipath','\boot\boot.sdi')

  # OS loader entry
  $out = & bcdedit /store $store /create /d $Desc /application osloader
  if($LASTEXITCODE -ne 0){ Fail "Failed to create OS loader for $store" }
  if($out -match '{([0-9a-fA-F\-]+)}'){ $guid = "{${Matches[1]}}" } else { Fail "Could not parse loader GUID for $store: $out" }

  # Use [locate] so no drive letters/volume GUIDs are needed.
  $ramdiskSpec = "ramdisk=[locate]$WimRel,{ramdiskoptions}"

  BE $store @('/set',$guid,'device',  $ramdiskSpec)
  BE $store @('/set',$guid,'osdevice',$ramdiskSpec)
  BE $store @('/set',$guid,'path','\Windows\System32\winload.exe')
  BE $store @('/set',$guid,'systemroot','\Windows')
  BE $store @('/set',$guid,'detecthal','Yes')
  BE $store @('/displayorder',$guid,'/addlast')
  BE $store @('/default',$guid)

  Write-Host "`nStore ready: $store"
  & bcdedit /store $store /enum all
  Write-Host ""
}

Write-Host "Done. This USB should now boot in UEFI (uses $BcdUefi) and BIOS (uses $BcdBios)."
