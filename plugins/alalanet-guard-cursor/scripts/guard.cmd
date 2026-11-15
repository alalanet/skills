@echo off
REM alalanet guard for Cursor on Windows. hooks/hooks.json runs ./scripts/guard with no extension: on Windows
REM PowerShell finds this file through PATHEXT; on macOS and Linux the sh script "guard" next to it runs instead.
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0guard-windows.ps1"
exit /b %ERRORLEVEL%
