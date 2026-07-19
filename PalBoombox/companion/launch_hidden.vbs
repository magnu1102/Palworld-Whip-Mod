Option Explicit

Dim fileSystem, shell, scriptPath, command
Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptPath = fileSystem.BuildPath( _
    fileSystem.GetParentFolderName(WScript.ScriptFullName), _
    "boombox_companion.ps1")
command = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " _
    & Chr(34) & scriptPath & Chr(34)

' Window style 0 is fully hidden. Do not wait: Lua only needs to dispatch the
' single-instance companion and immediately return to the game thread.
shell.Run command, 0, False
