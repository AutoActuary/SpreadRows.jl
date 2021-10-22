@echo off
setlocal
set "package=SpreadRows"
cd "%~dp0"
git add --all
git commit
git push origin main
C:\Users\simon\Juliawin\julia.exe "using Pkg; pkg\"dev .\"; using %package%; pth=dirname(pathof(%package%)); cd(pth); run(`git pull`); using LocalRegistry; using %package%; register(%package%)"