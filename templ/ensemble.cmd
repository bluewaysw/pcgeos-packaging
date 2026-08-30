@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "UPDATE_MARKER=%SCRIPT_DIR%update.txt"
set "RUN_LAUNCHER=%SCRIPT_DIR%BASEBOX\ensemble-run.cmd"
set "LOG_FILE=%SCRIPT_DIR%ensemble.log"

if exist "%UPDATE_MARKER%" (
    call :promote_pending_launcher "%SCRIPT_DIR%BASEBOX\ensemble-run.cmd"
    if errorlevel 1 exit /b 1

    call :promote_pending_launcher "%SCRIPT_DIR%BASEBOX\ensemble-run.sh"
    if errorlevel 1 exit /b 1

    del /q "%UPDATE_MARKER%" >nul 2>&1
    if exist "%UPDATE_MARKER%" >> "%LOG_FILE%" echo update: failed to delete marker "%UPDATE_MARKER%"
)

if not exist "%RUN_LAUNCHER%" (
    echo Error: Missing launcher at "%RUN_LAUNCHER%".
    exit /b 1
)

call "%RUN_LAUNCHER%" %*
exit /b %ERRORLEVEL%

:promote_pending_launcher
set "ACTIVE_LAUNCHER=%~1"
set "PENDING_LAUNCHER=%ACTIVE_LAUNCHER%.update"

if exist "%PENDING_LAUNCHER%" (
    copy /Y "%PENDING_LAUNCHER%" "%ACTIVE_LAUNCHER%" >nul
    if errorlevel 1 (
        >> "%LOG_FILE%" echo update: failed to promote "%PENDING_LAUNCHER%" to "%ACTIVE_LAUNCHER%"
        if not exist "%ACTIVE_LAUNCHER%" (
            echo Error: Could not install launcher update and no launcher exists at "%ACTIVE_LAUNCHER%".
            exit /b 1
        )
    ) else (
        >> "%LOG_FILE%" echo update: promoted "%PENDING_LAUNCHER%" to "%ACTIVE_LAUNCHER%"
        del /q "%PENDING_LAUNCHER%" >nul 2>&1
        if exist "%PENDING_LAUNCHER%" >> "%LOG_FILE%" echo update: failed to delete pending launcher "%PENDING_LAUNCHER%"
    )
) else (
    >> "%LOG_FILE%" echo update: marker exists but pending launcher is missing: "%PENDING_LAUNCHER%"
)

exit /b 0
