@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =======================
:: CONFIG - EDIT THESE
:: =======================
set "BOOT=H:"                          :: FAT32 boot partition (contains \boot, \EFI, bootmgr/bootmgr.efi)
set "DATA=G:"                          :: NTFS partition where the WIM file lives (only for sanity checks)
set "WIM=\sources\SmallRAM.wim"        :: Relative path of your WIM on the NTFS partition
set "DESC=Windows RAM (WIM)"

:: =======================
:: DERIVED
:: =======================
set "BCDBIOS=%BOOT%\boot\bcd"
set "BCDUEFI=%BOOT%\EFI\Microsoft\Boot\BCD"
set "SDI=\boot\boot.sdi"

echo === Building BCD using [locate] (no device hard-coding) ===
echo BOOT (FAT32): %BOOT%
echo DATA (NTFS) : %DATA%
echo WIM path   : %WIM%
echo.

:: -------- Sanity checks --------
if not exist "%BOOT%" (echo ERROR: BOOT path "%BOOT%" not found & exit /b 1)
if not exist "%DATA%" (echo ERROR: DATA path "%DATA%" not found & exit /b 1)

:: Require boot.sdi on the BOOT volume
if not exist "%BOOT%%SDI%" (
  echo ERROR: %BOOT%%SDI% not found. Copy the entire \boot folder from a Windows x64 ISO.
  exit /b 1
)

:: Require at least one boot manager file (UEFI or BIOS)
if not exist "%BOOT%\bootmgr" if not exist "%BOOT%\bootmgr.efi" if not exist "%BOOT%\EFI\Boot\bootx64.efi" if not exist "%BOOT%\EFI\Microsoft\Boot\bootmgfw.efi" (
  echo ERROR: No boot manager file found on %BOOT%.
  echo        Copy these from a Windows x64 ISO: \bootmgr, \bootmgr.efi, \EFI\Boot\bootx64.efi (UEFI), etc.
  exit /b 1
)

:: WIM exists on the DATA volume at the given relative path?
if not exist "%DATA%%WIM%" (
  echo ERROR: %DATA%%WIM% not found. Put your WIM there (exact path).
  exit /b 1
)

:: Ensure folders for BCD exist
if not exist "%BOOT%\boot" mkdir "%BOOT%\boot"
if not exist "%BOOT%\EFI\Microsoft\Boot" mkdir "%BOOT%\EFI\Microsoft\Boot"

:: -------- Helper macro to run bcdedit with a target store and fail on error --------
set "BE=bcdedit /store"

:: -------- Function-like label to build one store (BIOS or UEFI) --------
:: %1 = full path to BCD store
:BUILD_STORE
if "%~1"=="" goto :eof
set "STORE=%~1"

echo.
echo --- (Re)building store: %STORE% ---

:: backup old store if present
if exist "%STORE%" (
  copy /y "%STORE%" "%STORE%.bak" >nul
  del /f /q "%STORE%" >nul 2>&1
)

:: Create empty store
bcdedit /createstore "%STORE%" >nul
if errorlevel 1 (echo ERROR: createstore failed for %STORE% & exit /b 1)

:: {bootmgr}
%BE% "%STORE%" /create {bootmgr} /d "Windows Boot Manager" >nul
if errorlevel 1 (echo ERROR: create {bootmgr} failed & exit /b 1)
%BE% "%STORE%" /set {bootmgr} device boot
%BE% "%STORE%" /set {bootmgr} timeout 5
%BE% "%STORE%" /set {bootmgr} displaybootmenu yes

:: {ramdiskoptions}
%BE% "%STORE%" /create {ramdiskoptions} /d "Ramdisk Options" >nul
if errorlevel 1 (echo ERROR: create {ramdiskoptions} failed & exit /b 1)
%BE% "%STORE%" /set {ramdiskoptions} ramdisksdidevice boot
%BE% "%STORE%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi

:: Create OS loader entry and capture GUID
for /f "usebackq tokens=2 delims={}" %%G in (`
  bcdedit /store "%STORE%" /create /d "%DESC%" /application osloader
`) do set "GUID={%%G}"
if not defined GUID (echo ERROR: failed to create loader entry in %STORE% & exit /b 1)

:: Use [locate] so no device/volume is hard-coded. Keep the WIM path unique on all attached disks!
set "RAMDISK_SPEC=ramdisk=[locate]%WIM%,{ramdiskoptions}"

%BE% "%STORE%" /set %GUID% device   "%RAMDISK_SPEC%"
if errorlevel 1 (echo ERROR: set device failed & exit /b 1)
%BE% "%STORE%" /set %GUID% osdevice "%RAMDISK_SPEC%"
if errorlevel 1 (echo ERROR: set osdevice failed & exit /b 1)
%BE% "%STORE%" /set %GUID% path \Windows\System32\winload.exe
%BE% "%STORE%" /set %GUID% systemroot \Windows
%BE% "%STORE%" /set %GUID% detecthal Yes

%BE% "%STORE%" /displayorder %GUID% /addlast
%BE% "%STORE%" /default %GUID%

echo Store built: %STORE%
%BE% "%STORE%" /enum all

set "GUID="
goto :eof

:: -------- Build BIOS store --------
call :BUILD_STORE "%BCDBIOS%"

:: -------- Build UEFI store (only if UEFI files exist) --------
if exist "%BOOT%\EFI\Microsoft\Boot" (
  call :BUILD_STORE "%BCDUEFI%"
)

echo.
echo === Done. Boot in BIOS (uses \boot\BCD) or UEFI (uses \EFI\Microsoft\Boot\BCD). ===
echo NOTE: Because [locate] is used, ensure ONLY ONE attached drive contains %WIM%.
echo.
pause
endlocal
