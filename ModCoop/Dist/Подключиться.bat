@echo off
chcp 65001 >nul
rem Подключается к кооп-серверу.
rem Использование: "Подключиться.bat" [IP[:ПОРТ]]   например: "Подключиться.bat" 192.168.1.10
setlocal
cd /d "%~dp0System"
if not exist CT.exe (
	echo Не найден System\CT.exe. Распакуйте архив мода в папку GameData игры.
	pause
	exit /b 1
)

set "LASTFILE=ModCoopLastAddress.txt"
set "LAST=127.0.0.1"
if exist "%LASTFILE%" set /p LAST=<"%LASTFILE%"

set "ADDR=%~1"
if "%ADDR%"=="" set /p "ADDR=IP хоста [Enter = %LAST%]: "
if "%ADDR%"=="" set "ADDR=%LAST%"

>"%LASTFILE%" echo %ADDR%
echo Подключение к %ADDR% ... Лог: System\CoopClient.log
start "" CT.exe "Entry?Menu=ModCoop.CoopJoinMenu" -CoopConnect=%ADDR% -forcelogflush LOG=CoopClient.log %2 %3 %4
