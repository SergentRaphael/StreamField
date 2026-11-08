@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo  ===  Installation de StreamField  ===
echo.
where flutter >nul 2>nul || (echo Flutter n'est pas installe. Voir le fichier README.md & pause & exit /b 1)
call flutter pub get || goto :error
call dart run tool/setup.dart || goto :error
call flutter test || goto :error
echo.
echo  Tout est pret ! Lancement de StreamField sur ce PC...
call flutter run -d windows
exit /b 0
:error
echo.
echo  Une erreur est survenue : copie le message ci-dessus et envoie-le moi.
pause
exit /b 1
