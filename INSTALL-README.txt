PALWHIP + FIELD BOOMBOX - POWERSHELL INSTALLER
==============================================

1. Close Palworld completely.
2. Extract the entire PalWhip-Installer.zip to a normal folder.
3. Double-click Install-PalWhip.cmd.
4. Approve the Windows administrator prompt.
5. Wait for the successful completion message.

The CMD launcher runs the included install.ps1 with PowerShell's execution-policy
bypass. This prevents Windows RemoteSigned policy from silently blocking a PS1
that came from the Internet. Advanced users may instead unblock install.ps1 in
its file Properties and choose "Run with PowerShell".

The installer locates Steam Palworld automatically, downloads UE4SS and
PalSchema from their official releases when missing, applies required settings,
and installs PalWhip plus Field Boombox. It is safe to rerun for updates:
existing configuration and the complete installed music folder are preserved.

Do not run install.ps1 from inside the ZIP. Extract every file first.
