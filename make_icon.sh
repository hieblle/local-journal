#!/bin/bash
#
# Erzeugt alle benötigten macOS-App-Icon-Größen aus EINEM quadratischen
# Quellbild (idealerweise 1024x1024 PNG) und legt sie im AppIcon-Set ab.
# Nutzt `sips` (auf jedem Mac vorinstalliert) – kein Xcode nötig.
#
# Verwendung:
#   ./make_icon.sh /pfad/zu/deinem-icon.png
#
set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" || ! -f "$SRC" ]]; then
  echo "Verwendung: $0 /pfad/zu/deinem-icon.png  (quadratisch, am besten 1024x1024)"
  exit 1
fi

DEST="$(cd "$(dirname "$0")" && pwd)/LocalJournal/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$DEST"

for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$SRC" --out "$DEST/icon_${size}.png" >/dev/null
done

# Falls von einem früheren Versuch ein Einzelbild herumliegt: aufräumen.
rm -f "$DEST/AppIcon.png"

echo "✅ Icon-Größen erzeugt in:"
echo "   $DEST"
echo "   Jetzt in Xcode neu bauen (⌘B / ⌘R)."
