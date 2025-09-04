# Requires: Windows 10/11, Admin
# Purpose: Build a fresh BCD on the FAT32 "Boot" partition that RAM-boots a WIM on the NTFS "WIM" partition,
#          without using drive letters in the BCD entries.

$BootLabel = 'Boot'   # FAT32 EFI/Boot partition label
$WimLabel  = 'WIM'    # NTFS data partition label
$WimRel    = '\sources\WinIRCollector.wim'  # relative path to your WIM (on the NTFS partition)
$Desc      = 'Windows RAM (WIM)'

function Fail($msg){ Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# 1) Locate volumes by LABEL (no drive letters needed)
$bootVol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq $BootLabel }
$wimVol  = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq $WimLabel  }

if(!$bootVol){ Fail "Volume with label '$BootLabel' not found." }
if(!$wimVol){  Fail "Volume with label '$WimLabel' not found."  }

if($bootVol.FileSystem -ne 'FAT32'){ Fail "Volume '$BootLabel' must be FAT32 (is $($bootVol.FileSystem))." }
if($wimVol.FileSystem  -ne 'NTFS'){  Fail "Volume '$WimLabel' must be NTFS (is $($wimVol.FileSystem))." }

# Get canonical volume GUID paths (end with backslash), e.g. \\?\Volume{GUID}\
$bootRoot = $bootVol.Path.TrimEnd('\')
$wimRoot  = $wimVol.Path.TrimEnd('\')

# 2) Validate required files
if(!(Test-Path "$bootRoot\bootmgr"))     { Fail "Missing $bootRoot\bootmgr (copy from Windows x64 ISO)" }
if(!(Test-Path "$bootRoot\boot\boot.sdi")){ Fail "Missing $bootRoot\boot\boot.sdi (copy entire \boot from ISO)" }
if(!(Test-Path "$wimRoot$WimRel"))       { Fail "Missing $wimRoot$WimRel (place your WIM there)" }

# Ensure \boot exists on the FAT32 partition
if(!(Test-Path "$bootRoot\boot")){ New-Item -ItemType Directory -Path "$bootRoot\boot" | Out-Null }

# 3) Create brand-new BCD store on FAT32 using its volume GUID path
$bcd = "$bootRoot\boot\bcd"

if(Test-Path $bcd){
  Copy-Item $bcd "$bcd.bak" -Force
  Remove-Item $bcd -Force
}

# Helper to run bcdedit against our store
function BE { param([string[]]$Args)
  $all = @('/store', $bcd) + $Args
  $p = Start-Process -FilePath bcdedit.exe -ArgumentList $all -NoNewWindow -Wait -PassThru
  if($p.ExitCode -ne 0){ Fail ("bcdedit failed: " + ($all -join ' ')) }
}

Write-Host "Creating empty BCD store at $bcd ..."
& bcdedit /createstore $bcd | Out-Null
if($LASTEXITCODE -ne 0){ Fail "createstore failed" }

# 4) {bootmgr}
BE @('/create','{bootmgr}','/d','Windows Boot Manager')
BE @('/set','{bootmgr}','device','boot')
BE @('/set','{bootmgr}','timeout','5')
BE @('/set','{bootmgr}','displaybootmenu','yes')

# 5) {ramdiskoptions} (note: no drive letters — use 'boot' alias for SDI)
BE @('/create','{ramdiskoptions}','/d','Ramdisk Options')
BE @('/set','{ramdiskoptions}','ramdisksdidevice','boot')
BE @('/set','{ramdiskoptions}','ramdisksdipath','\boot\boot.sdi')

# 6) Create OS loader and capture GUID
Write-Host "Creating Windows loader entry..."
$createOut = & bcdedit /store $bcd /create /d $Desc /application osloader
if($LASTEXITCODE -ne 0){ Fail "Failed to create OS loader" }
if($createOut -match '{([0-9a-fA-F\-]+)}'){ $guid = "{${Matches[1]}}" } else { Fail "Could not parse loader GUID from: $createOut" }
Write-Host "Loader GUID: $guid"

# 7) Point to the WIM WITHOUT letters, using [locate] (bootmgr will search all volumes)
#    This avoids hard-coding a partition. Keep WIM path unique across all attached volumes.
$ramdiskSpec = "ramdisk=[locate]$WimRel,{ramdiskoptions}"
BE @('/set',$guid,'device',  $ramdiskSpec)
BE @('/set',$guid,'osdevice',$ramdiskSpec)

# 8) Standard loader settings
BE @('/set',$guid,'path','\Windows\System32\winload.exe')
BE @('/set',$guid,'systemroot','\Windows')
BE @('/set',$guid,'detecthal','Yes')

# 9) Add to menu + set default
BE @('/displayorder',$guid,'/addlast')
BE @('/default',$guid)

Write-Host "`nBCD build complete. Verifying..."
& bcdedit /store $bcd /enum all
Write-Host "`nDone. You can now boot from the USB (UEFI or BIOS)."
