PALWHIP + FIELD BOOMBOX - UNINSTALL
===================================

1. In Palworld, dismantle every placed Field Boombox.
2. Discard every Boombox and Pal Whip item.
3. Close Palworld completely.
4. Double-click Uninstall-PalWhip.cmd.
5. Approve the Windows administrator prompt.
6. Type UNINSTALL and press Enter.

The uninstaller backs up both configuration files and the complete music folder
under Documents\PalWhip Backups before it removes anything.

Only PalWhip, PalBoombox, PalWhipItem, and PalBoomboxItem are removed. UE4SS,
PalSchema, unrelated mods, shared loader files, and Palworld saves are untouched.

The CMD launcher intentionally starts PowerShell with ExecutionPolicy Bypass so
Windows does not silently block the downloaded PS1 file under RemoteSigned.
