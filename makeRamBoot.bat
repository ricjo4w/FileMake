@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: CONFIG
set "BOOT=G:"                          :: FAT32 partition (boot files/BCD)
set "DATA=H:"                          :: NTFS partition (big WIM lives here)
set "WIM=\sources\WinIRCollector.wim"  :: Path to WIM on NTFS partition
set "DESC=Windows RAMOS"

set "BCD=%BOOT%\boot\bcd"
set "SDI=\boot\boot.sdi"

echo === Rebuilding BCD on %BOOT% (FAT32) to load WIM from %DATA% (NTFS) ===

:: Sanity checks
if not exist "%BOOT%\bootmgr" (
  echo ERROR: %BOOT%\bootmgr not found. Copy boot files from Windows ISO.
  exit /b 1
)
if not exist "%BOOT%%SDI%" (
  echo ERROR: %BOOT%%SDI% not found. Ensure boot.sdi is present.
  exit /b 1
)
if not exist "%DATA%%WIM%" (
  echo ERROR: %DATA%%WIM% not found. Place your custom WIM there.
  exit /b 1
)

:: Backup existing BCD
if exist "%BCD%" (
  copy /y "%BCD%" "%BCD%.bak" >nul
  del /f /q "%BCD%"
)

:: Create empty store
bcdedit /createstore "%BCD%" || (echo ERROR: createstore failed & exit /b 1)

:: Create boot manager
bcdedit /store "%BCD%" /create {bootmgr} /d "Windows Boot Manager"
bcdedit /store "%BCD%" /set {bootmgr} device boot
bcdedit /store "%BCD%" /set {bootmgr} timeout 5
bcdedit /store "%BCD%" /set {bootmgr} displaybootmenu yes

:: Ramdisk options
bcdedit /store "%BCD%" /create {ramdiskoptions} /d "Ramdisk Options"
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi

:: Create loader entry
for /f "usebackq tokens=2 delims={}" %%G in (`
  bcdedit /store "%BCD%" /create /d "%DESC%" /application osloader
`) do set "GUID={%%G}"

if not defined GUID (
  echo ERROR: Could not create loader entry
  exit /b 1
)

:: Point to WIM on NTFS partition
bcdedit /store "%BCD%" /set %GUID% device   ramdisk=[%DATA%]%WIM%,{ramdiskoptions}
bcdedit /store "%BCD%" /set %GUID% osdevice ramdisk=[%DATA%]%WIM%,{ramdiskoptions}
bcdedit /store "%BCD%" /set %GUID% path \Windows\System32\winload.exe
bcdedit /store "%BCD%" /set %GUID% systemroot \Windows
bcdedit /store "%BCD%" /set %GUID% detecthal Yes

:: Add to boot menu
bcdedit /store "%BCD%" /displayorder %GUID% /addlast
bcdedit /store "%BCD%" /default %GUID%

echo.
echo === BCD setup complete. Verify with: bcdedit /store %BCD% /enum all ===
echo.
pause
endlocal
