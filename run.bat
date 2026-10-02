@echo off
setlocal
title GameLoop - WASD Speed Fix
cd /d "%~dp0"

:menu
cls
echo ============================================================
echo    GameLoop - WASD / joystick speed fix
echo ============================================================
echo.
echo    Makes WASD direction changes INSTANT instead of sluggish.
echo.
echo    CLOSE GAMELOOP COMPLETELY FIRST (tray icon too).
echo.
echo ------------------------------------------------------------
echo    1)  Show current state          (nothing is changed)
echo    2)  APPLY the fix               (recommended)
echo    3)  Preview only                (dry run)
echo    4)  Show which config files exist
echo    5)  Fix only one game
echo    6)  Undo - restore latest backup
echo    7)  Exit
echo ------------------------------------------------------------
echo.
set "choice="
set /p choice="    Choose [1-7]: "

if "%choice%"=="1" goto act_diagnose
if "%choice%"=="2" goto act_apply
if "%choice%"=="3" goto act_dryrun
if "%choice%"=="4" goto act_list
if "%choice%"=="5" goto act_onegame
if "%choice%"=="6" goto act_restore
if "%choice%"=="7" exit /b

echo.
echo    Not a valid choice.
timeout /t 2 >nul
goto menu

:act_diagnose
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-WasdSpeed.ps1" -Diagnose
goto done

:act_apply
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-WasdSpeed.ps1"
goto done

:act_dryrun
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-WasdSpeed.ps1" -DryRun
goto done

:act_list
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-WasdSpeed.ps1" -List
goto done

:act_restore
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-WasdSpeed.ps1" -Restore
goto done

:act_onegame
cls
echo ============================================================
echo    Fix only one game
echo ============================================================
echo.
echo    Enter the game's package name.
echo    Common ones:
echo       com.tencent.ig        PUBG Mobile
echo       com.tencent.igfit     PUBG Mobile (Flash / Lite client)
echo       com.dts.freefireth    Free Fire
echo       com.garena.game.kgth  Garena Free Fire
echo.
echo    Use option 1 first if you are not sure what you have.
echo.
set "pkg="
set /p pkg="    Package name: "
if "%pkg%"=="" goto menu
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-WasdSpeed.ps1" -App "%pkg%"
goto done

:done
echo.
echo ------------------------------------------------------------
pause
goto menu
