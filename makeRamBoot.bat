@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =======================
:: CONFIGURE THESE TWO LINES
:: =======================
set "USB=U:"                       :: <-- your USB root
set "WIM=\sources\FullWin.wim"     :: <-- your WIM path on the USB

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

:: --- Sanity checks ---
if not exist "%USB%\bootmgr" (
  echo ERROR: %USB%\bootmgr not found. Copy it from the Windows ISO.
  exit /b 1
)
if not exist "%USB%%SDI%" (
  echo ERROR: %USB%%SDI% not found. Copy the entire \boot folder from the Windows ISO.
  exit /b 1
)
if not exist "%USB%%WIM%" (
  echo ERROR: %USB%%WIM% not found. Put your WIM at that path.
  exit /b 1
)

:: --- Ensure \boot exists ---
if not exist "%USB%\boot" mkdir "%USB%\boot"

:: --- Backup any existing BCD and start fresh ---
if exist "%BCD%" (
  echo Backing up existing BCD to %USB%\boot\bcd.bak ...
  copy /y "%BCD%" "%USB%\boot\bcd.bak" >nul
  del /f /q "%BCD%" >nul 2>&1
)

echo Creating empty BCD store...
bcdedit /createstore "%BCD%" || (echo ERROR: createstore failed & exit /b 1)

echo Configuring {bootmgr}...
bcdedit /store "%BCD%" /create {bootmgr} /d "Windows Boot Manager" >nul || (echo ERROR: create bootmgr failed & exit /b 1)
bcdedit /store "%BCD%" /set {bootmgr} device boot || (echo ERROR: set bootmgr device failed & exit /b 1)
bcdedit /store "%BCD%" /set {bootmgr} timeout 5  || (echo ERROR: set timeout failed & exit /b 1)
bcdedit /store "%BCD%" /set {bootmgr} displaybootmenu yes || (echo ERROR: set displaybootmenu failed & exit /b 1)

echo Creating {ramdiskoptions}...
bcdedit /store "%BCD%" /create {ramdiskoptions} /d "Ramdisk Options" >nul || (echo ERROR: create ramdiskoptions failed & exit /b 1)
:: **** KEY CHANGE HERE ****
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdidevice boot || (echo ERROR: set ramdisksdidevice failed & exit /b 1)
bcdedit /store "%BCD%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi || (echo ERROR: set ramdisksdipath failed & exit /b 1)

echo Creating Windows loader entry...
for /f "usebackq tokens=2 delims={}" %%G in (`
  bcdedit /store "%BCD%" /create /d "%DESC%" /application osloader
`) do set "GUID={%%G}"

if not defined GUID (
  echo ERROR: Could not capture loader GUID.
  exit /b 1
)

echo Configuring loader %GUID% ...
bcdedit /store "%BCD%" /set %GUID% device   ramdisk=[boot]%WIM%,{ramdiskoptions} || (echo ERROR: set device failed & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% osdevice ramdisk=[boot]%WIM%,{ramdiskoptions} || (echo ERROR: set osdevice failed & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% path \Windows\System32\winload.exe         || (echo ERROR: set path failed & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% systemroot \Windows                        || (echo ERROR: set systemroot failed & exit /b 1)
bcdedit /store "%BCD%" /set %GUID% detecthal Yes                              || (echo ERROR: set detecthal failed & exit /b 1)

echo Adding loader to boot menu...
bcdedit /store "%BCD%" /displayorder %GUID% /addlast || (echo ERROR: displayorder failed & exit /b 1)
bcdedit /store "%BCD%" /default %GUID%               || (echo ERROR: default failed & exit /b 1)

echo.
echo Done. Verifying store:
bcdedit /store "%BCD%" /enum all

echo.
echo SUCCESS. Boot this USB in LEGACY BIOS/CSM mode.
endlocal
