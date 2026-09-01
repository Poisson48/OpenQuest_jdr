#!/usr/bin/env bash
# Lance le serveur de développement OpenQuest
set -euo pipefail
cd "$(dirname "$0")/../server"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Fichier .env créé depuis .env.example"
fi

npm run dev
