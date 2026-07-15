@echo off
set NODE_PATH=%~dp0node_modules
set CHROME_PATH=%CHROME_PATH%
node "%~dp0scrape_linkedin.js" %*
