' Opens the Distraction Log app without a console window.
' Optional argument (from a notification click), e.g. distractionlog:plan
Set fso = CreateObject("Scripting.FileSystemObject")
script = fso.GetParentFolderName(WScript.ScriptFullName) & "\app.ps1"
target = ""
If WScript.Arguments.Count > 0 Then
    Set re = New RegExp
    re.Pattern = "[^a-zA-Z]"
    re.Global = True
    target = LCase(re.Replace(Replace(LCase(WScript.Arguments(0)), "distractionlog:", ""), ""))
End If
cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & script & """"
If target <> "" Then cmd = cmd & " -Open " & target
CreateObject("WScript.Shell").Run cmd, 0, False
