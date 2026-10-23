@echo off
chcp 65001 >nul
rem Запускает кооп-сервер (хост играет сам и одновременно является сервером).
rem Использование: "Создать сервер.bat" [УРОВЕНЬ] [ИГРОКОВ]   например: "Создать сервер.bat" GEO_01A 2
setlocal
cd /d "%~dp0System"
if not exist CT.exe (
	echo Не найден System\CT.exe. Распакуйте архив мода в папку GameData игры.
	pause
	exit /b 1
)

set "MAP=%~1"
set "PLAYERS=%~2"

if "%MAP%"=="" (
	echo Уровни кампании: GEO_01A, GEO_01B, GEO_01C, GEO_03A ... RAS_01A ... YYY_06D
	echo Полный список проверенных уровней - в README.md
	set /p "MAP=Уровень [Enter = GEO_01A]: "
)
if "%MAP%"=="" set "MAP=GEO_01A"
if "%PLAYERS%"=="" set /p "PLAYERS=Максимум игроков 2-4 [Enter = 4]: "
if "%PLAYERS%"=="" set "PLAYERS=4"

echo Запуск кооп-сервера: %MAP%, до %PLAYERS% игроков, порт 7777 UDP. Лог: System\CoopHost.log
echo Если друзья не могут подключиться - запустите "Разрешить в брандмауэре.bat" на этом ПК.
echo Другие игроки подключаются по вашему IP (LAN или VPN) через "Подключиться.bat" или меню MULTIPLAYER - CO-OP: JOIN BY IP.
start "" CT.exe "%MAP%?game=ModCoop.CoopGame?listen?MaxPlayers=%PLAYERS%" -forcelogflush LOG=CoopHost.log %3 %4 %5
