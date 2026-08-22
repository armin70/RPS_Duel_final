@echo off
setlocal

set "RPS_EXPORT_PRESET=%~dp0export_presets.cfg"

if not exist "%RPS_EXPORT_PRESET%" (
    echo ERROR: export_presets.cfg was not found next to this file.
    echo Put this file in the Godot project root and run it again.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$path = $env:RPS_EXPORT_PRESET;" ^
  "$text = [System.IO.File]::ReadAllText($path);" ^
  "if ($text -notmatch '(?m)^permissions/vibrate=(?:false|true)\s*$') { throw 'Android vibrate permission was not found in export_presets.cfg.' };" ^
  "$updated = [System.Text.RegularExpressions.Regex]::Replace($text, '(?m)^permissions/vibrate=(?:false|true)\s*$', 'permissions/vibrate=true');" ^
  "$utf8 = New-Object System.Text.UTF8Encoding($false);" ^
  "[System.IO.File]::WriteAllText($path, $updated, $utf8);"

if errorlevel 1 (
    echo ERROR: Android vibration permission could not be enabled.
    pause
    exit /b 1
)

echo Android VIBRATE permission is enabled.
echo Export a new APK or AAB from Godot before testing.
pause
