@echo off
rem Double-click to fix NVIDIA Code 43 on an eGPU (M.2 -> OCuLink). Accept the UAC prompt.
rem Cift tiklayin, UACye Evet deyin.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-NvidiaEgpuCode43.ps1"
