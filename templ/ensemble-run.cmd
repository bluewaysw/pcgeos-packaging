@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if "%BASEBOX_BUILD%"=="" set "BASEBOX_BUILD={{BASEBOX_BUILD}}"

set "ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "ARCH=%PROCESSOR_ARCHITEW6432%"

set "BASEBOX_BIN_DIR=binnt64"
if /I "%ARCH%"=="AMD64" set "BASEBOX_BIN_DIR=binnt64"
if /I "%ARCH%"=="IA64" set "BASEBOX_BIN_DIR=binnt64"
if /I "%ARCH%"=="ARM64" set "BASEBOX_BIN_DIR=binnt64"

for %%I in ("%SCRIPT_DIR%..") do set "ENSEMBLE_DIR=%%~fI"
for %%I in ("%ENSEMBLE_DIR%") do set "LAUNCH_DIR_NAME=%%~nxI"
set "BASEBOX_EXEC=%ENSEMBLE_DIR%\BASEBOX\%BASEBOX_BUILD%\%BASEBOX_BIN_DIR%\{{WINDOWS_BASEBOX_EXE}}"
set "BASE_CONFIG_FILE=%ENSEMBLE_DIR%\basebox.conf"
set "LAUNCH_TEMPLATE_CONFIG_FILE=%ENSEMBLE_DIR%\BASEBOX\basebox.launch.templ.conf"
set "LAUNCH_CONFIG_FILE=%ENSEMBLE_DIR%\BASEBOX\basebox.launch.conf"
set "LOG_FILE=%ENSEMBLE_DIR%\ensemble.log"
> "%LOG_FILE%" echo [%DATE% %TIME%] start: %~nx0 %*
>> "%LOG_FILE%" echo basebox: "%BASEBOX_EXEC%"

if "%LAUNCH_DIR_NAME%"=="" (
    >> "%LOG_FILE%" echo error: could not resolve launcher directory name from "%ENSEMBLE_DIR%"
    echo Error: Could not resolve launcher directory name from "%ENSEMBLE_DIR%".
    exit /b 1
)

if not exist "%BASE_CONFIG_FILE%" (
    >> "%LOG_FILE%" echo error: missing static config "%BASE_CONFIG_FILE%"
    echo Error: Missing static config at "%BASE_CONFIG_FILE%".
    exit /b 1
)

if not exist "%LAUNCH_TEMPLATE_CONFIG_FILE%" (
    >> "%LOG_FILE%" echo error: missing launch template config "%LAUNCH_TEMPLATE_CONFIG_FILE%"
    echo Error: Missing launch template config at "%LAUNCH_TEMPLATE_CONFIG_FILE%".
    exit /b 1
)

findstr /C:"{{LAUNCH_DIR_NAME}}" "%LAUNCH_TEMPLATE_CONFIG_FILE%" >nul
if errorlevel 1 (
    >> "%LOG_FILE%" echo error: placeholder {{LAUNCH_DIR_NAME}} not found in launch template "%LAUNCH_TEMPLATE_CONFIG_FILE%"
    echo Error: Missing {{LAUNCH_DIR_NAME}} placeholder in launch template "%LAUNCH_TEMPLATE_CONFIG_FILE%".
    exit /b 1
)

set "TEMP_CONFIG_FILE=%LAUNCH_CONFIG_FILE%.tmp"
setlocal EnableDelayedExpansion
> "%TEMP_CONFIG_FILE%" (
    for /f "usebackq delims=" %%L in ("%LAUNCH_TEMPLATE_CONFIG_FILE%") do (
        set "LINE=%%L"
        set "LINE=!LINE:{{LAUNCH_DIR_NAME}}=%LAUNCH_DIR_NAME%!"
        echo(!LINE!
    )
)
endlocal

if not exist "%TEMP_CONFIG_FILE%" (
    >> "%LOG_FILE%" echo error: failed to generate launch config "%LAUNCH_CONFIG_FILE%" from template "%LAUNCH_TEMPLATE_CONFIG_FILE%"
    echo Error: Could not generate launch config at "%LAUNCH_CONFIG_FILE%".
    exit /b 1
)

findstr /C:"{{LAUNCH_DIR_NAME}}" "%TEMP_CONFIG_FILE%" >nul
if not errorlevel 1 (
    del /q "%TEMP_CONFIG_FILE%" >nul 2>&1
    >> "%LOG_FILE%" echo error: unresolved placeholder remained in generated config "%TEMP_CONFIG_FILE%"
    echo Error: Generated launch config still contains {{LAUNCH_DIR_NAME}} in "%LAUNCH_CONFIG_FILE%".
    exit /b 1
)

move /Y "%TEMP_CONFIG_FILE%" "%LAUNCH_CONFIG_FILE%" >nul
if errorlevel 1 (
    del /q "%TEMP_CONFIG_FILE%" >nul 2>&1
    >> "%LOG_FILE%" echo error: failed to write launch config "%LAUNCH_CONFIG_FILE%"
    echo Error: Could not write launch config at "%LAUNCH_CONFIG_FILE%".
    exit /b 1
)

>> "%LOG_FILE%" echo config: generated "%LAUNCH_CONFIG_FILE%" from template "%LAUNCH_TEMPLATE_CONFIG_FILE%" (launch dir: "%LAUNCH_DIR_NAME%")

if not exist "%BASEBOX_EXEC%" (
    >> "%LOG_FILE%" echo error: missing executable "%BASEBOX_EXEC%"
    echo Error: Expected Basebox executable not found at "%BASEBOX_EXEC%".
    exit /b 1
)

>> "%LOG_FILE%" echo launch: request submitted
start "" /D "%ENSEMBLE_DIR%" "%BASEBOX_EXEC%" -noconsole -noprimaryconf -nolocalconf -conf "%BASE_CONFIG_FILE%" -conf "%LAUNCH_CONFIG_FILE%" %*
if errorlevel 1 (
    >> "%LOG_FILE%" echo error: failed to start basebox
    echo Error: Could not start Basebox.
    exit /b 1
)

>> "%LOG_FILE%" echo launcher: exiting after detached launch
exit /b 0
