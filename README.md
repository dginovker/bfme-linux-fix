# BFME on Linux

Get [Battle for Middle-earth's Online Battle Arena](https://bfmeladder.com/download) (Ladder mode) working on Linux.

This is a temporary workaround while two Wine fixes go through review:
- **d3d9**: missing MSVC vtable byte-pattern that the Arena's overlay scanner looks for ([WineHQ bug 59708](https://bugs.winehq.org/show_bug.cgi?id=59708), submitted to wine-staging)
- **hnetcfg**: `fw_app_get_Enabled` returning the wrong answer, which makes BFME pop a "Firewall Detected" dialog and abort multiplayer

The script clones Wine source matching your installed Wine version, applies the two patches, builds patched 32-bit `d3d9.dll` and `hnetcfg.dll`, and drops them into your Wine prefix. Builds are cached so subsequent runs are instant.

## Prerequisites

- Linux on **X11** (Wayland breaks Wine's input handling for the Arena window)
- **wine** or **wine-staging** installed
- A **Vulkan-capable GPU** (BFME's caps check fails on llvmpipe)
- ~5 GB free disk
- ~30 minutes for the first run (subsequent runs use the cache)

## Install

```bash
git clone https://github.com/dginovker/bfme-linux-fix.git
cd bfme-linux-fix
./install.sh
```

The script will prompt for `sudo` to install build deps (`mingw-w64`, `base-devel`/`build-essential`, `flex`, `bison`).

By default it targets `~/.wine-bfme`. Use a different prefix with:
```bash
WINEPREFIX=/path/to/prefix ./install.sh
```

## Then run BFME

1. Download [AllInOneLauncher](https://bfmeladder.com/download)
2. Install it: `WINEPREFIX=~/.wine-bfme wine ~/Downloads/AllInOneLauncherSetup.exe`
3. Open the launcher, install BFME 1
4. Click MULTIPLAYER → log in → pick Patch 2.22 → CONTINUE
5. The Automated Matchmaking Test should pass and drop you into the Arena lobby

## Uninstall

```bash
WINEPREFIX=~/.wine-bfme ./uninstall.sh
```

(Restores the `*.bfme-orig` DLL backups and removes the DLL overrides.)

## Troubleshooting

**"Your system failed the test — the overlay didn't load in 30 seconds"**
The Arena writes `dinput8.dll` into `C:\BFME1\` on each launch but sometimes silently fails. Try launching the Arena standalone:
```bash
WINEPREFIX=~/.wine-bfme wine "$HOME/.wine-bfme/drive_c/users/$USER/AppData/Roaming/BFME Competetive Arena/BfmeFoundationProject_OnlineArena.exe"
```

**Synthetic clicks don't reach the Arena window**
Stop `ydotoold` if it's running. Wine on X11 takes regular X input fine.

**Build fails**
Open an issue with the output of `wine --version` and the relevant tail of `/tmp/bfme-build.log` or `/tmp/bfme-configure.log`.

## What this does

1. Detects your Wine version and clones matching upstream source from `gitlab.winehq.org/wine/wine`
2. Applies the two patches in `patches/`
3. Builds 32-bit `d3d9.dll` and `hnetcfg.dll` with `--enable-archs=i386,x86_64`
4. Backs up your prefix's existing DLLs to `*.bfme-orig`
5. Copies the patched DLLs into `$WINEPREFIX/drive_c/windows/syswow64/`
6. Sets DLL overrides for `d3d9`, `hnetcfg`, and `dinput8` to `native,builtin`

## License

MIT for the install script. Patches are derivatives of [Wine](https://www.winehq.org/) (LGPL 2.1).
