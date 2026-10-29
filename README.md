# A2 Racer 4 Widescreen Fix + Modern GPU Crash Fix

This package contains a native 16:9 widescreen fix for the PC version of **A2 Racer 4**.

The fix has three parts:

1. a patched `spel.dat` executable module that makes the 3D game render correctly at a 16:9 resolution without horizontal stretching, and that fixes the crash at race start on modern graphics cards;
2. An automatic patcher called `A2Racer4WidescreenPatcher.exe` that patches `spel.dat` and installs the overlay files in the game folder you choose.
3. patched `overlay*.ini` files that reposition and unstretch the in-game HUD for a 16:9 layout.

The game uses `spel.dat` as the executable module for the DirectDraw/Direct3D racing portion of the game, even though the file extension is `.dat`.

## Crash fix for modern graphics cards (v1.0.4)

On a current graphics card the original game crashes as soon as a race starts: the screen goes black and the game hangs or closes. The game measures its texture memory by creating textures until the card refuses, and keeps them in a list with room for 1024. Any card with more than about 128 MB of video memory overflows that list. This is why the game used to need dgVoodoo with `VRAM` set to 128 MB or less.

Since v1.0.4 the patcher fixes this. The dgVoodoo `VRAM` setting no longer matters, and the race also starts with plain Wine or D7VK.

- Already using an older version? Run the new patcher on your game folder. Your original 4:3 files stay in the `4x3_backup` folder.
- Game versions 1.00 and 1.01 use an identical `spel.dat`, so both are supported.
- The technical details are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#patch-part-4-texture-memory-crash-fix).

## Recommended setup

The patched `spel.dat` fixes the 3D widescreen rendering. Since v1.0.5 the automatic patcher, `A2Racer4WidescreenPatcher.exe` (or the Linux version), creates it and installs the patched overlay `.ini` files in one go.
The patched overlay `.ini` files fix the HUD layout.

Using only one part of the fix is not recommended.

## Files

### `A2Racer4WidescreenPatcher.exe` / `A2Racer4WidescreenPatcher_linux_x86_64`

The automatic patcher. Run it from anywhere and enter:

1. the game folder, the folder that contains `spel.dat`. Press Enter if the patcher is already in that folder;
2. your 16:9 resolution, for example `2560x1440`.

It writes the patched `spel.dat` (including the crash fix) and copies the patched overlay `.ini` files into that folder. Every file it replaces is moved to a `4x3_backup` folder in the game folder; earlier backups are never overwritten. It refuses to patch an unknown `spel.dat` version.

Game folders differ per installation, for example:

```text
Windows:            C:\Program Files (x86)\Davilex\A2 Racer 4
Lutris:             ~/Games/a2-racer-4/drive_c/Program Files (x86)/Davilex/A2 Racer 4
Default Wine prefix: ~/.wine/drive_c/Program Files (x86)/Davilex/A2 Racer 4
```

You can type or paste the path, or drag the folder into the window. Quotes, escaped spaces and `~` are fine.

`overlay7.ini` is only installed when the "Schaduw" extra car update is present, because that update brings its own copy. Install the update first, then run the patcher.

The Windows version needs Windows 10 or newer. On Windows 7, patch `spel.dat` by hand with the steps in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#manual-patching-on-windows), or run the patcher on another PC and copy the patched `spel.dat` over.

### `A2Racer4_DashboardFix`

This contains the patched overlay files:

```text
overlay0.ini
overlay1.ini
overlay2.ini
overlay3.ini
overlay4.ini
overlay5.ini
overlay6.ini
overlay7.ini
```

`overlay7.ini` is for the "Schaduw" extra car update. Install that update first, then copy the overlay files.

Since v1.0.5 the patcher installs these files for you. The zip is for installing them by hand, for example on Windows 7.

Extract these files into the same folder where the original overlay `.ini` files are located. Back up the originals first.

## What the `spel.dat` patch changes

The original game is built around 4:3 display modes such as 640×480 and 800×600. Simply forcing a 16:9 resolution makes the 3D image either stretched or vertically zoomed.

The patched `spel.dat` fixes this in two steps:

### 1. Native 16:9 display mode

The internal display-mode table was changed so the game can open a **16 by 9** mode instead of falling back to old 4:3 modes.

For the 2560×1440 build, for example, the relevant mode-table entries are redirected to:

```text
Width  = 2560
Height = 1440
```

### 2. Hor+ 3D projection correction

The 3D viewport/projection math was adjusted so the game keeps the correct proportions at 16:9.

The important part is that the patch does **not** just stretch the old 4:3 image. Instead, it preserves the vertical framing and expands the visible horizontal view. This is the desired **Hor+** widescreen behavior:

```text
Original 4:3:   normal vertical view, limited horizontal view
Patched 16:9:   same vertical view, more horizontal view
```

For the 2560×1440 patch, the aspect/projection calculation was adjusted around a 4:3 reference width of **1920** for a 1440-pixel-tall frame:

```text
1440 × 4 / 3 = 1920
```

This keeps the original 4:3 vertical framing while allowing the wider 2560-pixel output to show extra image on the sides.

An additional horizontal tuning factor was applied after testing. Resulting in a proper 16:9 image, no visible 3D stretching, and acceptable HUD behavior when combined with the patched overlay files.

### 3. Texture memory crash fix

Not widescreen related: the game's texture memory test is skipped, and the game is told it has 64 MB. The game keeps sizing its texture cache from its own `custom_texture_memory` setting (4–8 MB by default, well below 64 MB); it just no longer crashes on cards with more than 128 MB. See [Crash fix for modern graphics cards](#crash-fix-for-modern-graphics-cards-v104).

## What the overlay `.ini` files do

The overlay `.ini` files control the HUD layout and many 2D on-screen elements. These include:

- speedometer
- turbo dial
- damage meter
- euro counter
- communicator panel
- character portrait popups
- race timer
- lap / round text
- position text
- direction arrows
- finish text styling

The original overlay files are laid out for a **640×480 4:3 virtual canvas**. When the game is rendered in 16:9, those HUD elements can become stretched, misplaced, or too close to the old 4:3 center area.

The patched overlay files keep the HUD usable and visually correct at 16:9.

## Main overlay changes compared with the original game files

### HUD horizontal unstretch

Most HUD image elements received an X-scale correction such as:

```ini
Scale = 0.75,1,1
```

This compensates for the 4:3-to-16:9 horizontal stretch while preserving the vertical size.

Text elements that had their own scale values were adjusted similarly, for example:

```ini
Scale = 0.525,0.7,0.7
Scale = 0.6,0.8,0.8
Scale = 0.45,0.6,0.6
```

The goal was to make text and sprites look proportionally correct rather than wide or flattened.

### Speedometer moved and corrected

The speedometer was moved toward the lower-right 16:9 screen edge and its internal parts were realigned.

Changed speedometer-related elements include:

```text
OVL_SPEEDOMETER_BODY
OVL_SPEEDOMETER_GLAS
OVL_SPEEDOMETER_STRIPES
OVL_SPEEDOMETER_HLTH
OVL_SPEEDOMETER_HLTH_BK
OVL_SPEEDOMETER_DIAL
OVL_SPEEDOMETER_DOP
OVL_SPEEDOMETER_RED_LED
OVL_SPEEDOMETER_RED_LUD
OVL_SPEEDOMETER_RED_GLOW
OVL_SPEEDOMETER_GRN_LED
OVL_SPEEDOMETER_GRN_LUD
OVL_SPEEDOMETER_GRN_GLOW
OVL_SPEEDOMETER_TURBODIAL
OVL_SPEEDOMETER_TURBODOP
STRING_DAMAGE_TXT
STRING_EURO_MONEY
STRING_EURO_SIGN
```

The speedometer dials, damage text, euro counter, and green/red indicator lights were individually tuned so they line up with the speedometer graphic.

### Communicator moved and corrected

The communicator panel was moved toward the lower-left 16:9 screen edge and its internal elements were aligned together.

Changed communicator-related elements include:

```text
OVL_COMMUNICATOR_BODY
OVL_COMMUNICATOR_GLAS1
OVL_COMMUNICATOR_GLAS2
OVL_COMMUNICATOR_HLTH
OVL_COMMUNICATOR_HLTH_BK
OVL_COMMUNICATOR_RED_LED
OVL_COMMUNICATOR_RED_LUD
OVL_COMMUNICATOR_RED_GLOW
STRING_0_COMMUNICATOR
STRING_1_COMMUNICATOR
STRING_2_COMMUNICATOR
STRING_3_COMMUNICATOR
```

The character portrait popup elements used by the communicator were also adjusted so they line up with the communicator panel.

### Player position portraits moved

The `[Portraits]` composite was moved to fit the 16:9 layout better.

The final tuned value is:

```ini
[Portraits]
Position = -90,-59,0
```

This places the player-position portrait stack near the upper-left edge without falling off-screen.

### Top-right race text moved

The race timer, current lap/round, and current position strings were moved toward the upper-right 16:9 edge.

Changed elements include:

```text
STRING_RACE_TIME_VALUE
STRING_CUR_LAP
STRING_CUR_POS
STRING_COUNTDOWN_TIMER
```

### Direction and turnaround indicators adjusted

Direction arrows and the turnaround indicator were moved and scaled for the wider output.

Changed elements include:

```text
OVL_DIRECTION_GOLEFT
OVL_DIRECTION_GORIGHT
OVL_DIRECTION_GOBOTH
OVL_DIRECTION_GOZIGZAG
OVL_TURNAROUND_FRAME
```

These use:

```ini
Position = 320,-30,0
Scale    = 1,1.25,1.25
```

### Finish text styling

The finish-position strings and finish prompt were adjusted in the `.ini` files.

Changed elements include:

```text
STRING_FINISH_POS_1
STRING_FINISH_POS_2
STRING_FINISH_POS_3
STRING_FINISH_POS_4
STRING_FINISH_POS_5
STRING_FINISH_TEXT
```

Important note: testing showed that the **scale/color** of the finish-position strings is read from the `.ini` files, but their **position appears to be overwritten by the game at runtime**. So the `.ini` position values for `STRING_FINISH_POS_*` may not affect the final in-game placement.

## Known limitation

The finish-position text shown at the end of a race appears to have its position controlled by executable code rather than only by the overlay `.ini` files.

During testing:

- changing `STRING_FINISH_POS_*` color worked;
- changing `STRING_FINISH_POS_*` scale worked;
- changing `STRING_FINISH_POS_*` position did **not** move the text.

This strongly suggests the game assigns finish-result positions dynamically at runtime.

## Installation

1. If you use the "Schaduw" extra car update, install it first.

2. Run the patcher, then enter the game folder and your 16:9 resolution. It writes the patched `spel.dat` and overlay `.ini` files, and moves the originals to the `4x3_backup` folder in the game folder.

3. Start the racing part of the game normally.

To install by hand instead, for example on Windows 7: back up `spel.dat` and the overlay `.ini` files, patch `spel.dat` with the steps in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#manual-patching-on-windows), and copy the files from `A2Racer4_DashboardFix.zip` into the game folder.

## Notes

- This fix was tuned for **2560×1440 16:9**. I was not able to test other resolutions yet.
- The overlay layout was manually tuned by in-game testing.
- The 3D fix is native and does not rely on stretching the image.
- Back up your original files before installing.
- This project does not include original game assets beyond modified configuration/executable patch files.
- All testing was done on Fedora Linux 44 running the game through Wine using DXVK and DgVoodoo in tandem.
- The v1.0.4 crash fix was tested on Fedora Linux 44 with plain Wine 11.19, D7VK v2.4, and dgVoodoo 2.80 with `VRAM = 256` (which crashes without the fix). It hasn't been tested on Windows yet.
