@echo off
setlocal
cd /d "%~dp0"
set /p PROJECT_REF=Supabase project ref: 
call npx.cmd supabase login || goto :fail
call npx.cmd supabase link --project-ref %PROJECT_REF% || goto :fail
call npx.cmd supabase functions deploy admin-api || goto :fail
echo Done.
pause
exit /b 0
:fail
echo Failed. Read the error above.
pause
exit /b 1
