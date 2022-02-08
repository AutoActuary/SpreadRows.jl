@echo off
setlocal
set "package=SpreadRows"
cd "%~dp0"
"%~dp0..\..\julia\julia.exe" -e "using Pkg; pkg\"dev .\"; using %package%; pth=dirname(pathof(%package%)); println(pth); cd(pth); using LocalRegistry; using %package%; register(%package%)"
if /i "%comspec% /c %~0 " equ "%cmdcmdline:"=%" pause