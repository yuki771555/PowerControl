@echo off
start "" powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0PowerControl.ps1"
