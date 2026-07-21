@echo off
setlocal
cd /d "%~dp0"
echo [1/3] Checking Node.js...
where node >nul 2>nul || (echo Node.js not found. Install Node.js LTS first.& pause & exit /b 1)
echo [2/3] Checking Supabase CLI...
call npx.cmd supabase --version || (echo Supabase CLI failed.& pause & exit /b 1)
echo [3/3] Deploying admin-api...
call npx.cmd supabase functions deploy admin-api
if errorlevel 1 (echo Deployment failed.& pause & exit /b 1)
echo.
echo admin-api deployed successfully.
pause
