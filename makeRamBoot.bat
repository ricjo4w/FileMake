@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: === CONFIG ===
set "USB=U:"                 :: <-- your USB drive letter
set "WIM=\sources\FullWin.wim"
set "SDI=\boot\boot.sdi"
set "DESC=Windows RAMOS"

:: Sanity checks
if not exist "%USB%\boot\bcd" (
  echo ERROR: "%USB%\boot\bcd" not found.
  exit /b 1
)
if not exist "%USB%%SDI%" (
  echo ERROR: "%USB%%SDI%" not found.
  exit /b 1
)
if not exist "%USB%%WIM%" (
  echo ERROR: "%USB%%WIM%" not found.
  exit /b 1
)

:: Create/ensure ramdiskoptions object
bcdedit /store "%USB%\boot\bcd" /create {ramdiskoptions} /d "Ramdisk Options" >nul 2>&1
bcdedit /store "%USB%\boot\bcd" /set {ramdiskoptions} ramdisksdidevice partition=%USB%
if errorlevel 1 exit /b 1
bcdedit /store "%USB%\boot\bcd" /set {ramdiskoptions} ramdisksdipath "%SDI%"
if errorlevel 1 exit /b 1

:: Create the OS loader entry and capture its GUID.
:: We parse the line 'The entry {GUID} was successfully created.'
for /f "usebackq tokens=2 delims={}" %%G in (`
  bcdedit /store "%USB%\boot\bcd" /create /d "%DESC%" /application osloader
`) do set "GUID={%%G}"

if not defined GUID (
  echo ERROR: Could not capture GUID from bcdedit /create.
  exit /b 1
)
echo Created loader entry %GUID%

:: Point the new entry at the WIM (RAMDISK) and configure boot settings
bcdedit /store "%USB%\boot\bcd" /set %GUID% device ramdisk=[%USB%]%WIM%,{ramdiskoptions}
if errorlevel 1 exit /b 1
bcdedit /store "%USB%\boot\bcd" /set %GUID% osdevice ramdisk=[%USB%]%WIM%,{ramdiskoptions}
if errorlevel 1 exit /b 1
bcdedit /store "%USB%\boot\bcd" /set %GUID% path \Windows\System32\winload.exe
if errorlevel 1 exit /b 1
bcdedit /store "%USB%\boot\bcd" /set %GUID% systemroot \Windows
if errorlevel 1 exit /b 1
bcdedit /store "%USB%\boot\bcd" /set %GUID% detecthal Yes
if errorlevel 1 exit /b 1
bcdedit /store "%USB%\boot\bcd" /displayorder %GUID% /addlast
if errorlevel 1 exit /b 1

echo Success. Boot entry added for RAM WIM.
endlocal
