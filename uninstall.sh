#!/usr/bin/env bash
# uninstall.sh — revert install.sh's changes
set -euo pipefail

WINEPREFIX="${WINEPREFIX:-$HOME/.wine-bfme}"

# Locate Wine's PE DLL dir (matching install.sh)
WINE_PE_DIR=""
for candidate in /usr/lib/wine/i386-windows /usr/lib32/wine/i386-windows /opt/wine-staging/lib/wine/i386-windows /usr/lib/x86_64-linux-gnu/wine/i386-windows; do
    if [[ -d "$candidate" ]]; then WINE_PE_DIR="$candidate"; break; fi
done

if [[ -n "$WINE_PE_DIR" ]]; then
    for dll in d3d9.dll hnetcfg.dll; do
        if [[ -f "$WINE_PE_DIR/$dll.bfme-orig" ]]; then
            sudo mv "$WINE_PE_DIR/$dll.bfme-orig" "$WINE_PE_DIR/$dll"
            echo "Restored $WINE_PE_DIR/$dll"
        fi
    done
fi

if [[ -d "$WINEPREFIX" ]]; then
    rm -f "$WINEPREFIX/drive_c/BFME1/dinput8.dll"
    WINEPREFIX="$WINEPREFIX" wine reg delete "HKCU\\Software\\Wine\\DllOverrides" /v dinput8 /f >/dev/null 2>&1 || true
fi

echo "Done. Build cache at \${XDG_CACHE_HOME:-\$HOME/.cache}/bfme-linux-fix/ is untouched — delete it manually if you want to free disk."
