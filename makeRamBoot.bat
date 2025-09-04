@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ===== CONFIG =====
set "BOOT=H:"                                :: FAT32 (boot files)
set "DATA=G:"                                :: NTFS (WIM lives here)  -- only used for sanity check
set "WIM=\sources\SmallRAM.wim"              :: path to WIM on the NTFS partition
set "DESC=SmallRAM"
:: Use NT native path, NOT \\?\  (no trailing backslash!)
set "VOLGUID=\??\Volume{04695db3-890e-11f0-a428-bdff3da90986}"

:: ===== DERIVED =====
set "BCD=%BOOT%\boot\bcd"
set "SDI=\boot\boot.sdi"

echo === Rebuilding BCD on %BOOT% (FAT32) to load WIM from Volume %VOLGUID% ===

:: --- Sanity checks ---
if not exist "%BOOT%\bootmgr" (
  echo ERROR: %BOOT%\bootmgr not found. Copy boot files from Windows x64 ISO.
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

:: --- Backup existing BCD and start fresh ---
if exist "%BCD%" (
  copy /y "%BCD%" "%BCD%.bak" >nul
  del /f /q "%BCD%" >nul 2>&1
)

echo Creating empty BCD store...
bcdedit /createstore "%BCD%" || (echo ERROR: createstore failed & exit /b 1)

echo Configuring {bootmgr}...
bcdedit /store "%BCD%" /create {bootmgr} /d "Windows Boot Manager" >nul || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /set {bootmgr} device boot || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /set {bootmgr} timeout 5  || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /set {bootmgr} displaybootmenu yes || (echo ERROR & exit /b 1)

echo Creating {ramdiskoptions}...
bcdedit /store "%BCD%" /create {ramdiskoptions} /d "Ramdisk Options" >nul || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdidevice boot || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi || (echo ERROR & exit /b 1)

echo Creating Windows loader entry...
for /f "usebackq tokens=2 delims={}" %%G in (`
  bcdedit /store "%BCD%" /create /d "%DESC%" /application osloader
`) do set "GUID={%%G}"
if not defined GUID (echo ERROR: Could not create loader entry & exit /b 1)

:: === KEY FIX: use NT path form \??\Volume{GUID} with NO trailing backslash inside [] ===
set "RAMDISK_SPEC=ramdisk=[%VOLGUID%]%WIM%,{ramdiskoptions}"

echo Configuring loader %GUID% ...
bcdedit /store "%BCD%" /set %GUID% device   "%RAMDISK_SPEC%" || (echo ERROR setting device & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% osdevice "%RAMDISK_SPEC%" || (echo ERROR setting osdevice & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% path \Windows\System32\winload.exe || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% systemroot \Windows || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% detecthal Yes || (echo ERROR & exit /b 1)

bcdedit /store "%BCD%" /displayorder %GUID% /addlast || (echo ERROR & exit /b 1)
bcdedit /store "%BCD%" /default %GUID% || (echo ERROR & exit /b 1)

echo.
echo === BCD setup complete. Verify with: bcdedit /store "%BCD%" /enum all ===
echo.
pause
endlocal
