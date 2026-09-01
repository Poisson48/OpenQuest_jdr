#!/usr/bin/env bash
# Setup initial — à lancer après le clone (les deux devs)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> OpenQuest JDR — setup"
echo ""

# Node / serveur
if ! command -v node &>/dev/null; then
  echo "❌ Node.js introuvable. Installe Node 20+ : https://nodejs.org"
  exit 1
fi
echo "✓ Node $(node --version)"

cd server
if [ ! -f .env ]; then
  cp .env.example .env
  echo "✓ server/.env créé"
fi
npm install
npm run typecheck
echo "✓ Dépendances serveur OK"
cd "$ROOT"

# Godot (optionnel)
if command -v flatpak &>/dev/null && flatpak list 2>/dev/null | grep -q godotengine.Godot; then
  echo "✓ Godot (Flatpak) détecté : $(flatpak run org.godotengine.Godot --version 2>/dev/null || echo '?')"
elif command -v godot4 &>/dev/null; then
  echo "✓ godot4 détecté"
elif command -v godot &>/dev/null; then
  echo "✓ godot détecté"
else
  echo "⚠ Godot non trouvé — installe-le pour le client :"
  echo "  flatpak install flathub org.godotengine.Godot"
fi

# Dossier POC (référence future)
mkdir -p poc

# Git hooks (optionnel, désactivé par défaut)
# git config core.hooksPath .githooks 2>/dev/null || true

echo ""
echo "==> Setup terminé"
echo ""
echo "Prochaines étapes :"
echo "  1. git config user.name / user.email  (ton identité)"
echo "  2. cd server && npm run dev           (terminal 1)"
echo "  3. Ouvrir game/ dans Godot 4          (terminal 2)"
echo ""
echo "Workflow : voir docs/COLLABORATION.md"
