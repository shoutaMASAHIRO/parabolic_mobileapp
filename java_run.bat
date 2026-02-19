@echo off
pushd "%~dp0backend"
if not exist "out" mkdir out
javac src\Main.java -d out && java -cp out Main %*
popd
