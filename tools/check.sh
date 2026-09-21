#!/bin/sh
# Headless parse/load check for every script; prints only real errors.
G="/c/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
timeout 180 "$G" --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|at: " | grep -v "gdextension\|godotsteam" | head -40
