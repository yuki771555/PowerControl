@echo off
start "" /b powershell.exe -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PowerControl.ps1"
