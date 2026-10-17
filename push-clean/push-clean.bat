@echo off
rem =====================================================================
rem 🚀 push-clean.bat: Wipe Git History & Force Push a Single Clean Commit
rem Target OS: Windows (CMD / Command Prompt / Double-Clickable)
rem =====================================================================

setlocal enabledelayedexpansion

set "COMMIT_MSG=%~1"
if "%COMMIT_MSG%"=="" (
    for /f "tokens=1-4 delims=/ " %%a in ('date /t') do (
        set "TODAY=%%d-%%b-%%c"
    )
    set "COMMIT_MSG=Clean release: %DATE% %TIME%"
)

set "TARGET_BRANCH=%~2"
if "%TARGET_BRANCH%"=="" set "TARGET_BRANCH=main"

set "REMOTE=%~3"
if "%REMOTE%"=="" set "REMOTE=origin"

rem Go to git root if possible
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do cd /d "%%i"

echo [push-clean] Preparing clean, zero-history push to %REMOTE%/%TARGET_BRANCH%...

rem 1. Create a detached orphan branch
set "TEMP_BRANCH=temp-orphan-%RANDOM%-%TIME:~6,2%"
git checkout --orphan "%TEMP_BRANCH%" >nul 2>&1

rem 2. Stage all files
git add -A

rem 3. Commit
git commit -m "%COMMIT_MSG%"

rem 4. Replace main branch
git branch -D "%TARGET_BRANCH%" >nul 2>&1
git branch -m "%TARGET_BRANCH%"

rem 5. Force push
echo [push-clean] Force-pushing single clean commit to %REMOTE%/%TARGET_BRANCH%...
git push -f "%REMOTE%" "%TARGET_BRANCH%"

echo.
echo [push-clean] Clean push complete! Past git history has been completely purged on GitHub.
echo Only 1 single commit now exists on '%TARGET_BRANCH%'.
endlocal
