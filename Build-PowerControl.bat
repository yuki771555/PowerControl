@echo off
setlocal

set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
set "OUT=%~dp0PowerControl.exe"
set "TEMP_EXE=%TEMP%\PowerControl-%RANDOM%-%RANDOM%.exe"

if not exist "%CSC%" (
  echo Could not find the .NET Framework C# compiler.
  echo Install .NET Framework 4.x developer tools or build PowerControl.cs with another C# compiler.
  exit /b 1
)

if exist "%~dp0Build-Icon.ps1" (
  powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Build-Icon.ps1"
  if errorlevel 1 exit /b 1
)

if exist "%TEMP_EXE%" del "%TEMP_EXE%"
"%CSC%" /nologo /target:winexe /win32manifest:"%~dp0PowerControl.exe.manifest" /win32icon:"%~dp0PowerControl.ico" /out:"%TEMP_EXE%" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Runtime.Serialization.dll "%~dp0PowerControl.cs"
if errorlevel 1 exit /b %ERRORLEVEL%

findstr /m /c:"requireAdministrator" "%TEMP_EXE%" >nul
if errorlevel 1 (
  echo PowerControl.exe was built, but the requireAdministrator manifest marker was not found.
  if exist "%TEMP_EXE%" del "%TEMP_EXE%"
  exit /b 1
)

move /y "%TEMP_EXE%" "%OUT%" >nul
if errorlevel 1 (
  echo Failed to replace PowerControl.exe. Close any running copy and try again.
  if exist "%TEMP_EXE%" del "%TEMP_EXE%"
  exit /b 1
)

exit /b 0
