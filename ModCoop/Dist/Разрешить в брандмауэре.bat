@echo off
chcp 65001 >nul
rem Разрешает CT.exe принимать подключения (UDP) во всех сетях, включая ZeroTier/Radmin/Hamachi.
rem Нужен на ПК ХОСТА (клиенту обычно не нужен, но не помешает). Запрашивает права администратора.
setlocal
set "BATFILE=%~f0"
net session >nul 2>&1
if errorlevel 1 (
	echo Нужны права администратора, сейчас Windows спросит разрешение...
	powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath $env:ComSpec -ArgumentList '/c', ('\"' + $env:BATFILE + '\"')"
	exit /b
)

set "EXE=%~dp0System\CT.exe"
if not exist "%EXE%" (
	echo Не найден %EXE%. Батник должен лежать в папке GameData рядом с папкой System.
	pause
	exit /b 1
)

echo Добавляю правила брандмауэра для:
echo   %EXE%
netsh advfirewall firewall delete rule name="SWRC Coop (CT.exe)" >nul 2>&1
netsh advfirewall firewall add rule name="SWRC Coop (CT.exe)" dir=in action=allow program="%EXE%" protocol=udp profile=any enable=yes
netsh advfirewall firewall add rule name="SWRC Coop (CT.exe)" dir=out action=allow program="%EXE%" protocol=udp profile=any enable=yes
echo.
echo Готово. Правило "SWRC Coop (CT.exe)" можно удалить в "Брандмауэр Защитника Windows - Дополнительные параметры".
pause
