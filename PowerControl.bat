@echo off
if exist "%~dp0PowerControl.exe" (
  start "" "%~dp0PowerControl.exe"
  exit /b
)
start "" powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0PowerControl.ps1"
