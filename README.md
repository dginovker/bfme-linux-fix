# BFME on Linux

Get [Battle for Middle-earth's Online Battle Arena](https://bfmeladder.com/download) (Ladder mode) working on Linux.

This is a temporary workaround while two Wine fixes go through review:
- **d3d9**: missing MSVC vtable byte-pattern that the Arena's overlay scanner looks for ([WineHQ bug 59708](https://bugs.winehq.org/show_bug.cgi?id=59708), submitted to wine-staging)
- **hnetcfg**: `fw_app_get_Enabled` returning the wrong answer, which makes BFME pop a "Firewall Detected" dialog and abort multiplayer

The script clones Wine source matching your installed Wine version, applies the two patches, builds patched 32-bit `d3d9.dll` and `hnetcfg.dll`, drops them into Wine's system DLL dir, and extracts `dinput8.dll` from the Arena's resources into your BFME install. Builds are cached so subsequent runs are instant.

## Prerequisites

- Linux on **X11** (Wayland breaks Wine's input handling for the Arena window)
- **wine** or **wine-staging** installed
- A **Vulkan-capable GPU** (BFME's caps check fails on llvmpipe)
- ~5 GB free disk
- ~30 minutes for the first run (subsequent runs use the cache)
- `sudo` access (the script needs to install patched DLLs into Wine's system path)

## Install

```bash
# 1. Install AIO Launcher and BFME 1 first
WINEPREFIX=~/.wine-bfme wine ~/Downloads/AllInOneLauncherSetup.exe
# Then in the launcher: install BFME 1, click MULTIPLAYER once
# (the first try will fail — that's expected; it extracts the files we need)

# 2. Install the fix
git clone https://github.com/dginovker/bfme-linux-fix.git
cd bfme-linux-fix
./install.sh
```

The script will prompt for `sudo` to:
- install build deps (`mingw-w64`, `base-devel`/`build-essential`, `flex`, `bison`) if missing
- copy the patched DLLs into Wine's system path (`/usr/lib/wine/i386-windows/`)
- install `dotnet-sdk` if missing (needed to extract `dinput8.dll` from BFME's bundled resources)

By default it targets `~/.wine-bfme`. Use a different prefix with:
```bash
WINEPREFIX=/path/to/prefix ./install.sh
```

## Then run BFME

1. Open the AIO Launcher (or run the Arena directly): `WINEPREFIX=~/.wine-bfme wine "$HOME/.wine-bfme/drive_c/users/$USER/AppData/Roaming/BFME Competetive Arena/BfmeFoundationProject_OnlineArena.exe"`
2. Log in
3. Pick a game (BFME 1) → pick a patch (Patch 2.22) → CONTINUE on the sync dialog
4. The Automated Matchmaking Test should pass within ~30 seconds and drop you into the Arena lobby

## Uninstall

```bash
WINEPREFIX=~/.wine-bfme ./uninstall.sh
```

(Restores the `*.bfme-orig` system DLL backups, removes the prefix `dinput8.dll`, and clears the dinput8 DllOverride.)

## Troubleshooting

**"Your system failed the test — the overlay didn't load in 30 seconds"**
- Confirm `~/.wine-bfme/drive_c/BFME1/dinput8.dll` exists (size ~300 KB)
- Confirm `/usr/lib/wine/i386-windows/d3d9.dll` is the 1.7 MB patched version (vanilla Wine ships ~240 KB)
- Stop `ydotoold` if running — it can interfere with Wine's X11 input

**"BfmeFoundationProject.BfmeClient.dll not found in prefix"**
You haven't launched the Arena yet. Open the AIO Launcher and click MULTIPLAYER once (the test will fail — that's fine), then re-run `./install.sh`.

**Build fails**
Open an issue with the output of `wine --version` and the relevant tail of `/tmp/bfme-build.log` or `/tmp/bfme-configure.log`.

## What this does

1. Detects your Wine version, clones matching upstream source from `gitlab.winehq.org/wine/wine`
2. Applies the two patches in `patches/`
3. Builds 32-bit `d3d9.dll` and `hnetcfg.dll` with `--enable-archs=i386,x86_64` (cached after first run)
4. Backs up `/usr/lib/wine/i386-windows/{d3d9,hnetcfg}.dll` to `*.bfme-orig` and replaces with patched versions (sudo)
5. Locates the Arena's bundled `BfmeFoundationProject.BfmeClient.dll` in your prefix and extracts the embedded `dinput8.dll` resource via `ilspycmd`
6. Drops the extracted `dinput8.dll` into `$WINEPREFIX/drive_c/BFME1/`
7. Sets `dinput8=native,builtin` DllOverride so Wine prefers the BFME-provided `dinput8.dll`

## Why the patched DLLs go into the system path

Wine's PE-built DLLs contain a `"Wine builtin DLL"` magic string. When you put a Wine-built DLL into a prefix's `syswow64/` and set `DllOverrides=native,builtin`, Wine sees the magic and decides to load the system copy from `/usr/lib/wine/i386-windows/` anyway. So patching the prefix isn't enough — the system copy has to be patched too. (If you'd rather avoid `sudo`, use `WINEDLLPATH` to point Wine at a user-owned dir — but that's a less reliable path.)

## License

MIT for the install script. Patches are derivatives of [Wine](https://www.winehq.org/) (LGPL 2.1).
