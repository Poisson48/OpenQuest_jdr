#!/usr/bin/env bash
# Ouvre OpenQuest dans le navigateur par défaut
DIR="$(cd "$(dirname "$0")" && pwd)"
xdg-open "file://${DIR}/index.html" 2>/dev/null || firefox "file://${DIR}/index.html" 2>/dev/null || echo "Ouvre manuellement : ${DIR}/index.html"
