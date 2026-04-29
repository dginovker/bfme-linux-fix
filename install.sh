#!/usr/bin/env bash
# install.sh — patch Wine for BFME Online Battle Arena on Linux
# https://github.com/dginovker/bfme-linux-fix
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bfme-linux-fix"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-bfme}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[34m%s\033[0m\n' "$*"; }
die()   { red "ERROR: $*" >&2; exit 1; }

# --- Sanity checks ---

command -v wine >/dev/null || die "wine not installed. Install wine or wine-staging first (Arch: 'pacman -S wine-staging', Debian/Ubuntu: see https://gitlab.winehq.org/wine/wine/-/wikis/Debian-Ubuntu)."
command -v git  >/dev/null || die "git not installed."

WINE_VERSION_RAW="$(wine --version 2>/dev/null || die 'wine --version failed')"
WINE_VERSION="$(printf '%s' "$WINE_VERSION_RAW" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
[[ -n "$WINE_VERSION" ]] || die "couldn't parse wine version from: $WINE_VERSION_RAW"
blue "Detected Wine $WINE_VERSION ($WINE_VERSION_RAW)"

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
    red "Warning: session type is '${XDG_SESSION_TYPE:-unknown}', not x11."
    red "The Arena window needs X11 — Wayland is known to break Wine input."
fi

if command -v vulkaninfo >/dev/null; then
    vulkaninfo --summary >/dev/null 2>&1 || red "Warning: vulkaninfo failed. BFME's caps check needs a Vulkan-capable GPU; llvmpipe is too slow."
fi

# --- Build deps ---

install_deps() {
    local missing=()
    for cmd in git make gcc i686-w64-mingw32-gcc x86_64-w64-mingw32-gcc flex bison; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        green "Build deps already satisfied."
        return 0
    fi
    blue "Missing build deps: ${missing[*]}. Installing..."
    if command -v pacman >/dev/null; then
        sudo pacman -S --needed --noconfirm git base-devel mingw-w64-gcc flex bison
    elif command -v apt-get >/dev/null; then
        sudo apt-get update
        sudo apt-get install -y git build-essential gcc-mingw-w64-i686 gcc-mingw-w64-x86-64 g++-mingw-w64-i686 g++-mingw-w64-x86-64 flex bison pkg-config
    elif command -v dnf >/dev/null; then
        sudo dnf install -y git make gcc mingw32-gcc mingw64-gcc flex bison pkgconf-pkg-config
    else
        die "Unknown distro. Install manually: git, base-devel/build-essential, mingw-w64 (i686 + x86_64), flex, bison."
    fi
}

# --- Build ---

BUILD_KEY="wine-${WINE_VERSION}-v1"
BUILD_DIR="$CACHE_DIR/$BUILD_KEY"
WINE_SRC="$CACHE_DIR/wine-src-${WINE_VERSION}"

if [[ -f "$BUILD_DIR/d3d9.dll" && -f "$BUILD_DIR/hnetcfg.dll" ]]; then
    green "Cached patched DLLs found at $BUILD_DIR — skipping build."
else
    blue "Building patched DLLs for Wine $WINE_VERSION (~30 min on first run)..."
    install_deps

    if [[ ! -d "$WINE_SRC/.git" ]]; then
        blue "Cloning Wine source (tag wine-${WINE_VERSION})..."
        rm -rf "$WINE_SRC"
        mkdir -p "$CACHE_DIR"
        git clone --depth 1 --branch "wine-${WINE_VERSION}" \
            https://gitlab.winehq.org/wine/wine.git "$WINE_SRC" \
            || die "git clone failed. Is 'wine-${WINE_VERSION}' a valid tag at gitlab.winehq.org/wine/wine? Try a Wine version that has a matching upstream tag."
    fi

    cd "$WINE_SRC"
    git reset --hard HEAD
    git clean -xdf >/dev/null

    blue "Applying patches..."
    git apply "$REPO_DIR/patches/0001-d3d9-byte-pattern.patch"      || die "d3d9 patch failed to apply"
    git apply "$REPO_DIR/patches/0002-hnetcfg-fw-app-enabled.patch" || die "hnetcfg patch failed to apply"

    blue "Configuring..."
    ./configure --enable-archs=i386,x86_64 >/tmp/bfme-configure.log 2>&1 \
        || { tail -30 /tmp/bfme-configure.log >&2; die "configure failed — see /tmp/bfme-configure.log"; }

    blue "Building d3d9 and hnetcfg (this is the slow part)..."
    make -j"$(nproc)" dlls/d3d9/i386-windows/d3d9.dll dlls/hnetcfg/i386-windows/hnetcfg.dll >/tmp/bfme-build.log 2>&1 \
        || { tail -50 /tmp/bfme-build.log >&2; die "make failed — see /tmp/bfme-build.log"; }

    [[ -f dlls/d3d9/i386-windows/d3d9.dll       ]] || die "d3d9.dll i386 not produced — check /tmp/bfme-build.log"
    [[ -f dlls/hnetcfg/i386-windows/hnetcfg.dll ]] || die "hnetcfg.dll i386 not produced — check /tmp/bfme-build.log"

    mkdir -p "$BUILD_DIR"
    cp dlls/d3d9/i386-windows/d3d9.dll       "$BUILD_DIR/d3d9.dll"
    cp dlls/hnetcfg/i386-windows/hnetcfg.dll "$BUILD_DIR/hnetcfg.dll"
    green "Built and cached at $BUILD_DIR"
fi

# --- Install into prefix ---

if [[ ! -d "$WINEPREFIX" ]]; then
    blue "Initializing Wine prefix at $WINEPREFIX..."
    WINEPREFIX="$WINEPREFIX" wineboot --init >/dev/null 2>&1 || die "wineboot --init failed"
fi

SYSWOW64="$WINEPREFIX/drive_c/windows/syswow64"
[[ -d "$SYSWOW64" ]] || die "syswow64 not found at $SYSWOW64 — is this a 64-bit prefix? (32-bit prefixes don't have syswow64; remove the prefix and rerun, or use a fresh location.)"

blue "Installing patched DLLs into $SYSWOW64..."
for dll in d3d9.dll hnetcfg.dll; do
    if [[ -f "$SYSWOW64/$dll" && ! -f "$SYSWOW64/$dll.bfme-orig" ]]; then
        cp "$SYSWOW64/$dll" "$SYSWOW64/$dll.bfme-orig"
    fi
    cp "$BUILD_DIR/$dll" "$SYSWOW64/$dll"
done

blue "Setting DLL overrides..."
for dll in d3d9 hnetcfg dinput8; do
    WINEPREFIX="$WINEPREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" \
        /v "$dll" /d "native,builtin" /f >/dev/null 2>&1
done

green ""
green "Done. Wine prefix is ready at $WINEPREFIX."
echo
echo "Next steps:"
echo "  1. Download AllInOneLauncherSetup.exe from https://bfmeladder.com/download"
echo "  2. WINEPREFIX=$WINEPREFIX wine ~/Downloads/AllInOneLauncherSetup.exe"
echo "  3. Open the launcher, install BFME 1, then click MULTIPLAYER → log in → Patch 2.22 → CONTINUE"
