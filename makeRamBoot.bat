# Point to boot store on USB
bcdedit /store U:\boot\bcd /create {ramdiskoptions} /d "Ramdisk Options"
bcdedit /store U:\boot\bcd /set {ramdiskoptions} ramdisksdidevice partition=U:
bcdedit /store U:\boot\bcd /set {ramdiskoptions} ramdisksdipath \boot\boot.sdi

# Create Windows boot entry
for /f "tokens=3" %A in ('bcdedit /store U:\boot\bcd /create /d "Windows RAMOS" /application osloader') do set guid=%A

bcdedit /store U:\boot\bcd /set %guid% device ramdisk=[U:]\sources\FullWin.wim,{ramdiskoptions}
bcdedit /store U:\boot\bcd /set %guid% osdevice ramdisk=[U:]\sources\FullWin.wim,{ramdiskoptions}
bcdedit /store U:\boot\bcd /set %guid% path \Windows\System32\winload.exe
bcdedit /store U:\boot\bcd /set %guid% systemroot \Windows
bcdedit /store U:\boot\bcd /set %guid% detecthal Yes
bcdedit /store U:\boot\bcd /displayorder %guid% /addlast
