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

if [[ "${XDG_SESSION_TYPE:-}" != "x11" && "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
    red "Warning: unrecognized session type '${XDG_SESSION_TYPE:-unknown}'. The Arena needs an X11 or Wayland (with Xwayland) desktop."
fi

if command -v vulkaninfo >/dev/null; then
    vulkaninfo --summary >/dev/null 2>&1 || red "Warning: vulkaninfo failed. BFME's caps check needs a Vulkan-capable GPU; llvmpipe is too slow."
fi

# --- Locate Wine's PE DLL dir (system path) ---

WINE_PE_DIR=""
for candidate in /usr/lib/wine/i386-windows /usr/lib32/wine/i386-windows /opt/wine-staging/lib/wine/i386-windows /usr/lib/x86_64-linux-gnu/wine/i386-windows; do
    if [[ -d "$candidate" && -f "$candidate/d3d9.dll" ]]; then
        WINE_PE_DIR="$candidate"
        break
    fi
done
[[ -n "$WINE_PE_DIR" ]] || die "couldn't find Wine's i386-windows DLL dir. Tried: /usr/lib/wine/i386-windows, /usr/lib32/wine/i386-windows, /opt/wine-staging/lib/wine/i386-windows, /usr/lib/x86_64-linux-gnu/wine/i386-windows. Set WINE_PE_DIR= in env to override."
blue "Wine PE DLL dir: $WINE_PE_DIR"

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

# --- Build patched DLLs (cached by Wine version) ---

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

# --- Install patched DLLs to system path (sudo) ---
# Wine's loader detects "Wine builtin DLL" magic in our patched files and falls
# back to the system path even when DllOverride says native,builtin. So we must
# replace the system DLLs themselves. Backups go to <dll>.bfme-orig.

blue "Installing patched DLLs to $WINE_PE_DIR (will prompt for sudo)..."
for dll in d3d9.dll hnetcfg.dll; do
    if [[ -f "$WINE_PE_DIR/$dll" && ! -f "$WINE_PE_DIR/$dll.bfme-orig" ]]; then
        sudo cp "$WINE_PE_DIR/$dll" "$WINE_PE_DIR/$dll.bfme-orig"
    fi
    sudo cp "$BUILD_DIR/$dll" "$WINE_PE_DIR/$dll"
done

# --- Initialize prefix if missing ---

if [[ ! -d "$WINEPREFIX" ]]; then
    blue "Initializing Wine prefix at $WINEPREFIX..."
    WINEPREFIX="$WINEPREFIX" wineboot --init >/dev/null 2>&1 || die "wineboot --init failed"
fi

# --- Extract dinput8.dll from BfmeClient.dll resources, drop into C:\BFME1\ ---
# The Arena's AddApiDllToGameDirectory is supposed to do this on launch, but
# silently fails on Wine. Without dinput8.dll in BFME1, no overlay scanner runs
# at all and the matchmaking test will fail with "overlay didn't load".

BFME1_DIR="$WINEPREFIX/drive_c/BFME1"
if [[ ! -d "$BFME1_DIR" ]]; then
    red "C:\\BFME1 doesn't exist in this prefix yet."
    red "Install BFME 1 via the AIO Launcher (see https://bfmeladder.com/download), then re-run this script."
    exit 0
fi

BFME_CLIENT_DLL="$(find "$WINEPREFIX/drive_c/users" -name "BfmeFoundationProject.BfmeClient.dll" 2>/dev/null | head -1)"
if [[ -z "$BFME_CLIENT_DLL" ]]; then
    red "BfmeFoundationProject.BfmeClient.dll not found in prefix."
    red "Open the AIO Launcher and click MULTIPLAYER once (or run the Arena standalone) so it extracts."
    red "Then re-run this script."
    exit 0
fi
blue "Found $BFME_CLIENT_DLL"

# Need ilspycmd to extract the embedded dinput8.dll resource
export PATH="$PATH:$HOME/.dotnet/tools"
if ! command -v ilspycmd >/dev/null; then
    if ! command -v dotnet >/dev/null; then
        blue "Installing dotnet SDK..."
        if command -v pacman >/dev/null; then
            sudo pacman -S --needed --noconfirm dotnet-sdk
        elif command -v apt-get >/dev/null; then
            sudo apt-get install -y dotnet-sdk-9.0 || sudo apt-get install -y dotnet-sdk-8.0
        elif command -v dnf >/dev/null; then
            sudo dnf install -y dotnet-sdk-9.0 || sudo dnf install -y dotnet-sdk-8.0
        else
            die "dotnet not installed and unknown distro. Install dotnet-sdk manually."
        fi
    fi
    blue "Installing ilspycmd..."
    dotnet tool install --global ICSharpCode.Decompiler.Console >/dev/null 2>&1 || die "dotnet tool install ilspycmd failed"
fi

EXTRACT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT
blue "Extracting dinput8.dll from BfmeClient resources..."
ilspycmd -p "$BFME_CLIENT_DLL" -o "$EXTRACT_DIR" >/dev/null 2>&1 || die "ilspycmd extraction failed"
DINPUT8_RESOURCE="$(find "$EXTRACT_DIR" -name "*Resources.dinput8.dll" 2>/dev/null | head -1)"
[[ -n "$DINPUT8_RESOURCE" ]] || die "Resources.dinput8.dll not found in extracted output"
cp "$DINPUT8_RESOURCE" "$BFME1_DIR/dinput8.dll"
green "Installed $BFME1_DIR/dinput8.dll"

# --- Set DllOverride for dinput8 in this prefix ---
blue "Setting dinput8 override (native,builtin)..."
WINEPREFIX="$WINEPREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" \
    /v dinput8 /d "native,builtin" /f >/dev/null 2>&1

green ""
green "Done. Wine $WINE_VERSION patched, prefix $WINEPREFIX ready."
echo
echo "Next: open the AIO Launcher (Multiplayer) or the Arena, log in,"
echo "pick a patch (e.g. Patch 2.22), CONTINUE through the sync dialog."
echo "The Automated Matchmaking Test should pass and drop you into the lobby."
