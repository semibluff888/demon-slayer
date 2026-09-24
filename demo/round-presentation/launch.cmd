@echo off
setlocal
set "DEMO_GODOT=D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
if not "%~1"=="" set "DEMO_GODOT=%~1"
if not exist "%DEMO_GODOT%" (
  echo Godot not found. Pass the Godot executable as the first argument.
  pause
  exit /b 1
)
pushd "%~dp0..\.."
start "" "%DEMO_GODOT%" --path "%CD%" res://demo/round-presentation/demo.tscn
popd
