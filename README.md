# A2 Racer 4 Fixes

Fixes for the PC version of **A2 Racer 4**:

- the game runs correctly at the resolution you choose, whatever its shape: 16:9, 16:10, 21:9, 32:9, 4:3 or 5:4;
- the crash at race start on modern graphics cards is gone;
- the black edges around objects on current graphics drivers are gone;
- the game no longer needs its CD in the drive.

They consist of three parts:

1. a patched `spel.dat` executable module that makes the 3D game render correctly at your resolution without stretching, and that holds the other game fixes, with a small patch to `menu.exe` for the CD check;
2. an automatic patcher called `A2Racer4Fixes`, for 64-bit and 32-bit Windows and Linux, that patches `spel.dat` and installs the overlay files in the game folder you choose;
3. `overlay*.ini` files that the patcher makes from the game's own files, with the HUD moved to the edges of your screen.

The game uses `spel.dat` as the executable module for the DirectDraw/Direct3D racing portion of the game, even though the file extension is `.dat`.

## Crash fix for modern graphics cards (v1.0.4)

On a current graphics card the original game crashes as soon as a race starts: the screen goes black and the game hangs or closes. The game measures its texture memory by creating textures until the card refuses, and keeps them in a list with room for 1024. Any card with more than about 128 MB of video memory overflows that list. This is why the game used to need dgVoodoo with `VRAM` set to 128 MB or less.

Since v1.0.4 the patcher fixes this. The dgVoodoo `VRAM` setting no longer matters, and the race also starts with plain Wine or D7VK.

- Already using an older version? Run the new patcher on your game folder. Your original 4:3 files stay in the `4x3_backup` folder.
- Game versions 1.00 and 1.01 use an identical `spel.dat`, so both are supported.
- The technical details are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#patch-part-4-texture-memory-crash-fix).

## Black edges around objects (v1.2.0)

Some current graphics drivers show black around trees, signs, HUD digits and other objects with transparent parts. It looks the same with bilinear filtering on or off.

The game draws transparent parts with a color key: a single texture color that should be skipped, and in memory that color is black. The patch gives textures a real alpha bit, removes those pixels with the alpha test and turns the color key off.

Textures now use 5 bits for green instead of 6, on every system. The difference is at most very slight extra banding in smooth color gradients.

The details are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#patch-part-6-transparency-fix).

## No CD needed (v1.2.0)

The game no longer asks for its CD. Install it from the disc once, and after patching you can play with no disc, drive or disc image. The patcher changes `menu.exe` as well as `spel.dat` for this, and keeps the original in the `4x3_backup` folder. The intro video plays from the game folder.

## Recommended setup

The patched `spel.dat` fixes the 3D rendering and the crash. Since v1.0.5 the automatic patcher, `A2Racer4Fixes.exe` (or the 32-bit or Linux version), creates it and installs the patched overlay `.ini` files in one go.
The overlay `.ini` files put the HUD at the edges of your screen.

Using only one part is not recommended.

## Files

### `A2Racer4Fixes` (Windows and Linux, 64-bit and 32-bit)

The automatic patcher. Download the version for your system:

| System | Download |
|---|---|
| Windows 10 or 11, 64-bit | `A2Racer4Fixes.exe` |
| Windows 95, 98, Me, 2000, XP, Vista, 7, 8, 8.1 or 10, 32-bit | `A2Racer4Fixes_32bit.exe` |
| Windows XP, Vista, 7, 8 or 8.1, 64-bit | `A2Racer4Fixes_32bit.exe` |
| Linux, 64-bit | `A2Racer4Fixes_linux_x86_64` |
| Linux, 32-bit | `A2Racer4Fixes_linux_32bit` |

The 64-bit versions do not start on a 32-bit system. All four write exactly the same files.

On Linux, use a Linux version, also when the game runs in Wine. Open a terminal, make the file executable and start it (the 64-bit file works the same way):

```bash
chmod +x A2Racer4Fixes_linux_32bit
```

```bash
./A2Racer4Fixes_linux_32bit
```

Run it from anywhere and enter:

1. the game folder, the folder that contains `spel.dat`. Press Enter if the patcher is already in that folder;
2. your resolution, for example `2560x1440`.

It writes the patched `spel.dat` (including the crash fix) and copies the patched overlay `.ini` files into that folder. Every file it replaces is moved to a `4x3_backup` folder in the game folder; earlier backups are never overwritten. It refuses to patch an unknown `spel.dat` version.

On Windows the patcher needs administrator rights, because the game is normally installed in `C:\Program Files (x86)`, or `C:\Program Files` on 32-bit Windows. Windows asks for them when you start it; click Yes (Allow on Vista). Windows XP does not ask: use an administrator account, or right-click the patcher and choose Run as. Without administrator rights it stops and changes nothing. Windows 95, 98 and Me have no such rights.

The patcher always shows the result. That includes any file it could not write and what that means for your game files. On Windows the window stays open until you press Enter.

Game folders differ per installation, for example:

```text
Windows:             C:\Program Files (x86)\Davilex\A2 Racer 4
Windows 32-bit:      C:\Program Files\Davilex\A2 Racer 4
Lutris:              ~/Games/a2-racer-4/drive_c/Program Files (x86)/Davilex/A2 Racer 4
Default Wine prefix: ~/.wine/drive_c/Program Files (x86)/Davilex/A2 Racer 4
32-bit Wine prefix:  ~/.wine/drive_c/Program Files/Davilex/A2 Racer 4
```

You can type or paste the path, with or without quotes. On Linux, `~` and escaped spaces work too, and most terminals let you drag the folder in.

`overlay7.ini` is only installed when the "Schaduw" extra car update is present, because that update brings its own copy. Install the update first, then run the patcher.

`A2Racer4Fixes.exe` needs Windows 10 or newer, so on older 64-bit Windows use the 32-bit version. On Windows XP that one needs Service Pack 3. Service Pack 2 is untested, and Microsoft documents that programs with a manifest like this one can make an unpatched SP2 restart, so update to SP3 first, or install hotfixes KB921337 and KB943232. It doesn't support game folders with characters outside your system's code page: it gives an error and changes nothing.

The game can only use a resolution your graphics driver offers, so on an old PC choose a mode that is listed in your display settings.

The 32-bit Windows version needs a 486 or newer. The 32-bit Linux version needs a processor with MMX but not SSE2, so it also runs on a Pentium III or Athlon XP, and Linux 3.2 or newer.

### `A2Racer4_DashboardFix`

Ready-made overlay files for 16:9 screens only, for installing by hand. `overlay7.ini` is for the "Schaduw" extra car update. The patcher makes these files itself for any resolution, so normally you don't need the zip. Back up the originals first, then extract the files into the same folder.

## What the `spel.dat` patch changes

The original game is built around 4:3 display modes. Forcing another shape makes the image stretched or zoomed. The patch does the following, all calculated from your resolution. The details and the code behind them are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md).

1. **Display mode:** the game's mode table is set to your resolution.
2. **3D view:** the vertical view stays as it is at 4:3, and the horizontal view is set to `0.75 x width / height`. Pixels stay square at every shape. A wider screen shows more on the sides, and a narrower one such as 5:4 shows slightly less.
3. **HUD proportions:** the game squashes its HUD vertically on anything but 4:3. The patch makes it use the 4:3 shape there too, so the HUD keeps its original proportions and its size relative to the height of the screen.
4. **Texture memory crash fix:** not related to the screen shape, see [Crash fix for modern graphics cards](#crash-fix-for-modern-graphics-cards-v104).
5. **Transparency fix:** see [Black edges around objects](#black-edges-around-objects-v120).
6. **CD check removal:** see [No CD needed](#no-cd-needed-v120).

## What happens to the overlay `.ini` files

The overlay files describe the HUD on a 640x480 canvas. The patcher starts from the game's own files, from `4x3_backup` after an earlier run, so results never build on an earlier patch. It only moves elements attached to a screen edge, by the same amount everywhere:

```text
shift = (0.75 x width / height - 1) x 320 / 0.99, rounded
```

| Shape | Example | Shift |
|---|---|---|
| 5:4 | 1280x1024 | -20 |
| 4:3 | 1600x1200 | 0, the files stay as they are |
| 16:10 | 1680x1050 | +65 |
| 16:9 | 2560x1440 | +108 |
| 21:9 | 3440x1440 | +256 |
| 32:9 | 5120x1440 | +539 |

- **To the right:** the speedometer and everything on it, and the race time, lap and position text.
- **To the left:** the communicator and everything on it, the character portraits and the player portraits.
- **Unchanged:** everything else, including all `Scale` values and all vertical positions. Elements in the middle stay in the middle.

Because older versions of this fix tuned the files by hand, the patcher refuses to build on such a file: it asks you to restore the original from the game CD if it can't find one in `4x3_backup`.

## Installation

1. If you use the "Schaduw" extra car update, install it first.

2. Run the patcher (on Windows, click Yes when it asks for administrator rights), then enter the game folder and your resolution. It writes the patched `spel.dat`, `menu.exe` and overlay `.ini` files, and moves the originals to the `4x3_backup` folder in the game folder.

3. Start the racing part of the game normally.

To install by hand instead: back up `spel.dat` and the overlay `.ini` files, patch `spel.dat` with the steps in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#manual-patching-on-windows), and copy the files from `A2Racer4_DashboardFix.zip` into the game folder.

## Notes

- The 3D view and HUD layout are calculated from the game's own code. Since v1.1.0 they no longer use hand-tuned values.
- v1.1.0 was checked in-game by the author. The files it writes were compared under Wine at shapes from 5:4 to 32:9.
- The 32-bit Windows version is a small C program since v1.1.0, tested under Wine in Windows 98, XP, 7 and 10 mode. v1.1.1 ran fine on real Windows 7 32-bit with a Mobility Radeon HD 5750. Earlier versions of the same code ran on Windows 98 SE in a VM.
- The 32-bit Linux version was tested in earlier releases on a 32-bit Linux 3.18 kernel in QEMU, on emulated processors without SSE2.
- The v1.2.0 transparency fix was checked in-game by the author on a Radeon 760M under Windows 10. The fix and the CD removal also ran through a race start under Wine with software rendering. Both patchers wrote identical files.
- Back up your original files before installing.
- This project does not include original game assets beyond modified configuration/executable patch files.
- Testing before v1.1.1 was done on Fedora Linux 44, running the game through Wine using DXVK and DgVoodoo in tandem.
- The v1.0.4 crash fix was tested on Fedora Linux 44 with plain Wine 11.19, D7VK v2.4, and dgVoodoo 2.80 with `VRAM = 256` (which crashes without the fix). v1.1.1 also ran fine on real Windows 10 64-bit with a Radeon 760M.
