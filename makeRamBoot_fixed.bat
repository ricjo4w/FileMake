@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================================
rem  makeRamBoot_fixed.bat
rem  Build BIOS and UEFI BCD stores to boot a WIM into RAM (Windows PE or WIMBOOT)
rem  Layout (two partitions on the USB):
rem    - BOOT (FAT32): \boot\boot.sdi, \efi\microsoft\boot\*, \efi\boot\bootx64.efi
rem    - WIM  (NTFS) : \sources\SmallRAM.wim   (or another WIM path you set below)
rem
rem  IMPORTANT:
rem   • Running full desktop Windows entirely from a RAM-loaded WIM is *not* supported.
rem     This technique is for WinPE/WIMBOOT scenarios. If your WIM is a full Windows
rem     capture from a VHD, consider creating a PE-based WIM instead or use VHD(X) boot.
rem   • The script uses [locate] so make sure ONLY ONE attached disk has the target WIM.
rem   • Run this from an elevated command prompt on a Windows 10/11 host.
rem ============================================================================

rem ====== EDIT THESE TWO ======
set "BOOT=H:"                     rem FAT32 EFI/BIOS system partition (holds \boot and \efi)
set "WIMREL=\sources\SmallRAM.wim" rem Relative path to the WIM ON THE NTFS DATA PARTITION

rem ====== Optional: PE mode flag (Yes recommended for RAM-WIM) ======
set "WINPE=No"

rem ====== Derived paths ======
set "BCDBIOS=%BOOT%\boot\bcd"
set "BCDUEFI=%BOOT%\efi\microsoft\boot\bcd"
set "BOOTSDI=%BOOT%\boot\boot.sdi"
set "BOOTMGFW=%BOOT%\efi\microsoft\boot\bootmgfw.efi"
set "BOOTX64=%BOOT%\efi\boot\bootx64.efi"

echo.
echo === Config ===
echo   BOOT   : %BOOT%
echo   WIMREL : %WIMREL%
echo   BCDBIOS: %BCDBIOS%
echo   BCDUEFI: %BCDUEFI%
echo   WINPE  : %WINPE%
echo.

rem ====== Basic validation ======
if not exist "%BOOT%\" (
  echo [ERROR] BOOT volume "%BOOT%" not found.
  goto :fail
)
if not exist "%BOOTSDI%" (
  echo [ERROR] "%BOOTSDI%" is missing. You must copy boot.sdi from a Windows ISO (usually \boot\boot.sdi).
  goto :fail
)
if not exist "%BOOT%\efi\microsoft\boot\" (
  echo [ERROR] EFI Microsoft boot folder is missing at "%BOOT%\efi\microsoft\boot".
  echo         You can copy it from a Windows ISO (mount ISO, copy \efi\microsoft\boot).
  goto :fail
)

rem Ensure \efi\boot\bootx64.efi exists for removable-media UEFI boot
if not exist "%BOOTX64%" (
  if exist "%BOOTMGFW%" (
    echo [INFO] Copying bootmgfw.efi to \efi\boot\bootx64.efi ...
    copy /y "%BOOTMGFW%" "%BOOTX64%" >nul || (
      echo [WARN] Could not copy bootmgfw.efi to %BOOTX64%.
    )
  ) else (
    echo [WARN] Neither %BOOTX64% nor %BOOTMGFW% exists. UEFI removable boot may fail.
  )
)

echo.
echo === Rebuilding BIOS BCD ===
rem Create a clean BIOS BCD
del /f /q "%BCDBIOS%" 2>nul
bcdedit /createstore "%BCDBIOS%" || goto :bd_err

rem Create {bootmgr} object and set timeout
bcdedit /store "%BCDBIOS%" /create {bootmgr} /d "Windows Boot Manager" >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /set {bootmgr} timeout 5 >nul || goto :bd_err

rem Create an OS loader entry and capture its GUID
for /f "tokens=2 delims={}" %%G in ('bcdedit /store "%BCDBIOS%" /create /d "Windows RAM (WIM)" /application osloader') do set "OSGUID_BIOS={%%G}"

if not defined OSGUID_BIOS (
  echo [ERROR] Failed to create BIOS osloader entry.
  goto :fail
)
echo [INFO] BIOS loader GUID: %OSGUID_BIOS%

rem Create the ramdiskoptions object implicitly by referencing it when setting device/osdevice
rem First set ramdiskoptions (SDI device+path)
bcdedit /store "%BCDBIOS%" /set {ramdiskoptions} ramdisksdidevice partition=[locate] >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi >nul || goto :bd_err

rem Now point device/osdevice to the WIM (RAMDISK) and set required fields
bcdedit /store "%BCDBIOS%" /set %OSGUID_BIOS% device ramdisk=[locate]%WIMREL%,{ramdiskoptions} >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /set %OSGUID_BIOS% osdevice ramdisk=[locate]%WIMREL%,{ramdiskoptions} >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /set %OSGUID_BIOS% path \Windows\System32\winload.exe >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /set %OSGUID_BIOS% systemroot \Windows >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /set %OSGUID_BIOS% detecthal Yes >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /set %OSGUID_BIOS% winpe %WINPE% >nul || goto :ignore_pe_bios

:ignore_pe_bios
bcdedit /store "%BCDBIOS%" /displayorder %OSGUID_BIOS% /addlast >nul || goto :bd_err
bcdedit /store "%BCDBIOS%" /default %OSGUID_BIOS% >nul || goto :bd_err
echo [OK] BIOS store complete.
bcdedit /store "%BCDBIOS%" /enum {default}

echo.
echo === Rebuilding UEFI BCD ===
rem Create a clean UEFI BCD
del /f /q "%BCDUEFI%" 2>nul
bcdedit /createstore "%BCDUEFI%" || goto :ue_err

rem Create {bootmgr} object and set timeout
bcdedit /store "%BCDUEFI%" /create {bootmgr} /d "Windows Boot Manager" >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /set {bootmgr} timeout 5 >nul || goto :ue_err

rem Create a UEFI OS loader entry and capture its GUID
for /f "tokens=2 delims={}" %%G in ('bcdedit /store "%BCDUEFI%" /create /d "Windows RAM (WIM)" /application osloader') do set "OSGUID_UEFI={%%G}"

if not defined OSGUID_UEFI (
  echo [ERROR] Failed to create UEFI osloader entry.
  goto :fail
)
echo [INFO] UEFI loader GUID: %OSGUID_UEFI%

rem Set ramdiskoptions for UEFI store
bcdedit /store "%BCDUEFI%" /set {ramdiskoptions} ramdisksdidevice partition=[locate] >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi >nul || goto :ue_err

rem Point to WIM and set EFI loader path
bcdedit /store "%BCDUEFI%" /set %OSGUID_UEFI% device ramdisk=[locate]%WIMREL%,{ramdiskoptions} >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /set %OSGUID_UEFI% osdevice ramdisk=[locate]%WIMREL%,{ramdiskoptions} >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /set %OSGUID_UEFI% path \Windows\System32\winload.efi >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /set %OSGUID_UEFI% systemroot \Windows >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /set %OSGUID_UEFI% detecthal Yes >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /set %OSGUID_UEFI% winpe %WINPE% >nul || goto :ignore_pe_uefi

:ignore_pe_uefi
bcdedit /store "%BCDUEFI%" /displayorder %OSGUID_UEFI% /addlast >nul || goto :ue_err
bcdedit /store "%BCDUEFI%" /default %OSGUID_UEFI% >nul || goto :ue_err
echo [OK] UEFI store complete.
bcdedit /store "%BCDUEFI%" /enum {default}

echo.
echo === All done ===
echo Boot (BIOS) uses \boot\bcd    ; Boot (UEFI) uses \efi\microsoft\boot\bcd
echo Ensure only one disk has %WIMREL% so [locate] finds the correct file.
echo.
pause
goto :eof

:bd_err
echo [ERROR] A BCDEDIT command failed while building the BIOS store.
goto :fail

:ue_err
echo [ERROR] A BCDEDIT command failed while building the UEFI store.
goto :fail

:fail
echo.
echo Script failed. Review messages above and fix any missing files/paths.
exit /b 1
