@echo off
REM Build the MTFPulse SKSE plugin.
REM
REM Usage:
REM   build.bat              configure + build (release)
REM   build.bat debug        configure + build (debug)
REM   build.bat configure    configure only
REM
REM First run pulls deps:
REM   - Clones extern/CommonLibSSE-NG if missing.
REM   - vcpkg installs spdlog/fmt/rapidcsv via VS-bundled vcpkg.
setlocal

set "VS_ROOT=C:\Program Files\Microsoft Visual Studio\18\Community"
set "VCVARS=%VS_ROOT%\VC\Auxiliary\Build\vcvars64.bat"
set "VCPKG_TOOLCHAIN=%VS_ROOT%\VC\vcpkg\scripts\buildsystems\vcpkg.cmake"
set "VCPKG_EXE=%VS_ROOT%\VC\vcpkg\vcpkg.exe"

if not exist "%VCVARS%" (
    echo Cannot find vcvars64 at: %VCVARS%
    echo Update VS_ROOT in build.bat if your install path differs.
    exit /b 1
)

set BUILD_TYPE=Release
if /I "%~1"=="debug" set BUILD_TYPE=Debug
set BUILD_DIR=build\x64-%BUILD_TYPE%

pushd "%~dp0"

REM 1) CommonLibSSE-NG clone (idempotent).
if not exist extern\CommonLibSSE-NG\CMakeLists.txt (
    echo === Cloning CommonLibSSE-NG ===
    if not exist extern mkdir extern
    git clone --depth 1 --branch v3.7.0 https://github.com/CharmedBaryon/CommonLibSSE-NG.git extern\CommonLibSSE-NG || (popd & exit /b 1)
)

REM 2) vcpkg manifest install (idempotent — manifest hash gates rebuild).
echo === vcpkg install ===
"%VCPKG_EXE%" install --triplet x64-windows-static-md || (popd & exit /b 1)

REM 3) CMake configure (always runs to pick up file additions).
echo === CMake configure ===
call "%VCVARS%" >nul
cmake -S . -B %BUILD_DIR% ^
  -G "Visual Studio 18 2026" -A x64 ^
  -DCMAKE_BUILD_TYPE=%BUILD_TYPE% ^
  -DCMAKE_TOOLCHAIN_FILE="%VCPKG_TOOLCHAIN%" ^
  -DVCPKG_TARGET_TRIPLET=x64-windows-static-md ^
  -DCMAKE_PREFIX_PATH="%~dp0vcpkg_installed\x64-windows-static-md"
if errorlevel 1 (popd & exit /b 1)

if /I "%~1"=="configure" (
    popd
    exit /b 0
)

REM 4) Build.
echo === cmake --build ===
cmake --build %BUILD_DIR% --config %BUILD_TYPE% -- -m
set EC=%ERRORLEVEL%

if %EC%==0 (
    echo.
    echo MTFPulse.dll: %~dp0%BUILD_DIR%\%BUILD_TYPE%\MTFPulse.dll
)

REM 5) Sync the Release artifact forward so no copy can go stale (mirrors
REM    build_scripts.sh, which deploys .pex on every compile). data\ is the
REM    repo-canonical copy the FOMOD falls back to when the build dir is
REM    absent; the dev-modlist copy is what the game loads. Debug builds are
REM    intentionally NOT synced. Instance deploys (LoreRim/AuthoriaRR) stay
REM    manual — those are live playthroughs, not dev targets.
if %EC%==0 if /I "%BUILD_TYPE%"=="Release" (
    copy /Y "%~dp0%BUILD_DIR%\%BUILD_TYPE%\MTFPulse.dll" "%~dp0..\data\SKSE\Plugins\MTFPulse.dll" >nul 2>&1 && (echo Synced: data\SKSE\Plugins\MTFPulse.dll) || (echo WARNING: data\ DLL sync FAILED - copy manually)
    if exist "F:\Modlists\Modding Essentials\mods\Magic Tattoos Framework\SKSE\Plugins\" (
        copy /Y "%~dp0%BUILD_DIR%\%BUILD_TYPE%\MTFPulse.dll" "F:\Modlists\Modding Essentials\mods\Magic Tattoos Framework\SKSE\Plugins\MTFPulse.dll" >nul 2>&1 && (echo Synced: dev modlist SKSE\Plugins\MTFPulse.dll) || (echo WARNING: dev-modlist DLL sync FAILED ^(file locked? game running?^) - copy manually)
    )
)
popd
exit /b %EC%
