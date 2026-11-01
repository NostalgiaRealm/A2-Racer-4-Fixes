# A2 Racer 4 Fixes

Fixes for the PC version of **A2 Racer 4**:

- the game runs at the resolution of your display, whatever its shape: 16:9, 16:10, 21:9, 32:9, 4:3 or 5:4. It finds that out by itself each time it starts;
- the crash at race start on modern graphics cards is gone;
- the black edges around objects on current graphics drivers are gone;
- the game no longer needs its CD in the drive;
- surfaces no longer flicker where they meet, from Windows Vista on;
- cars no longer lift their nose, lose their drive or crawl on modern PCs: the car physics no longer depend on the frame rate, or on how long the PC or the game has been running;
- the 3, 2, 1 before a race is back, after v1.1.0 to v1.4.0 of this patch lost it;
- from Windows Vista on the screen runs in 32-bit color instead of 16-bit, which Windows 8 and newer only emulate;
- from 66 frames per second on, cars no longer climb invisible ramps or hang in the air, a bug in the game's physics engine that made them pull their front up and stop driving;
- pressing Enter, or the game putting a car back on the road, now actually frees the car;
- a car that really gets caught on something, with its wheels in the air, goes back on the road by itself;
- police cars, the chase camera, car lighting, skid marks, smoke, mud and water, pickups and more no longer change with the frame rate.

They consist of a patched `spel.dat` executable module that holds these fixes, a small patch to `menu.exe` for the CD check, and an automatic patcher called `A2Racer4Fixes`, for 64-bit and 32-bit Windows and Linux, that applies them to the game folder you choose. You run the patcher once.

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

## Car physics (v1.4.0)

On modern PCs cars could pull their nose up, lose their drive or crawl, and traffic did this most of all. Four bugs in the game caused it, and they are all fixed:

- **Traffic lifted its nose.** The game gives traffic one push per frame, with an amount that suits about 25 frames per second. At 60 frames per second that is more than double, and because the force sits low on the vehicle, the nose comes up, by up to 45 degrees. A vehicle like that is also a ramp for every car around it. Each frame now gets its share of the push.
- **The clock.** The game kept its time in a number format that loses precision the longer the clock runs. After weeks of uptime the time between frames is often negative: the whole world runs in slow motion, or stands still at high frame rates, so nothing can drive. Windows 8 and newer keep counting through a normal shutdown when Fast Startup is on, so long uptimes are common. The time between frames now comes straight from the counter.
- **The turbo.** Between two physics steps only the force of the last frame counted, so the turbo of the player and the racers lost strength above 66 frames per second. Forces now add up until the next physics step, and are applied once.
- **Gas and brake.** Above 300 frames per second the steps of your pedals got rounded away, and the car stayed where it was with your foot down. The rounded part is now kept.

The game runs at up to 240 frames per second, or your display's refresh rate if that is lower.

Collisions can still throw a car, as they always could.

## The countdown before a race (v1.4.1)

From v1.1.0 to v1.4.0 the 3, 2, 1 and START before a race were gone. This patch kept a value in a place it took for unused, and the game clears that place when a race loads, so the digits got a size calculated by dividing by zero. The value now sits in memory the game doesn't use.

## Frame rate (v1.5.2)

The car physics stopped depending on the frame rate in v1.4.0 and v1.5.1. A new read through all of the game's code found more that counted per frame what it meant per second. From 25 frames per second up, all of this now behaves the same at any frame rate, as it did at 25:

- **Police:** a chasing police car that drives faster than its target brakes with 13 percent at 30 frames per second and 2 at 165, so at high frame rates it hardly slowed down and ran into or past its target. It now brakes with at least 16. The Supercop trying to reverse out of a stuck spot had the same problem.
- **Chase camera:** it moved a fixed part of the way per frame, so at 165 frames per second it followed five times as tightly as at 30, sat closer at speed and passed on every bump. If you know the game from a fast PC, the camera now lags more than you're used to.
- **Car lighting:** cars stayed dark after a shadow or a tunnel. At 165 frames per second a car standing still could stay 165 of 255 levels too dark.
- **Skid marks:** a long slide left a mark of 0.3 seconds at 165 frames per second, gone within a second. Now it's up to 1.9 seconds, and it fades in 2 to 6 seconds.
- **Smoke:** at high frame rates it stayed where it started and was gone within a second, at a quarter of its size. Below 15 frames per second it shot far ahead of the car. Now it lasts 4 seconds or more and drifts the same at any frame rate.
- **Mud and water:** these filled the room for all particles in 0.15 seconds at 165 frames per second, after which sparks and debris didn't show.
- **Pickups** spun 5 times as fast at 165 as at 30 frames per second, and **animated objects**, **debris** and the shrinking of a pickup you take went by frames too.
- **Speed camera flash:** it lasted one frame, which at 240 frames per second is 4 ms. Now it's 40 ms.
- **Turbo tank:** now 10 seconds at any frame rate.

None of this changes how your own car drives, apart from how long the turbo lasts. The details are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#patch-part-13-what-still-counted-frames).

## Cars that lift up or float (v1.5.1)

This is the bug that made a car pull its front up out of nowhere and then stop driving, or stay hanging in the air. It sat in the game's physics engine, and it only shows from 66 frames per second on, the rate of the physics. At 51 frames per second you could race without ever seeing it, and at 165 it came back.

When the body of a car touches a triangle of the road, the engine keeps that contact and looks at the distance to the plane of that triangle, and a plane has no edges. It also checks whether the car is still over the triangle, but something the game does once per frame threw that answer away. At low frame rates enough checks got through. From 66 frames per second on, none did. So a body that had touched a slope, a kerb or a ramp kept pressing against an invisible extension of it. Where that plane rises in front of the car, the car climbs it nose first until its front wheels are off the road.

Those checks now count at any frame rate.

## Putting a car back on the road (v1.5.1)

The reset, by Enter or by the check below, had a few faults of its own:

- It left the old contacts in place, and they went along. A car could hang from a plane far above the road with its rear in the air, however often it was reset. A car now starts without contacts.
- A reset of any car made the Enter key wait 5 seconds, so a racer that kept getting reset kept your Enter from working. Now only Enter itself makes Enter wait.
- A reset left the car listed on the lane it came from, for the rest of the race, so lanes looked taken for other cars and for the next reset.
- When the lanes of the last section of a track looked taken, the game stopped with the error `Illegal chunk`.
- On three stages it could put a car on the ground under a raised road, or on top of a tunnel. It now goes by the height of the lane in those places.

## Cars that get hung up (v1.5.0)

A car can also really get caught, on the side of a jump ramp or on a part of a bridge, or land on its roof. The game only corrected a car that spins, so a racer could stay there until the end of the race, and you had to press Enter.

A car that stands still for 3 seconds with its front or rear wheels off the ground, or tipped over, goes back on the road by itself. This goes for you, the racers and the police, and at any frame rate.

A frontal hit still lifts a car's nose, for example when you run into a truck, because the hit lands above the center of mass, which these cars have at the bottom of the body.

## 32-bit display mode (v1.5.0)

The game used to ask Windows for a 16-bit display mode. Windows 8 and newer have no real 16-bit modes and convert every frame on its way to the screen, and that gets slower as the resolution goes up. From Windows Vista on the game now asks for 32 bits. On a laptop with a Radeon 760M and a 165 Hz display that took the race at the display's normal resolution from 51 to 165 frames per second. Textures stay 16-bit, so the picture looks the same, apart from a loading picture with smoother gradients. Windows XP and older keep 16 bits, because the graphics cards of that time may not handle this.

This also means a resolution no longer needs a 16-bit mode to work.

## No more flickering (v1.3.0)

Where two surfaces lie close together, the game used to flicker. Its 16-bit Z-buffer is too coarse for how far it can see. From Windows Vista on the patch asks for 24 bits, or 32, and falls back to 16 if the driver has neither. This used to need dgVoodoo. Windows XP and older keep 16 bits, because the graphics cards of that time may not handle more with a 16-bit screen.

## Automatic resolution (v1.3.0)

The game now reads the resolution of your display every time it starts, and sets up the 3D view and the HUD for it. Change your display or its resolution and the next race just fits, without running the patcher again.

Nothing is written for this: it all happens in memory while the game runs, so no files change and no administrator rights are needed. The `overlay*.ini` files stay as the game ships them.

If you want something other than your display's resolution, or the game can't use it, type a fixed resolution when the patcher asks. Run the patcher again and press Enter to go back to automatic.

With more than one display, the game uses your main one. Windows display scaling above 100% needs no settings: the race uses the display's real resolution.

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
2. nothing for the resolution: press Enter and the game follows your display. To fix it instead, type one such as `2560x1440`.

It writes the patched `spel.dat` and `menu.exe` into that folder, and puts back the game's own overlay `.ini` files if an older version of this patch changed them. Every file it replaces is moved to a `4x3_backup` folder in the game folder; earlier backups are never overwritten. It refuses to patch an unknown `spel.dat` version.

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

The "Schaduw" extra car update and its `overlay7.ini` work in either order.

`A2Racer4Fixes.exe` needs Windows 10 or newer, so on older 64-bit Windows use the 32-bit version. On Windows XP that one needs Service Pack 3. Service Pack 2 is untested, and Microsoft documents that programs with a manifest like this one can make an unpatched SP2 restart, so update to SP3 first, or install hotfixes KB921337 and KB943232. It doesn't support game folders with characters outside your system's code page: it gives an error and changes nothing.

The game can only use a resolution your graphics driver offers: at 32-bit color from Windows Vista on, at 16-bit color on Windows XP and older. If it stops with "could not set display mode", type a fixed resolution in the patcher that is listed in your display settings.

The 32-bit Windows version needs a 486 or newer. The 32-bit Linux version needs a processor with MMX but not SSE2, so it also runs on a Pentium III or Athlon XP, and Linux 3.2 or newer.

## What the `spel.dat` patch changes

The original game is built around 4:3 display modes. Forcing another shape makes the image stretched or zoomed. The patch does the following, all calculated from your resolution when the game starts. The details and the code behind them are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md).

1. **Display mode:** the game's mode table is set to the resolution of your display.
2. **3D view:** the vertical view stays as it is at 4:3, and the horizontal view is set to `0.75 x width / height`. Pixels stay square at every shape. A wider screen shows more on the sides, and a narrower one such as 5:4 shows slightly less.
3. **HUD proportions:** the game squashes its HUD vertically on anything but 4:3. The patch makes it use the 4:3 shape there too, so the HUD keeps its original proportions and its size relative to the height of the screen.
4. **Texture memory crash fix:** not related to the screen shape, see [Crash fix for modern graphics cards](#crash-fix-for-modern-graphics-cards-v104).
5. **Transparency fix:** see [Black edges around objects](#black-edges-around-objects-v120).
6. **CD check removal:** see [No CD needed](#no-cd-needed-v120).
7. **Deeper Z-buffer:** see [No more flickering](#no-more-flickering-v130).
8. **Car physics:** see [Car physics](#car-physics-v140).
9. **32-bit display mode:** see [32-bit display mode](#32-bit-display-mode-v150).
10. **Cars that get hung up:** see [Cars that get hung up](#cars-that-get-hung-up-v150).
11. **Contacts in the physics engine:** see [Cars that lift up or float](#cars-that-lift-up-or-float-v151) and [Putting a car back on the road](#putting-a-car-back-on-the-road-v151).
12. **Frame rate:** see [Frame rate](#frame-rate-v152).

## How the HUD moves

The overlay files describe the HUD on a 640x480 canvas. While the game reads them, it moves elements attached to a screen edge, by the same amount everywhere:

```text
shift = (0.75 x width / height - 1) x 320 / 0.99, rounded
```

| Shape | Example | Shift |
|---|---|---|
| 5:4 | 1280x1024 | -20 |
| 4:3 | 1600x1200 | 0 |
| 16:10 | 1680x1050 | +65 |
| 16:9 | 2560x1440 | +108 |
| 21:9 | 3440x1440 | +256 |
| 32:9 | 5120x1440 | +539 |

- **To the right:** the speedometer and everything on it, and the race time, lap and position text.
- **To the left:** the communicator and everything on it, the character portraits and the player portraits.
- **Unchanged:** everything else, including all `Scale` values and all vertical positions. Elements in the middle stay in the middle.

This needs the game's own files, because a changed file would move twice. The patcher puts them back from `4x3_backup`. If it can't find an original for a file that older versions of this fix tuned by hand, it asks you to restore that file from the game CD.

## Installation

1. Run the patcher (on Windows, click Yes when it asks for administrator rights), then enter the game folder and press Enter at the resolution question. It writes the patched `spel.dat` and `menu.exe`, and moves the originals to the `4x3_backup` folder in the game folder.

2. Start the racing part of the game normally.

To install by hand instead: back up `spel.dat` and `menu.exe`, and follow the steps in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#manual-patching-on-windows).

## Notes

- The 3D view and HUD layout are calculated from the game's own code. Since v1.1.0 they no longer use hand-tuned values.
- v1.1.0 was checked in-game by the author. The files it writes were compared under Wine at shapes from 5:4 to 32:9.
- v1.3.0 was checked in-game by the author on a Radeon 760M under Windows 10: following the display through several resolutions, the race and menu at 150% display scaling, and no more flickering. Under Wine with software rendering, one patched game folder also ran at 4:3, 5:4, 16:9 and 16:10 by changing only the desktop size. At 16:10 the HUD was within a few pixels of v1.2.0.
- The 32-bit Windows version is a small C program since v1.1.0, tested under Wine in Windows 98, XP, 7 and 10 mode. v1.1.1 ran fine on real Windows 7 32-bit with a Mobility Radeon HD 5750. Earlier versions of the same code ran on Windows 98 SE in a VM.
- The 32-bit Linux version was tested in earlier releases on a 32-bit Linux 3.18 kernel in QEMU, on emulated processors without SSE2.
- The v1.2.0 transparency fix was checked in-game by the author on a Radeon 760M under Windows 10. The fix and the CD removal also ran through a race start under Wine with software rendering. Both patchers wrote identical files.
- The v1.4.0 car physics were checked in-game by the author, and measured under Wine with software rendering, from 15 to about 440 frames per second and with a faked 30-day uptime. The numbers are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#measurements).
- The v1.4.1 countdown was checked in-game by the author, and under Wine with software rendering at 4:3 and 16:9.
- The v1.5.0 display mode was checked in-game by the author on a Radeon 760M under Windows 10: 165 FPS at the display's normal resolution, up from 51/52. The display mode and the 240 FPS limit also ran under Wine with software rendering.
- The v1.5.0 check for cars that get hung up was checked in-game by the author, and tested under Wine with software rendering, at 165 and 51 frames per second, with a bot and with test placements on a jump ramp. The numbers are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#patch-part-11-cars-that-get-hung-up).
- The v1.5.1 physics engine fix was tested under Wine with software rendering, with a bot on all nine stages and with test placements, and with the stuck car of a test read from the running game. It went out before any check on real hardware. The author then tested the v1.5.2 test build, which includes it, in-game. The numbers are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#patch-part-12-contacts-that-outlive-their-triangle).
- The v1.5.2 frame rate fixes were tested under Wine with software rendering, with a bot on all nine stages, at up to 98 frames per second. The author tested the build in-game before the release. The numbers are in [`README_technical_spel.dat.md`](README_technical_spel.dat.md#patch-part-13-what-still-counted-frames).
- Back up your original files before installing.
- This project does not include original game assets beyond modified configuration/executable patch files.
- Testing before v1.1.1 was done on Fedora Linux 44, running the game through Wine using DXVK and DgVoodoo in tandem.
- The v1.0.4 crash fix was tested on Fedora Linux 44 with plain Wine 11.19, D7VK v2.4, and dgVoodoo 2.80 with `VRAM = 256` (which crashes without the fix). v1.1.1 also ran fine on real Windows 10 64-bit with a Radeon 760M.
