#!/bin/sh
# Copia la lógica autoritativa y el manifest de cada juego (games/<id>/<id>/) a server/games/<id>/,
# que es donde el servidor la busca (GameRegistry.logic_path). La carpeta destino es generada.
# Uso: tools/sync_server_logic.sh [carpeta_games] [carpeta_destino]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAMES="${1:-$ROOT/games}"
OUT="${2:-$ROOT/arcade-stars-horizons-edition/server/games}"
rm -rf "$OUT"
mkdir -p "$OUT"
for dir in "$GAMES"/*/; do
  id="$(basename "$dir")"
  src="$dir$id/${id}_logic.gd"
  if [ ! -f "$src" ]; then
    echo "skip $id (no ${id}_logic.gd)"
    continue
  fi
  mkdir -p "$OUT/$id"
  cp "$src" "$OUT/$id/"
  cp "$dir$id/manifest.json" "$OUT/$id/"
  echo "synced $id"
done
