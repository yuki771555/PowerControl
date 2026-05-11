@echo off
setlocal

set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"

if not exist "%CSC%" (
  echo Could not find the .NET Framework C# compiler.
  echo Install .NET Framework 4.x developer tools or build PowerControl.cs with another C# compiler.
  exit /b 1
)

if exist "%~dp0Build-Icon.ps1" (
  powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Build-Icon.ps1"
  if errorlevel 1 exit /b %ERRORLEVEL%
)

if exist "%~dp0PowerControl.exe" del "%~dp0PowerControl.exe"
"%CSC%" /nologo /target:winexe /win32manifest:"%~dp0PowerControl.exe.manifest" /win32icon:"%~dp0PowerControl.ico" /out:"%~dp0PowerControl.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Runtime.Serialization.dll "%~dp0PowerControl.cs"
if errorlevel 1 exit /b %ERRORLEVEL%

findstr /m /c:"requireAdministrator" "%~dp0PowerControl.exe" >nul
if errorlevel 1 (
  echo PowerControl.exe was built, but the requireAdministrator manifest marker was not found.
  exit /b 1
)

exit /b 0
