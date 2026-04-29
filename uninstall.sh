#!/usr/bin/env bash
# uninstall.sh — revert install.sh's changes to the Wine prefix
set -euo pipefail

WINEPREFIX="${WINEPREFIX:-$HOME/.wine-bfme}"
SYSWOW64="$WINEPREFIX/drive_c/windows/syswow64"

[[ -d "$SYSWOW64" ]] || { echo "no syswow64 at $SYSWOW64; nothing to do"; exit 0; }

for dll in d3d9.dll hnetcfg.dll; do
    if [[ -f "$SYSWOW64/$dll.bfme-orig" ]]; then
        mv "$SYSWOW64/$dll.bfme-orig" "$SYSWOW64/$dll"
        echo "Restored $SYSWOW64/$dll"
    fi
done

for dll in d3d9 hnetcfg dinput8; do
    WINEPREFIX="$WINEPREFIX" wine reg delete "HKCU\\Software\\Wine\\DllOverrides" /v "$dll" /f >/dev/null 2>&1 || true
done

echo "Done. Build cache at \${XDG_CACHE_HOME:-\$HOME/.cache}/bfme-linux-fix/ is untouched — delete it manually if you want to free disk."
