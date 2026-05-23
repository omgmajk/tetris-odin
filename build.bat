@echo off
if not exist build mkdir build
odin build . -out:build/tetris.exe
