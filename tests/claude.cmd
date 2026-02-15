@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock-claude.ps1" %*
