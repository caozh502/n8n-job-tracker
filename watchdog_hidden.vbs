' =====================================================================
'  watchdog_hidden.vbs - silent launcher for the 5-minute watchdog task.
'
'  Runs watchdog.bat (/nopause) with NO console window (window style 0)
'  and waits for the check to finish, so an overlapping run is avoided
'  by Task Scheduler's IgnoreNew policy if a restart takes a while.
' =====================================================================
Option Explicit

Dim fso, sh, baseDir, target
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
target  = fso.BuildPath(baseDir, "watchdog.bat")

If fso.FileExists(target) Then
    sh.Run """" & target & """ /nopause", 0, True
End If
