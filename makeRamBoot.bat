@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =======================
:: CONFIGURE THESE TWO LINES
:: =======================
set "USB=U:"                       :: <-- USB drive letter (root of the stick)
set "WIM=\sources\FullWin.wim"     :: <-- Path to your RAM-boot WIM on the USB

:: =======================
:: Do not edit below
:: =======================
set "BCD=%USB%\boot\bcd"
set "SDI=\boot\boot.sdi"
set "DESC=Windows RAM (WIM)"

echo === BIOS BCD (re)build for RAM-boot ===
echo USB root : %USB%
echo WIM path : %WIM%
echo BCD path : %BCD%
echo.

:: Sanity checks
if not exist "%USB%\bootmgr" (
  echo ERROR: %USB%\bootmgr not found. Copy it from the Windows ISO.
  exit /b 1
)
if not exist "%USB%\boot\boot.sdi" (
  echo ERROR: %USB%\boot\boot.sdi not found. Copy the entire \boot folder from the Windows ISO.
  exit /b 1
)
if not exist "%USB%%WIM%" (
  echo ERROR: %USB%%WIM% not found. Put your WIM at that path.
  exit /b 1
)

:: Ensure \boot exists
if not exist "%USB%\boot" mkdir "%USB%\boot"

:: Backup any existing BCD
if exist "%BCD%" (
  echo Backing up existing BCD to %USB%\boot\bcd.bak ...
  copy /y "%BCD%" "%USB%\boot\bcd.bak" >nul
  del /f /q "%BCD%" >nul 2>&1
)

echo Creating empty BCD store...
bcdedit /createstore "%BCD%" || (echo ERROR: createstore failed & exit /b 1)

echo Configuring {bootmgr}...
bcdedit /store "%BCD%" /create {bootmgr} /d "Windows Boot Manager" >nul
bcdedit /store "%BCD%" /set {bootmgr} device boot
bcdedit /store "%BCD%" /set {bootmgr} timeout 5
bcdedit /store "%BCD%" /set {bootmgr} displaybootmenu yes

echo Creating {ramdiskoptions}...
bcdedit /store "%BCD%" /create {ramdiskoptions} /d "Ramdisk Options" >nul
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdidevice partition=[boot]
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi

echo Creating Windows loader entry...
for /f "usebackq tokens=2 delims={}" %%G in (`
  bcdedit /store "%BCD%" /create /d "%DESC%" /application osloader
`) do set "GUID={%%G}"

if not defined GUID (
  echo ERROR: Could not capture loader GUID.
  exit /b 1
)

echo Configuring loader %GUID% ...
bcdedit /store "%BCD%" /set %GUID% device ramdisk=[boot]%WIM%,{ramdiskoptions}
bcdedit /store "%BCD%" /set %GUID% osdevice ramdisk=[boot]%WIM%,{ramdiskoptions}
bcdedit /store "%BCD%" /set %GUID% path \Windows\System32\winload.exe
bcdedit /store "%BCD%" /set %GUID% systemroot \Windows
bcdedit /store "%BCD%" /set %GUID% detecthal Yes

:: (Optional, sometimes helps for RAM-booted WIM scenarios)
:: bcdedit /store "%BCD%" /set %GUID% nointegritychecks on
:: bcdedit /store "%BCD%" /set %GUID% testsigning on

echo Adding loader to boot menu...
bcdedit /store "%BCD%" /displayorder %GUID% /addlast
bcdedit /store "%BCD%" /default %GUID%

echo.
echo Done. Verifying store:
bcdedit /store "%BCD%" /enum all

echo.
echo SUCCESS. You can now boot this USB in LEGACY BIOS/CSM mode.
endlocal
