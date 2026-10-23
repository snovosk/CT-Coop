@echo off
chcp 65001 >nul
rem Запускает на одном компьютере два окна игры: хост и клиент (127.0.0.1), чтобы проверить синхронизацию без второго ПК.
rem Логи: System\CoopHost.log и System\CoopClient.log
setlocal
cd /d "%~dp0System"
if not exist CT.exe (
	echo Не найден System\CT.exe. Распакуйте архив мода в папку GameData игры.
	pause
	exit /b 1
)

set "MAP=%~1"
if "%MAP%"=="" set "MAP=GEO_01A"

echo Запуск хоста (%MAP%) в окне...
start "" CT.exe "%MAP%?game=ModCoop.CoopGame?listen?MaxPlayers=2" -windowed -forcelogflush LOG=CoopHost.log
echo Ждём загрузку хоста 30 секунд...
timeout /t 30 /nobreak >nul
echo Запуск клиента в окне...
start "" CT.exe "Entry?Menu=ModCoop.CoopJoinMenu" -CoopConnect=127.0.0.1 -windowed -forcelogflush LOG=CoopClient.log
echo Готово. Окна можно переключать мышью. Управление получает активное окно.
timeout /t 5 >nul
