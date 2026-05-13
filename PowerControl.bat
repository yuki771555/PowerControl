@echo off
setlocal

set "APP=%~dp0PowerControl.exe"
set "BUILD=%~dp0Build-PowerControl.bat"

if exist "%BUILD%" (
  call "%BUILD%"
  if errorlevel 1 (
    if not exist "%APP%" exit /b 1
    echo Build failed. Starting the existing PowerControl.exe.
  )
)

if exist "%APP%" (
  start "" "%APP%"
  exit /b 0
)

echo PowerControl.exe was not found and could not be built.
exit /b 1
