@echo off
setlocal

set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"

if not exist "%CSC%" (
  echo Could not find the .NET Framework C# compiler.
  echo Install .NET Framework 4.x developer tools or build PowerControl.cs with another C# compiler.
  exit /b 1
)

"%CSC%" /nologo /target:winexe /out:"%~dp0PowerControl.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Runtime.Serialization.dll "%~dp0PowerControl.cs"
exit /b %ERRORLEVEL%
