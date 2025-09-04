At **boot time**, Windows drive letters like `G:` and `H:` do not exist. If we hard-code `device partition=H:` in BCD, `bootmgr` will fail, because the firmware/boot loader has no concept of “the H: drive.”

That’s why we need to use **device aliases** that the Windows boot loader understands at boot:

---

## 🔹 Device Aliases That Work in BCD

* `[boot]` → the same partition bootmgr itself was loaded from.
* `partition=\Device\HarddiskVolumeX` → absolute volume reference (not tied to letters).
* `[locate]` or `[path]` in some contexts (rare).

For your dual-partition stick:

* `bootmgr` + `boot.sdi` + BCD are on **FAT32 (ESP)** = `[boot]` partition.
* Your big WIM is on the **NTFS partition**. That partition is *not* `[boot]`, so we must point to it explicitly.

---

## 🔹 How to Safely Point to the NTFS Partition

When you’re setting up BCD *inside Windows* (with both partitions mounted as G: and H:), you can use **partition=H:** during creation.

BCD will resolve that into a *volume identifier* (`\Device\HarddiskVolumeX`) that is portable across boots.

You can confirm with:

```cmd
bcdedit /store G:\boot\bcd /enum all
```

→ It won’t actually say `H:` in the final store — it’ll show a volume GUID or HarddiskVolume reference.

So: **using drive letters when building is OK**, because bcdedit translates them into proper device paths.
**At boot time, there are no drive letters — only the resolved identifiers are used.**

---

## 🔹 Corrected Script Notes

My earlier script used `%DATA%` = `H:`. That works fine at build time, because bcdedit will translate it. But if you want to be explicit and avoid confusion, you can also query the volume GUID of the NTFS partition and use that instead:

```cmd
mountvol H: /L
```

→ Returns something like:

```
\\?\Volume{d3a7f3ac-0000-0000-0000-100000000000}\
```

Then you can substitute in BCD as:

```cmd
bcdedit /store G:\boot\bcd /set %GUID% device ramdisk=[\??\Volume{d3a7f3ac-...}]\sources\WinIRCollector.wim,{ramdiskoptions}
```

---

✅ **Bottom line:**

* Using `H:` (Windows-assigned) at setup time is fine — bcdedit writes the underlying volume ID into the store.
* At boot, no letters exist; the loader uses volume IDs.
* If you want bulletproof reproducibility (e.g., same script on different PCs), resolve the NTFS partition’s **volume GUID** with `mountvol` and use that instead of `H:`.

