#!/bin/zsh
# Startet die App im gebooteten Simulator mit Demo-Daten und macht einen Screenshot.
# Nutzung: ./shot.sh <ausgabe.png> [weitere Startparameter …]
out=$1; shift
xcrun simctl terminate booted de.beispiel.filmprototyp 2>/dev/null
xcrun simctl launch booted de.beispiel.filmprototyp -seedDemo YES "$@" >/dev/null
sleep ${WAIT:-4}
xcrun simctl io booted screenshot "$out" >/dev/null 2>&1
