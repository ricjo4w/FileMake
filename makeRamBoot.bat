@echo off
setlocal

REM ====== EDIT THESE TWO ======
set "BOOT=G:"                     REM FAT32 boot partition (has \boot, \EFI, bootmgr/bootmgr.efi)
set "WIM=\sources\SmallRAM.wim"   REM Relative path of your WIM on the NTFS partition

REM ====== Derived ======
set "BCDBIOS=%BOOT%\boot\bcd"
set "BCDUEFI=%BOOT%\EFI\Microsoft\Boot\BCD"

echo.
echo === Rebuilding BCD(s) using [locate] ===
echo BOOT : %BOOT%
echo WIM  : %WIM%
echo.

REM -- Minimal sanity: need boot.sdi on BOOT
if not exist "%BOOT%\boot\boot.sdi" (
  echo ERROR: %BOOT%\boot\boot.sdi not found. Copy \boot from a Win10/11 x64 ISO.
  exit /b 1
)

REM ===== BIOS store (\boot\BCD) =====
echo.
echo --- BIOS store: %BCDBIOS% ---
if exist "%BCDBIOS%" del /f /q "%BCDBIOS%" >nul 2>&1
bcdedit /createstore "%BCDBIOS%" >nul

bcdedit /store "%BCDBIOS%" /create {bootmgr} /d "Windows Boot Manager" >nul
bcdedit /store "%BCDBIOS%" /set {bootmgr} device boot
bcdedit /store "%BCDBIOS%" /set {bootmgr} timeout 5
bcdedit /store "%BCDBIOS%" /set {bootmgr} displaybootmenu yes

bcdedit /store "%BCDBIOS%" /create {ramdiskoptions} /d "Ramdisk Options" >nul
bcdedit /store "%BCDBIOS%" /set {ramdiskoptions} ramdisksdidevice boot
bcdedit /store "%BCDBIOS%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi

for /f "tokens=2 delims={}" %%G in ('bcdedit /store "%BCDBIOS%" /create /d "Windows RAM (WIM)" /application osloader') do set "GUID={%%G}"

bcdedit /store "%BCDBIOS%" /set %GUID% device   "ramdisk=[locate]%WIM%,{ramdiskoptions}"
bcdedit /store "%BCDBIOS%" /set %GUID% osdevice "ramdisk=[locate]%WIM%,{ramdiskoptions}"
bcdedit /store "%BCDBIOS%" /set %GUID% path \Windows\System32\winload.exe
bcdedit /store "%BCDBIOS%" /set %GUID% systemroot \Windows
bcdedit /store "%BCDBIOS%" /set %GUID% detecthal Yes
bcdedit /store "%BCDBIOS%" /displayorder %GUID% /addlast
bcdedit /store "%BCDBIOS%" /default %GUID%

echo BIOS store done.
bcdedit /store "%BCDBIOS%" /enum {default}

REM ===== UEFI store (\EFI\Microsoft\Boot\BCD) — only if folder exists =====
if exist "%BOOT%\EFI\Microsoft\Boot" (
  echo.
  echo --- UEFI store: %BCDUEFI% ---
  if exist "%BCDUEFI%" del /f /q "%BCDUEFI%" >nul 2>&1
  bcdedit /createstore "%BCDUEFI%" >nul

  bcdedit /store "%BCDUEFI%" /create {bootmgr} /d "Windows Boot Manager" >nul
  bcdedit /store "%BCDUEFI%" /set {bootmgr} device boot
  bcdedit /store "%BCDUEFI%" /set {bootmgr} timeout 5
  bcdedit /store "%BCDUEFI%" /set {bootmgr} displaybootmenu yes

  bcdedit /store "%BCDUEFI%" /create {ramdiskoptions} /d "Ramdisk Options" >nul
  bcdedit /store "%BCDUEFI%" /set {ramdiskoptions} ramdisksdidevice boot
  bcdedit /store "%BCDUEFI%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi

  for /f "tokens=2 delims={}" %%G in ('bcdedit /store "%BCDUEFI%" /create /d "Windows RAM (WIM)" /application osloader') do set "GUID={%%G}"

  bcdedit /store "%BCDUEFI%" /set %GUID% device   "ramdisk=[locate]%WIM%,{ramdiskoptions}"
  bcdedit /store "%BCDUEFI%" /set %GUID% osdevice "ramdisk=[locate]%WIM%,{ramdiskoptions}"
  bcdedit /store "%BCDUEFI%" /set %GUID% path \Windows\System32\winload.exe
  bcdedit /store "%BCDUEFI%" /set %GUID% systemroot \Windows
  bcdedit /store "%BCDUEFI%" /set %GUID% detecthal Yes
  bcdedit /store "%BCDUEFI%" /displayorder %GUID% /addlast
  bcdedit /store "%BCDUEFI%" /default %GUID%

  echo UEFI store done.
  bcdedit /store "%BCDUEFI%" /enum {default}
)

echo.
echo === Finished. Boot in BIOS (uses \boot\BCD) or UEFI (uses \EFI\Microsoft\Boot\BCD). ===
echo NOTE: Because [locate] is used, ensure ONLY ONE attached disk contains %WIM%.
echo.
pause
endlocal
