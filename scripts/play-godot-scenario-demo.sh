#!/usr/bin/env bash
# Lance la partie démo enquête (« Scénario Démo ») en session MJ.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/play-godot.sh" --rendering-method gl_compatibility \
  res://scenes/debug/scenario_demo_boot.tscn "$@"
