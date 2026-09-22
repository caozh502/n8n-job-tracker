' =====================================================================
'  start_hidden.vbs - silent launcher for the logon scheduled task.
'
'  Runs start_n8n.bat with NO console window (window style 0 = hidden)
'  and waits for it to finish, so the scheduled task "n8n Job Tracker
'  Start" stays in the Running state while the services come up
'  (Task Scheduler's IgnoreNew policy then prevents an overlapping run).
'
'  Manual runs: just double-click start_n8n.bat instead.
' =====================================================================
Option Explicit

Dim fso, sh, baseDir, target
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
target  = fso.BuildPath(baseDir, "start_n8n.bat")

If fso.FileExists(target) Then
    sh.Run """" & target & """ /nopause", 0, True
End If
