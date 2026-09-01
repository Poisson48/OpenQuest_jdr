#!/usr/bin/env bash
# Lance le client Godot OpenQuest JDR
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
flatpak run org.godotengine.Godot --path "$ROOT/game" "$@"
