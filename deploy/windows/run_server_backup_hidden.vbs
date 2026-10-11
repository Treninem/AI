Option Explicit

If WScript.Arguments.Count <> 3 Then
    WScript.Quit 2
End If

Function QuoteArgument(value)
    QuoteArgument = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function

Dim command, shell
command = QuoteArgument(WScript.Arguments(0)) & _
    " -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & _
    QuoteArgument(WScript.Arguments(1)) & " -ConfigPath " & QuoteArgument(WScript.Arguments(2))

Set shell = CreateObject("WScript.Shell")
WScript.Quit shell.Run(command, 0, True)
