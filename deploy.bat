@echo off
cd /d "%~dp0"
echo Updating ServiceStore...
git add -A
git diff --cached --quiet && (echo No changes to upload.& pause & exit /b 0)
git commit -m "Update ServiceStore"
git pull origin main --rebase
if errorlevel 1 (echo Pull conflict. Stop and send screenshot.& pause&exit /b 1)
git push origin main
if errorlevel 1 (echo Push failed. Send screenshot.& pause&exit /b 1)
echo Done. Cloudflare will deploy automatically.
pause
