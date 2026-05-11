@echo off
setlocal

set "APP=%~dp0PowerControl.exe"
set "BUILD=%~dp0Build-PowerControl.bat"

if exist "%BUILD%" (
  call "%BUILD%"
  if errorlevel 1 exit /b %ERRORLEVEL%
)

if exist "%APP%" (
  start "" "%APP%"
  exit /b 0
)

echo PowerControl.exe was not found and could not be built.
exit /b 1
