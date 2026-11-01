@echo off
rem Packs the logs of the last game into one zip to send with a report. Run it after closing the game.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-Logs.ps1"
pause
