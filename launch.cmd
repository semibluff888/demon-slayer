@echo off
setlocal
set "DUEL_GODOT=D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
if not exist "%DUEL_GODOT%" (
  echo Godot was not found at the configured path.
  echo Open project.godot in Godot 4.7.1, or edit DUEL_GODOT in this file.
  pause
  exit /b 1
)
start "" "%DUEL_GODOT%" --path "%~dp0."
