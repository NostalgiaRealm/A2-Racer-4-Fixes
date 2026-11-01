# Technical notes: the A2 Racer 4 `spel.dat` patch

This document explains how `spel.dat` is modified so **A2 Racer 4** renders correctly at any resolution. Since v1.3.0 the resolution is not in the patched file: added code reads it from the display every time the game starts, and fills in everything that depends on it in memory. No file changes when the display changes. Everything depends only on the width `W` and height `H`. The examples use 2560×1440.

## Important background

A2 Racer 4 uses `spel.dat` as the executable module for the actual DirectDraw/Direct3D racing portion of the game. Even though the extension is `.dat`, it is a normal PE32 Windows executable.

The original game is designed around 4:3 display modes. If another display mode is forced, the game does not adapt by itself: the 3D view and the HUD both distort.

The patch:

1. sets the display-mode table to the resolution of the display;
2. keeps the vertical view of the Direct3D viewport at 4:3 and calculates the horizontal view from the screen shape;
3. makes the HUD use the 4:3 shape as well, and moves elements attached to a screen edge to that edge while the game reads the `overlay*.ini` files, which stay as they are.

## What “Hor+” means here

The vertical view stays as it is at 4:3, and the horizontal view follows the shape of the screen. A wider screen shows more on the sides. A screen narrower than 4:3, such as 5:4, shows slightly less.

## PE layout notes

For this `spel.dat`:

```text
Image base: 0x00400000
```

The sections relevant to this patch have matching file offsets and RVAs, so the virtual address is usually:

```text
VA = 0x00400000 + file_offset
```

Examples:

```text
file offset 0x0C0E57 -> VA 0x004C0E57
file offset 0x1B3798 -> VA 0x005B3798
```

## Summary of the patch

| Part | Change |
|---|---|
| 1 | Display-mode table set to `W`×`H` at startup |
| 2 | Viewport divides by a stored 4:3 reference width `(H × 4 + 1) / 3` instead of `W` |
| 3 | Horizontal clip range becomes `±0.75 × W / H`, calculated in the viewport setup |
| 4 | Texture memory crash fix, not related to the screen shape |
| 5 | HUD code uses the 4:3 reference width instead of `W`, in three places, and moves elements to the screen edges |
| 6 | Transparency fix: alpha test instead of relying on the color key, not related to the screen shape |
| 7 | CD check removal, in `spel.dat` and `menu.exe` |
| 8 | Deeper Z-buffer against flickering, not related to the screen shape |
| 9 | Car physics: exact time steps, forces and pushes that follow time instead of frames, working pedals, a 240 FPS limit |
| 10 | 32-bit display mode from Windows Vista on, not related to the screen shape |
| 11 | A car that hangs with an axle in the air, or tipped over, goes back on the road |
| 12 | Contacts in the physics engine end when they leave their triangle at any frame rate, and when an object is moved; the reset cleans up after itself |
| 13 | Police, the Supercop, the chase camera, car lighting, skid marks, smoke, mud and water, pickups, animated objects, debris, the speed camera flash and the turbo tank no longer depend on the frame rate |

## Patch part 1: display-mode table

`WinMain` calls the game's init function at VA `0x004582AA`. That call now goes to `startup` in the added code first, see [All added and changed bytes](#all-added-and-changed-bytes).

`startup` first calls `SetProcessDPIAware`, looked up at runtime because it does not exist before Windows Vista. Without it, Windows display scaling above 100% scales what this process sees, and at 150% on Windows 10 the screen showed only the top left part of the game. It has the same effect as setting "Override high DPI scaling behavior" to "Application" in the file's compatibility settings, so that setting is no longer needed.

`startup` then takes the resolution from:

1. the two values at the end of the added code, if the patcher wrote a fixed resolution there;
2. otherwise `EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS)` for the primary display, looked up at runtime because `spel.dat` doesn't import it;
3. if that fails, `GetSystemMetrics(SM_CXSCREEN / SM_CYSCREEN)`.

`menu.exe` changes the display mode while it runs, but puts it back before it exits, and the launcher only starts `spel.dat` after that.

It then writes `W` and `H` as 32-bit values to the current mode and all 16-bit entries of the game's mode tables, whichever one `RESOLUTION` in `raser.ini` selects:

```text
0x005B3798  0x005B37EC  0x005B3800  0x005B3814  0x005B3864  0x005B3878
0x005B388C  0x005B38A0  0x005B38B4  0x005B3904  0x005B3918  0x005B392C
```

Each holds the width, followed by the height. All of this is in memory, in `.data`.

## Patch part 2: 4:3 aspect denominator

The relevant Direct3D viewport setup code originally does this:

```asm
fild  dword ptr ds:0x005B379C   ; load display height
fidiv dword ptr ds:0x005B3798   ; divide by display width
```

After the display table is changed to 2560×1440, that calculation becomes:

```text
1440 / 2560 = 0.5625
```

That is a true 16:9 ratio, but it is not what this old 4:3 projection path wants. In this game, allowing the projection path to use `0.5625` causes the 3D view to behave incorrectly.

For the correct Hor+ result, the calculation is redirected to use a 4:3 reference width:

```text
1440 / 1920 = 0.75
```

So `startup` stores `(H × 4 + 1) / 3`, `1920` here, in free memory after the game's data, VA `0x00751F38`, and the `fidiv` operand is changed to point to that value.

Up to v1.4.0 this value sat at `0x005973D0`, which is zero in the file and looked unused. It is a field of the game's racer table, which the game clears when the race loads, about a second after `startup` runs. Everything placed during loading was fine. The start digits are scaled every frame (`FUN_00496110`, through `FUN_0047CD90` from part 5), so from v1.1.0, when that function started using this value, they divided by 0 and the 3, 2, 1 and START were gone.

### Code redirection

Original instruction at file offset `0x0C0E57`, VA `0x004C0E57`:

```asm
fidiv dword ptr ds:0x005B3798
```

Original bytes:

```text
DA 35 98 37 5B 00
```

Patched instruction:

```asm
fidiv dword ptr ds:0x00751F38
```

Patched bytes:

```text
DA 35 38 1F 75 00
```

This makes the game divide by the 4:3 reference width instead of the actual 16:9 output width.

## Patch part 3: horizontal clip range

The same viewport setup block writes the Direct3D clip rectangle, a `D3DVIEWPORT2`:

```asm
mov dword ptr [esi+0x14], 0xBF800000   ; dvClipX     = -1.0
mov dword ptr [esi+0x1C], 0x40000000   ; dvClipWidth =  2.0
```

With part 2 the vertical range is `±0.75`. Pixels are square when the two ranges have the shape of the screen, so:

```text
dvClipX     = -0.75 × W / H
dvClipWidth =  1.5  × W / H
```

At 4:3 this gives the original `-1.0` and `2.0`. At 16:9 it gives `-1.3333` and `2.6667`.

The first instruction becomes a call to `set_horizontal_view` in the added code, which calculates both values from the current mode at `0x005B3798` and `0x005B379C`. The second becomes `nop`s.

| File offset | VA | Original | Patched |
|---|---|---|---|
| `0x0C0E8A` | `0x004C0E8A` | `C7 46 14 00 00 80 BF` | `E8 84 48 0B 00 90 90` |
| `0x0C0E96` | `0x004C0E96` | `C7 46 1C 00 00 00 40` | `90 90 90 90 90 90 90` |

v1.2.0 and older wrote the values into these instructions, so a patcher only checks the first three bytes there.

## Patch part 4: texture memory crash fix

This part is not related to the resolution. It fixes a crash in the original game that happens on every PC with a modern graphics card, at any resolution.

### The problem

When the Direct3D device is created at race start, the game measures how much texture memory the card has. It creates 256×256 textures in local video memory (`DDSCAPS_TEXTURE | DDSCAPS_VIDEOMEMORY | DDSCAPS_LOCALVIDMEM`) until `CreateSurface` fails, then releases them again. The surface pointers are kept in a fixed array of 1024 entries on the stack, and nothing checks the count.

At 16-bit colour every texture is 128 KB, so any card or driver that lets more than ~128 MB of video memory be allocated overruns the array. The overrun overwrites the return address and the exception handler records on the stack, and keeps going until it hits the top of the stack:

```text
EXCEPTION_ACCESS_VIOLATION at 0x004BC11A, writing 0x00370000 (top of the main thread's stack)
```

The broken exception handler chain then turns this into a stack overflow. You see a black screen when the race should start.

This is why the game used to need dgVoodoo with `VRAM` set to 128 MB or less: with 256 MB it crashes at exactly the same address. Plain Wine reports the card's real VRAM, so it crashes too.

The probe function, at VA `0x004BC0F0`:

```asm
004bc0f0: b8 00 10 00 00        mov    eax, 0x1000           ; 4 KB local array = 1024 pointers
004bc0f5: e8 06 d3 09 00        call   0x559400              ; stack probe
004bc0fa: 53                    push   ebx
...
004bc108: 68 00 01 00 00        push   0x100                 ; 256
004bc10d: 68 00 01 00 00        push   0x100                 ; 256
004bc112: e8 59 ff ff ff        call   0x4bc070              ; IDirectDraw::CreateSurface wrapper
004bc11a: 89 06                 mov    dword ptr [esi], eax  ; store pointer, no bound check
004bc11c: 85 c0                 test   eax, eax
004bc11e: 74 13                 je     0x4bc133              ; only exit: CreateSurface failed
...                                                          ; add (bpp/8) << 16 bytes, next entry
004bc135: 89 9d a1 02 00 00     mov    dword ptr [ebp+0x2a1], ebx   ; store the measured amount
```

### The fix

The function has a single result: the measured byte count it stores at `this+0x2A1`. The game uses that value in two places:
- as the upper limit for its texture cache, as `min(custom_texture_memory, measured)`;
- it writes it to `game.ini` as `available_texture_memory`.

So the patch replaces the start of the function with "store 64 MB and return", and skips the probe entirely:

```asm
004bc0f0: c7 81 a1 02 00 00 00 00 00 04   mov dword ptr [ecx+0x2a1], 0x4000000   ; 64 MB
004bc0fa: c3                              ret
```

| File offset | VA | Original | Patched |
|---:|---:|---|---|
| `0x0BC0F0` | `0x004BC0F0` | `B8 00 10 00 00 E8 06 D3 09 00 53` | `C7 81 A1 02 00 00 00 00 00 04 C3` |

Both callers pass the object in `ecx` and ignore the return value. The texture cache is still sized by `custom_texture_memory` from `game.ini` (4 MB as shipped, 8 MB after the menu's Texture detail setting), which is far below 64 MB. With `DEBUGON=1` the game's own `debug.txt` confirms it:

```text
Available texture memory: 4000000   (Real texture memory: 67108864)
```

Game versions 1.00 and 1.01 ship an identical `spel.dat`, so the same bytes apply to both. None of the resolution changes are near this offset.

## Patch part 5: HUD proportions

Three functions place the HUD and use the real screen shape:

```text
FUN_0047cd90, scale:     y = (H / W) × 0.99 / 240
FUN_0047fd20, position:  y = (1 - 0.99 / 240 × y) × (4/3) / (W / H)
FUN_00480500, position:  the same as FUN_0047fd20
x in both:               x = 0.99 / 320 × x - 1
```

On anything but 4:3 this squashes the HUD vertically. Using the 4:3 reference width from part 2 in place of `W` makes the vertical terms the same as at 4:3, so nothing needs a different `Scale`, including what the game places itself.

| File offset | VA | Original | Patched |
|---|---|---|---|
| `0x07CDD1` | `0x0047CDD1` | `DA 35 98 37 5B 00` | `DA 35 38 1F 75 00` |
| `0x07FE55` | `0x0047FE55` | `DB 05 98 37 5B 00` | `DB 05 38 1F 75 00` |
| `0x080534` | `0x00480534` | `DB 05 98 37 5B 00` | `DB 05 38 1F 75 00` |

Horizontally, HUD `x` reaches the screen edges where `0.99 / 320 × x - 1 = ±0.75 × W / H`. Compared with 4:3 the edges move by `(0.75 × W / H - 1) × 320 / 0.99`, which is the shift for elements attached to an edge. See [Overlay files](#overlay-files).

## Patch part 6: transparency fix

### The problem

Textures are 24-bit TGA files that mark transparent pixels with `(255, 0, 127)`. While loading, the game turns that color into its key, `DAT_00740D24/28/2C`, which nothing ever writes and so stays 0. Any other color that would become 0 is moved to red 1 (`FUN_004C7EE0`, `FUN_004C81B0`). So in a 16-bit texture, transparent means exactly `0x0000`, black.

The game then calls `SetColorKey` with key 0 and enables `D3DRENDERSTATE_COLORKEYENABLE` once at device creation. On a Radeon 760M under Windows 10 this shows black around objects and HUD elements, while a Mobility Radeon HD 5750 under Windows 7 does not. `FILTER=0` makes no difference, so it is not a filtering fringe. Under Wine, forcing `COLORKEYENABLE` to 0 gives the same kind of black.

### The fix

The code is in [`A2Racer4Fixes_source/spel_patch.asm`](A2Racer4Fixes_source/spel_patch.asm), see [All added and changed bytes](#all-added-and-changed-bytes).

1. **Format:** the game selects the alpha format with the most alpha bits, which it never uses. The selection now prefers the fewest, normally A1R5G5B5. At init the game asks for `16BPP_RGB`; if a 16-bit alpha format exists, the patch asks for `16BPP_ALPHA` instead, sets `ALPHATESTENABLE = 1`, `ALPHAFUNC = GREATER`, `ALPHAREF = 0` and turns `COLORKEYENABLE` off. Without such a format everything behaves as before.
2. **Texels:** both color converters end by setting the alpha mask on any result other than 0. Other surfaces have an alpha mask of 0, so they are unaffected.
3. **Vertex alpha:** `D3DTBLEND_MODULATE` takes alpha from a texture that has it and ignores vertex alpha, which would make shadows and clouds opaque. All 18 `ALPHABLENDENABLE` call sites go through a helper that also selects `D3DTBLEND_MODULATEALPHA` while blending is on and `D3DTBLEND_MODULATE` when it is off.
4. **Alpha 0 that must stay visible:** skidmarks and the radar use the inverted `INVSRCALPHA / SRCALPHA` blend, where fresh marks have alpha 0, and objects have blend modes such as `ONE / INVSRCCOLOR`. At those three "on" sites (`0x044523C`, `0x044275E`, `0x0B5E50`) the helper turns the alpha test off until blending is switched again.
5. **Viewport clear:** the alpha test is off during `IDirect3DViewport2::Clear`.

### Why the color key has to be off

Three test builds were run on the Radeon 760M, all with the format, texel and vertex alpha changes:

| Build | Alpha test | Color key | Clear guard | Result |
|---|---|---|---|---|
| A | on | on | yes | HUD clean, 3D broken: frozen frame with blocks of stale pixels and a solid black car body |
| B | on | off | yes | Correct: solid 3D, no black edges in 3D or the HUD |
| C | off | on | yes | Screen full of rapidly moving colored blocks |

Why this driver behaves this way is unknown. The Clear guard made no visible difference by itself in build A. It stays because no build without it has been tried on this GPU.

Known limit: with the color key off, the few texels with the key inside the part of `S_SFX` used for skidmarks are drawn dark, because the alpha test is off for skidmarks.

## Patch part 7: CD check removal

`spel.dat`: `FUN_004CD3B0` looks for the disc on all CD-ROM drives and stops with "A2 Racer CD-ROM niet gevonden" when it finds none. The stop now returns instead. Files are looked up in the game folder first (`FUN_004CD4A0`), so the disc is only used for a file missing from the folder, and a disc that is present still works.

| File | File offset | VA | Original | Patched |
|---|---|---|---|---|
| `spel.dat` | `0x0CD478` | `0x004CD478` | `68 70` | `EB B6` |
| `menu.exe` | `0x0A5154` | `0x004A5D54` | `E8 7F FE FF FF 84 C0 74 08` | `90 90 90 90 90 90 90 90 90` |

`menu.exe`: `FUN_004A5D4C` searches drives C to Z for `DATA\INTRO1.MPG` and shows its "CD not found" dialog when that fails. The patch skips the search and takes the "found" result. The intro itself plays from the game folder first (`FUN_004A50D0`).

The optional `[CDCHECK]` section the game can read from `game.ini` is not in the shipped file and is left alone. Without it the game does not check.

## Patch part 8: deeper Z-buffer

Where surfaces lie close together, the game flickers. `FUN_004C0610` creates the Z-buffer with the depth its caller passes, always 16 bits, and the view runs from 10 to 12500 (`FUN_004B39D0`). Depth precision falls with distance as roughly `z² / (near × 2^bits)`, so at 16 bits two surfaces about 1.5 units apart at distance 1000 can already swap places from frame to frame. Forcing a 24-bit or 32-bit Z-buffer with dgVoodoo removes the flickering.

The call to `IDirectDraw::CreateSurface` at VA `0x004C0679` now goes to `create_zbuffer` in the added code, which tries 24 bits, then 32, then the original 16. The game never reads the Z-buffer itself, so nothing else depends on its depth.

This only happens from Windows Vista on (`GetVersion` major version 6 or higher). Cards from the Windows 9x and XP period could accept a Z-buffer of another depth than a 16-bit screen when it is created and only fail when drawing, so those systems keep 16 bits and keep the flickering.

Known limit: if a driver accepts the deeper Z-buffer but then refuses the Direct3D device, the game stops with its device error. There is no retry at 16 bits.

## Patch part 9: car physics

Cars could pull their nose up, lose their drive or crawl on modern PCs. Four bugs in the game tie the physics to the frame rate and to how long the clock has run. The physics world itself is not the problem: Ipion steps at a fixed 66 Hz (`FUN_004A6A10` sets 0.015151516 seconds), and the wheels of the player's car and the racers (`IVP_Car_System_Real_Wheels`, vtable `0x00578568`) run inside those steps. The trouble is in how the game feeds it.

### The clock

`FUN_004A6700` keeps the game time at `0x007128B8` as a 32-bit float of seconds, taken directly from `QueryPerformanceCounter`, which counts from when Windows started. The time step is the new value minus the stored, rounded old one:

```asm
fild  qword ptr [esp+0xc]       ; counter
fdiv  float ptr [esi+4]         ; / frequency
fld   st0
fsub  float ptr [esi+8]         ; - previous time, rounded to a float
fstp  float ptr [esi+0xc]       ; time step
fstp  float ptr [esi+8]         ; time, rounded to a float
```

A float has 24 bits, so its resolution falls as uptime grows: 3.9 ms after 9 hours, 62.5 ms after 6 days, 250 ms after 24 days. Every frame's time step is then wrong by up to half of that, can be negative, and the average of the last four frames doesn't hide it. Windows 8 and newer don't reset the uptime on a normal shutdown with Fast Startup on, so long uptimes are common. `FUN_004A6800`, which about 240 places in the game use, also returns 0.1 seconds for a step of 0 or above 0.1, and passes negative steps on.

Measured at a fixed 60 FPS, with only the uptime faked (true step 0.01667):

| Uptime | Time steps seen by the game | Negative | Average |
|---|---|---|---|
| near 0 | 0.01666 to 0.01672 | 0% | 0.01667 |
| 3 days | 0.0114 to 0.0234 | 0% | 0.01693 |
| 12 days | 0.0053 to 0.0325 | 0% | 0.01790 |
| 30 days | -0.0726 to 0.1109 | 46% | 0.0087 |

`FUN_004AA0C0` advances the world by a moving average of these steps, so the world slows down with them. World time after 46 seconds of real time at a faked 30 days:

| Frame rate | Old clock | New clock |
|---|---|---|
| 60 FPS | 24.7 s | 45.1 s |
| about 370 FPS | 17.2 s, and it stood still from 11 to 26 s | 45.2 s |

While the world stands still no car can move, and pressing Enter only moves the car to another spot in a world that still stands still. In the first 50 seconds at 60 FPS the player's car covered 921 units with the old clock and 10640 with the new one.

`timer_counter` and `timer_ticks` replace the four clock calls in `FUN_004A6700` and `FUN_004A6840`, and count from the game's start. `timer_step` replaces the lines above in both functions, and takes the step from the counter itself instead of from the float:

```asm
fld   st0                       ; counter, from the game's start
fsub  qword ptr [LAST_COUNT]    ; - counter at the last update
fdiv  float ptr [esi+4]         ; / frequency
fstp  float ptr [esi+0xc]       ; time step
fst   qword ptr [LAST_COUNT]
fdiv  float ptr [esi+4]         ; / frequency
fstp  float ptr [esi+8]         ; time, for what reads it
```

So neither the uptime of Windows nor how long the game has run changes the step. `world_step` replaces `FUN_004A45D0`, which added up world time in a float as well, and uses a double.

### The driving force

`FUN_004A5CE0` is the force controller, which drives traffic and the turbo. It runs on every physics step and applies the force at `+0x80` as an impulse, without a time step. It then checks the length of that force, but `FUN_004F9680` also normalizes the vector in place:

```c
FUN_004a5ce0(...):
    local = rotate(this->force);            // force for this step
    length = FUN_004f9680(&this->force);    // returns the length, and normalizes
    if (length >= 1e-10 && core is simulated)
        FUN_004f41b0(core, anchor, &local); // apply it
```

So a force that `FUN_004A5C70` sets once per frame works at full strength on the first physics step after that frame, and after that as a vector of length 1, which is nothing next to the mass of a car. Measured, the set value was 480 and the stored value read 1.000. The force per second therefore grows with the frame rate up to 66 FPS. Above that, frames overwrite each other's force before a physics step takes it, so a force that is scaled by time, like the turbo in `FUN_00428C70` (`dt × mass × (|v| × 0.025 + 0.5) × 25`), gets weaker.

`force_add` makes `FUN_004A5C70` add to what is waiting instead of replacing it, and `force_take` replaces the call to `FUN_004F9680`, which is still used for the length, and clears the force. A physics step now applies everything since the last one, once, at any frame rate.

### Pushes per frame

`FUN_00428950` (traffic) and `FUN_00415E40` (vehicles on a fixed path) run every frame and work out everything from the mass, without a time step: the thrust of `0.8 × mass` through the controller, a push of `-mass × sideways speed`, and a downforce of `mass × |speed| × 0.12`. Trailers push the same way through `FUN_004A97F0`.

The thrust acts below the centre of mass (Ipion's y axis points down, and these vehicles attach their force at y = +0.55 up to +1.60), so every firing pitches the nose up. As a rough model, with the tail as a pivot, the nose stays down as long as `acceleration × height < 9.81 × distance to the axle`. For a car that is at about 35 units/s², so about 45 FPS, and for a truck it is at about 23 units/s², so about 30 FPS. Above that the nose comes up until the game's own check `up.y >= 0.9` cuts the force. Above 66 FPS the thrust stops growing while the downforce doesn't, which brings the nose down again. That gives a peak at 60 to 75 FPS, where every PC with a 60 Hz display sits, as the table below shows. The vehicle also lifts on flat road with nothing near it, and it's then a ramp for what comes after it.

`traffic_mass` replaces the division that gives the mass in both functions, and multiplies the mass by `frame_share`:

```text
frame_share = min(1, time step × 25)
```

Every force and push in those functions comes from that mass, so this scales all of them. `trailer_push` does the same for trailers. A frame at 25 FPS or slower gets one whole push, as it always did. The rate 25 comes from the game itself: it's the factor in its turbo formula, the one force it did scale by time. It also keeps the thrust of even the trucks below the point above. A rate of 30 gave twice the nose-up (0.19 mean, 0.28 highest at 60 FPS).

### The pedals

The player's gas and brake go through whole numbers:

```c
gas   = (int)(gas + dt * 300);    // FUN_0046F2A0
brake = (int)(brake + dt * 320);  // FUN_0046F2E0
```

Above 300 FPS the step is below 1 and rounds away. The car then stays where it is with the pedal down, unless a slow frame happens to give a bigger step. At about 410 FPS the bot's car stopped dead and needed 8 resets in 110 seconds. `pedal_gas` and `pedal_brake` keep what is rounded off for the next frame.

### The frame limit

`frame_limit` replaces the timer call at the start of every frame (`0x0044CB9E`) and waits until 1/240 of a second has passed. The game doesn't import `Sleep`, so it waits actively, as the unlimited game did anyway. A display at a lower refresh rate keeps the frame rate lower through vertical sync.

Nothing that was checked needs it any more. A sweep of the code for time steps that go through `__ftol` found one whole number step that breaks in this range: the fade of a trailer in `FUN_00430EA0` is `(int)(alpha + dt × 128)` and stopped above 128 FPS, so `trailer_fade` keeps what is rounded off, like the pedals. The other steps are frame counts of the form `(int)(seconds / dt)`, which are fine at any rate, and whole milliseconds per frame in `FUN_00469C60`, which round to nothing at 1000 FPS. The limit keeps the game far from that, and inside the range the physics were measured in. [Part 13](#patch-part-13-what-still-counted-frames) found more that this sweep missed. `FUN_0043C890`, the fuel station camera, writes `(int)(2 / dt)` steps into an array for 100, but nothing calls it. Ipion interpolates positions to the current time, so frames between physics steps do show movement.

### Measurements

All of this ran under Wine 11.20 with software rendering at 640x480, with the frame limit changed for each run, and a clean clock in the "before" columns.

How far traffic's nose rises in the first 3 seconds after a start, as the y of its forward vector (0.7 is 45 degrees), mean and highest of 3 to 7 starts:

| FPS | Before | After |
|---|---|---|
| 15 | 0.06 / 0.07 | 0.06 / 0.07 |
| 30 | 0.19 / 0.30 | 0.11 / 0.19 |
| 45 | 0.40 / 0.60 | |
| 60 | 0.51 / 0.74 | 0.08 / 0.18 |
| 66 | 0.69 / 0.72 | |
| 75 | 0.59 / 0.67 | |
| 90 | 0.49 / 0.58 | |
| 120 | 0.28 / 0.36 | 0.07 / 0.08 |
| 240 | 0.13 / 0.19 | 0.08 / 0.18 |
| about 440 | | 0.08 / 0.17 |

Traffic's acceleration from standstill was 2.9 units/s² at 15 FPS, 14.5 at 30 and 25 to 37 at 60 before. After, it's 9 to 11 at every frame rate from 30 to about 440. Below 25 FPS nothing changes.

A bot driving the player's car along the path of a racer for 110 seconds, with bursts of turbo. It takes the same route each time but crashes differ, so a single run says little: the low racer figure at 120 FPS is one racer crashing, and the second run shows that. Distance in units, then top speed:

| FPS | Player before | Player after | Racers before (mean distance) | Racers after |
|---|---|---|---|---|
| 30 | 22939, 44.2 | 25765, 42.8 | 22187 | 24217 |
| 60 | 24038, 40.8 | 26256, 44.5 and 26085, 47.3 | 22987 | 25350 and 24998 |
| 120 | 21364, 33.7 | 25152, 42.2 and 25698, 44.9 | 21084 | 20242 and 24206 |
| 240 | 17533, 28.1 | 25568, 46.3 | 17728 | 24049 |
| no limit | 15428, 27.9 (409 FPS) | 25437, 43.9 (375 FPS) | 19563 | 24036 |

### What this doesn't establish

- The numbers are from Wine with software rendering, and a held key or a bot. The author checked the result in-game before the release, without these measurements.
- What lifted cars after these fixes is in [Patch part 12](#patch-part-12-contacts-that-outlive-their-triangle). At the time of this part it had not been reproduced by itself. The player's wheels run inside the physics steps, so they don't depend on the frame rate, and a clean clock showed no lifting by itself at any frame rate. What was seen: the frozen and slowed world at a long uptime, and the 8 stops at high frame rates. Nose-up traffic as a ramp under the player's car is inferred, from what it would take for the wheels to lose the road.
- The reset can drop a car on top of another car: Enter at the start of a race put the player's car on the roof of a racer, nose up at 0.24 and wheels spinning, where it rode for 35 seconds. That isn't changed, and it looks a lot like a lifted car. `FUN_0040E5A0` puts the car 20 units above a free spot of the road, but not all vehicles count for that check.
- `FUN_004FC2D0` (the body's counter torque) only runs when braking, so its last value stays until the next brake. It's small: 1600 at full brake, which tilts the car about 1 degree, so it's left as it is.
- Trailers weren't run, and [part 13](#patch-part-13-what-still-counted-frames) found that nothing can reach that code. Some objects on the road still throw a car that hits them at speed, like the one near (-15020, 7570), at any frame rate.

## Patch part 10: 32-bit display mode

`FUN_004C55C0` asks for a display mode with the depth at `0x005B37A0`, always 16 for the race. Windows 8 and newer have no real 16-bit modes and emulate them, converting every frame on its way to the screen. On a Radeon 760M under Windows 10 with vsync off, the game held 51/52 FPS at its normal resolution and reached the limit, then 120 FPS, at 640x480, so the cost grows with the resolution. With the 32-bit mode the same laptop runs at 165 FPS at its normal resolution, so the 16-bit mode was that cost. What exactly takes the time inside Windows was not measured. 165 is the refresh rate of its display, even with vsync set to always off in AMD's settings, so here the game's `Flip` with `DDFLIP_WAIT` does hold it to the display.

`display_depth` replaces reading that depth for the call at `0x004C58AB`: from Windows Vista on (`GetVersion` major version 6 or higher) it asks for 32 bits. The value at `0x005B37A0` stays 16, because the game uses it to choose how to convert textures, and textures stay 16-bit. Windows XP and older keep the 16-bit mode, for the same reason as in part 8.

A DirectDraw trace of a race under Wine shows no `Lock` or `Blt` on any surface after the loading screen, so nothing else depends on the screen's format while racing. The 2D effects that do assume 16-bit pixels on the screen's format, `FUN_0043AE50`, `FUN_0043AF60`, `FUN_00440DF0` and `FUN_00440FB0`, are never called.

The one place that matters is the loading screen. `FUN_004409D0` loads its picture through `FUN_004C00B0` in the screen's own pixel format, and that function only writes 16 bits per pixel, which at 32 bits gave a half-width picture in the wrong colors. `image_pixel` replaces the conversion and store of each pixel there, and writes a whole pixel when the format has 32 bits.

The race, loading screen, countdown, pause and quit screens looked right under Wine at 32 bits, over seven minutes of driving, and races later ran through to the finish screen. Wine says nothing about the gain on Windows: with software rendering at 1280x720 the 32-bit mode ran at 245 FPS against 288 at 16 bits, because that renderer writes twice the bytes.

## Patch part 11: cars that get hung up

[Patch part 12](#patch-part-12-contacts-that-outlive-their-triangle) found what mostly held these cars up: contacts that had left their triangle. This part explains it with the center of mass, which was too simple, and it didn't free a car held that way. The check is still needed for cars that really get caught.

After parts 8 to 10 a test at 165 FPS on real hardware still showed the player's car with its front wheels lifted, and a racer that floated in the air and did not come back to the road. A run under Wine at 165 FPS caught the same thing. The racer drove up the side of one of the wooden jump ramps at 16 units per second, its y went from 2 to 25 in 1.6 seconds, and it then stayed at the same spot for the last 118 seconds of the run, with its wheels spinning freely at about 62 radians per second.

### Why a car stays up there

`FUN_00429710` builds these cars, and `FUN_004A14F0` moves the center of mass to the height stored in the object at `+0x78`. In Ipion's coordinates, where y points down, the wheels end up 0.6 to 1.3 units above the center of mass. Measured against the road, the center of mass is below the road surface. That keeps a car from rolling over in corners, but it has side effects:

- A body that rests on a point has its center of mass under that point. It swings like a pendulum and doesn't tip off. At one spot the car swung between about 12 and 80 degrees nose up without falling. Part 12 shows that this point was usually not on an edge at all, but past the end of a triangle.
- Forces at the height of the road or higher pitch the nose up instead of down. That goes for a frontal hit, and for braking.

The game's correction, `FUN_00419450` and its four callers, only reacts to a rotation above 10 radians per second for 0.25 seconds. A car that hangs still never triggers it. Friction contacts read from the physics engine show what is touching:

```text
pos(-21823.75 1.93 10689.37) up 0.982 forward y 0.191, speed 0
  body touches 'obj254' (a static bridge part, 3 points)
  wheel 0, 1, 2, 3 touch nothing
  wheel y -0.28 on all four, the wheels hanging from their springs
  wheel speed about 69 radians per second on all four
```

Under that bridge part the car looks lifted, and it can't drive because nothing touches the road.

### At 51 and 165 FPS

These hang-ups also happen at 51 FPS, at the same spots, so this part concluded that they had nothing to do with the frame rate. That was too quick. Cars that really get caught happen at any frame rate, but [part 12](#patch-part-12-contacts-that-outlive-their-triangle) shows that the contacts that hold a car up past the end of a triangle only happen from 66 FPS on. Two 900 second runs with the same bot:

| | 165 FPS | 51 FPS |
|---|---|---|
| Mean distance of the three fastest racers | 96.5 thousand units | 96.6 thousand units |
| Wheel y range of the player's car, 0.1% to 99.9% | -1.06 to 0.03 | -1.17 to 0.05 |
| Checks of a stationary car that found all four wheels off the ground | 2 | 2 |
| Checks of a stationary car that found one axle off the ground | 4 | 1 |

The floating racer was seen once in about 2270 seconds at 165 FPS and not in the 900 seconds at 51 FPS, which is too little to say anything about how often it happens.

### The fix

`hung_check` replaces the call to `FUN_00403170` at `0x00428F30`, in the function that drives the player, the racers and the police, and runs right after it. It reads the friction contacts of each wheel from the physics engine (object `+0x28`). `FUN_00403170` itself uses a flag that the friction listener sets when a contact is created and clears when any contact is removed, so that flag can read 0 on a wheel that still touches something. It doesn't change what the turbo does with it.

A car counts as hung when both of these hold:

- its speed is below 1.5 units per second;
- no front wheel or no rear wheel touches anything, or the y of its up vector is below 0.5.

After 3 seconds of that it calls `FUN_0040E5A0`, the same function the Enter key and the game's own correction use, which puts the car 20 units above a free spot on the road. The times are in `HUNG_TIMES` at `0x00751F40`, one for each of the 19 racer slots and one for the player.

A car that can still move doesn't count, as its speed goes above the limit. That includes a car with its front in the air that reverses out on its rear wheels.

### Measurements

Drives with the player's car under Wine at 165 FPS, from the same spot and heading with the gas held down, with a test build that can place the car:

| Build | Result |
|---|---|
| Without `hung_check`, first drive | hangs at y = 21.8 on the side of the ramp, one wheel touching, and is still there after 18 seconds |
| Without `hung_check`, second drive | hangs at y = 44.2, no wheel touching, and is still there after 18 seconds |
| With `hung_check` | hangs at y = 21.7, and is back on the road 3 seconds after it stopped |

Two whole races with the bot, with `hung_check`, both up to the finish screen:

| Frame rate | Race took | `hung_check` moved |
|---|---|---|
| 165 FPS | 471 s | a racer lying on its side against a canal wall; the player hanging at y = 34 at the end of a ramp; the player again 3 seconds later, see below |
| 51 FPS | 431 s | nothing |

It moved no car that stood on its wheels, in these races or at the start. The reset itself can put a car on an edge or inside something, because `FUN_0040E5A0` only checks for other vehicles. In the race at 165 FPS the first reset left the player's car at y = 20 with no wheel touching. Without this part a car stays there, even after pressing Enter, which part 12 explains. `hung_check` tried again after 3 seconds and the game chose the next free spot.

### What this doesn't establish

- The numbers are from Wine with software rendering, a bot and test placements. The author checked the result in-game before the release, without these measurements. What lifted the green car in the test on real hardware wasn't seen, only the same kind of thing.
- A car can still hang for those 3 seconds, and a car with both axles on something, like on top of another car or pressed against a wall, doesn't count as hung. Enter still works for those.
- A frontal hit still lifts the nose, as it follows from where the center of mass is. Moving that would change how every car drives.

## Patch part 12: contacts that outlive their triangle

After part 11 a test at 165 FPS under Wine showed the green car stuck with its rear in the air. `hung_check` fired several times and did not free it. The game could be paused and read as it stood:

```text
pos(-2767.55 89.90 7140.47) up y 0.902, forward y -0.425, speed 0.47, hung for 1.93 s
  the road here is flat, at y = 80
  wheel 0 touches the road under it, wheel 1 touches it without pressure, wheels 2 and 3 touch nothing
  body touches 'chunk_248', twice, with these points of the body:
    (-0.99 -1.18 -2.63), the left rear top corner, at (-2761.1 110.9 7161.5), pressure 803
    ( 0.99 -1.18 -2.63), the right rear top corner, at (-2780.1 112.5 7156.7), pressure 11065
  both on the triangle (-2310.7 80.0 7027.9) (-2361.6 90.0 7026.2) (-2338.3 80.0 6831.0)
  that triangle is 422 and 439 units away from those corners, and its plane runs about 60 units above them
```

So what held the rear of the car up was a contact with a piece of ground far away.

### How a contact ends

The physics engine creates a contact when two objects collide. For a corner of a body on the ground, it holds that corner and a triangle. Each physics step handles it in three stages:

1. `FUN_00505CC0` works out its state, through `FUN_005052D0` for a point on a triangle. The gap is the distance to the plane of the triangle, and a plane has no edges. A negative gap becomes 0, which counts as touching. Whether the corner is still over the triangle is checked by `FUN_005094E0`, but only when the byte at `+0x60` of the contact is 1, and that check clears the byte.
2. Friction (`FUN_0053FB20`, `FUN_0053E010`) sets that byte when the contact slips further than its friction spring allows. For wheels `FUN_00505CC0` sets it itself, every time.
3. `FUN_0053FA30` or `FUN_00549940` removes the contact if the check failed, or if the gap is 0.045 or more in the engine's units, a tenth of the game's. Otherwise it pushes (`FUN_0053D370`), with no limit on the push.

So a contact that slides gets its check in the step after it slipped. That was the design.

### Why that stopped working above 66 FPS

The function that drives the player and the racers, `FUN_00428C70`, calls `FUN_004F21E0` at `0x00428ED5`, which calls `FUN_004F3810`. That runs `FUN_00505CC0` on every contact of the car's body, once per frame, and nothing reads the result. It uses up the byte at `+0x60`: if the check fails there nobody hears of it, and the next physics step does no check.

The world steps at a fixed 66 Hz. At 30 frames per second about half of the steps have no frame before them, and those checks count. From 66 frames per second on, a frame falls between any two steps and no check ever counts. Wheels aren't affected, as they set the byte again every time. Traffic doesn't run `FUN_00428C70`.

The measurements below show this directly. With the same bot on the same stage, the code without this part has 0 to 3 such contacts per race up to 60 FPS, and 21 to 30 above 100 FPS.

### What that does to a car

A contact that survives keeps pressing the body against an invisible extension of its triangle. A contact can only push, so the planes that fall away from the car let go by themselves. The ones that last are the ones that rise in front of it. The car climbs them nose first until its front wheels are off the road, and most of the drive is on those wheels. This is the report that started part 9: the front pulls up out of nowhere and the car can't drive any further.

It needs no reset and no hit. In one race at section 238 of etappe 5, at 233 FPS:

```text
150.08 s  pos(-3445.0 87.9 7744.2)  forward y 0.03  speed 20.5  body on a triangle of chunk_238, 23 units past it, pressure 23524
151.31 s  pos(-3301.3 99.5 7730.8)  forward y 0.79  speed  3.4  the road is at y = 81 here
```

The hang-up of part 11 was the same thing. At y = 19 on the side of the ramp the body hangs from a point 10 units past the end of the triangle, with a pressure of about 18000 and one wheel touching. That point is also the pivot of the pendulum that part 11 saw.

### Why a reset didn't help

`FUN_005020A0`, which moves an object, leaves its contacts alone, and it stops the object, so nothing slips and nothing asks for a check, at any frame rate. The contact only ends if the body lands more than 0.045 above the plane. A reset puts the car 20 units above the road, so where the old plane runs higher than that, the contact stays with a gap of 0. The corners stay where they are while the rest of the car falls, which gives the rear in the air. `hung_check` or Enter moves the car to the next spot and the same contact goes along. A contact 60 units below its plane would take about 300 seconds to work its way up and let go.

A race on the v1.5.0 code caught all of this by itself: the player's car ran into a contact 27 units past chunk_188 at 303 s, stood up, and then hung at y = 100 above the road at y = 80, the height of a reset, swinging between forward y 0 and 0.86, for the 112 seconds until the end of the run. The bot pressed Enter 25 times, and `hung_check` fired as well.

### Other things wrong with the reset

Reading `FUN_0040E5A0` for this turned up more, all from the original game, and made worse by `hung_check` calling it more often:

- It sets the waypoint of the car without taking the car off the list of the old one. That waypoint counts the car forever. Lanes look taken for the rest of the race, for other cars and for the next reset, which then moves the car further ahead. Two Enter presses at the start moved the car 128 units ahead each.
- Every reset of any car sets the time for the 5 second wait of the Enter key. A racer that gets reset every 3 seconds keeps Enter from working at all.
- Near the end of the track it steps to the next section without wrapping around. When the lanes of the last section look taken, the game stops with the error `Illegal chunk: 327`.
- It takes the height from the first surface it finds under the lane, with no look at how high that is. At sections 296 and 305 of etappe 5, where the road runs at y = 80 to 100, that is the ground at y = 0, so the car ended up at y = 1 under the road. On etappe 6 the same happens at sections 175, 183, 194 and 244, and on etappe 7 at section 15 it picks the surface at y = 449 above a tunnel, for a road at y = 73. This comes from reading the track files for every lane: only these three stages have it.
- The move stops the car but not its rotation, and the game's correction for a spinning car (`FUN_00419450`) goes on until the spin stops, so a car can get reset again on the next frames and comes down still turning. In a test with a fast spin the reset fired once or twice, as the spin dies off quickly, so this matters less than the rest.

### The fix

| Hook | Where | What it does |
|---|---|---|
| `contact_check` | start of `FUN_00505CC0`, `0x00505CC6` | Sets the byte at `+0x60` on every call, so every contact gets the check on every step, as wheels already did. The game's own removal does the rest |
| `move_object` | start of `FUN_004F3130`, `0x004F3130`, which all moves of an object go through | Removes the object's contacts with `FUN_004F2910`, the game's own function for when it turns off collisions |
| `reset_unlink` | before the move in the reset, `0x0040E7C0` | Takes the car off the list of its waypoint with `FUN_004A7020`, as the game's own respawn `FUN_0041CAE0` does |
| `reset_done` | stores the time of the reset, `0x0040E818` | Only sets that time when the call came from the Enter key, and stops the rotation of the body. The wheels keep theirs, so a reset feels as it did |
| `reset_next_section`, `reset_previous_section` | step to another section, `0x0040E838` and `0x0040E841` | Wrap around at the ends of the track |
| `reset_height` | adds 20 to the height, `0x0040E7B6` | When the surface is more than 25 units from the lane's own height, uses the lane's height. Not for a lane marked as not for placing cars (flag 4), where the lane can run far under the road, unless no surface was found at all |

A smaller change was tried as well: putting the byte back after the call in `FUN_004F3810`, which brings back the game's own rule at any frame rate. It measured the same in five races. But in `FUN_0053D590` a slow creep under load rewrites the friction spring without setting the byte, for bodies as well as for wheels, so that rule misses a corner that slowly crawls past the end of a triangle, at any frame rate. Checking every time covers that too. What it costs is a few float operations per contact per step. A body that crosses from one triangle to the next loses its contact and sags about 0.09 units before it collides again, which is what the game always did for a body that slides at low frame rates.

`hung_check` stays. A car can also really get caught, with contacts on what it touches, and that now gets it free, as nothing comes along.

### Measurements

Whole races with the same bot, all five cars on the track scanned every 0.25 seconds. "Past its triangle" means a corner or edge of a body more than 12 units from the triangle or edge of its contact. A race can end early when the bot wrecks its car, as it doesn't avoid anything. Several races ran at once, which is why the frame rates without a limit vary.

| Code | Etappe | Frame rate | Contacts past their triangle, per race | Seconds with a nose above 0.5, all cars together |
|---|---|---|---|---|
| v1.5.0 | 5 | 30 | 0, 2, 1 | 1.5, 12.6, 7.2 |
| v1.5.0 | 5 | 51 | 0, 0, 0 | 2.7, 7.1, 9.5 |
| v1.5.0 | 5 | 60 | 3 | 14.4 |
| v1.5.0 | 5 | 114 | 21 | 3.4 |
| v1.5.0 | 5 | 238 | 26, 26 | 17.8, 83.3 |
| v1.5.0 | 4 | 137 | 30 | 29.7 |
| this patch | 5 | 30 | 0 | 9.5 |
| this patch | 5 | 51 | 0, 0 | 6.2, 11.2 |
| this patch | 5 | 60 | 0 | 19.5 |
| this patch | 5 | 122 to 146 | 0, 0, 0 | 10.6, 7.4, 9.7 |
| this patch | 0, 1, 2, 3, 4, 4, 6, 7, 8 | 101 to 127 | 0 on every one | 7 to 39 |

The contacts tell the story. The time with a nose up mostly comes from hits, which the bot has plenty of: most of what remains is the car running into traffic or riding up onto a truck at full speed, and it says more about the bot than about the physics. The 38 seconds on etappe 4 are its fourth racer, which drives back and forth across the road near the start for the whole race. It does the same on v1.5.0.

Tests with a test build that can place a car, under Wine:

| Test | v1.5.0 | This patch |
|---|---|---|
| On its back on a flat bridge deck for 0.4 s, then moved to the spot of the stuck car, three times | Nose down at forward y -0.4, rear in the air, the state of the stuck car. `hung_check` fires and it comes back the same at sections 245 and 244 | Lands flat on all four wheels every time, no `hung_check` |
| The ramp of part 11, gas held, three drives, without `hung_check` | Hangs at y = 19 on a contact 10 units past its triangle; next caught on a part at y = 15, then on its roof | Drives past the ramp, three times |
| In those drives, samples of a body contact that presses while more than 1 unit from its triangle | 169 of 732, up to 191 units away | 0 of 323 |
| Drive through section 247 of etappe 5 with the gas held, where the car stood up nearly vertical | Nearly vertical at y = 105 | Drives on |
| Enter right after a reset of a racer | Ignored | Works |
| Waypoint entries of cars that are elsewhere, after 2 resets of the player and 2 of a racer | 4 | 0 |
| Reset at the last section, with its lanes marked as taken | `Illegal chunk: 327`, the game stops | Lands on section 0, the race goes on. Also in reverse |
| Reset at sections 296 and 305 of etappe 5 | Lands at y = 1.4 and 0.2, under the road | Lands on the road, at y = 93 and 81 |
| Reset at section 15 of etappe 7 | Not run; the track file gives y = 449 above the tunnel | Lands at y = 74 |
| Moving the player on and off moving cars, and resetting it and the racers while touching, 935 times, 126 of them with the body touching something | | No crash and no error |
| On its roof, pushed sideways across triangles for 5 s, changes in the body's contacts | 15 | 17 |


### What this doesn't establish

- The numbers are from Wine with software rendering, a bot and test placements. The stuck car itself ran under Wine at 165 FPS. This part was released before anyone played it on real hardware. The author then tested the v1.5.2 test build, which includes it, in-game.
- How the green car came to touch that triangle isn't known: the game was stopped after it happened. That triangle is about 400 units from the road, and the moves before the pause weren't logged.
- The frame rates of the PCs of the time aren't known, so why this went unnoticed then is inferred.
- A frontal hit still lifts the nose, and a car can land on its roof or on another car. These were all seen in the races, with contacts that really touch.
- A car with both axles on something, like pressed against a wall, still doesn't count as hung. Enter works for those, and racers reverse out by themselves.
- `hung_check` also runs after the finish and during an arrest, so a car lying on its roof by then gets put back as well.

## Patch part 13: what still counted frames

Parts 9 and 12 took the frame rate out of the car physics. For this part the whole of `spel.dat` was read again for anything else that depends on it, in two ways:

- Every reader of the time step, every `__ftol`, every use of the tick clock and of `rand`, every value that updates itself without a time step and every object handler. Each finding was then checked by a second, independent read of the code.
- The game ran at exact limits of 30, 60, 120 and 240 FPS, with every value in its memory compared, to catch what reading misses.

### What was already fine

World time, steering, gas and brake ramps, racer and traffic speed, gears, wheel forces, laps, the race clock, money, game over and arrest timers, engine and skid sounds, the speedometer and the fixed-step physics. Steering from -100 to +100 took 3.01 s, gas from 0 to 100 1.33 s and the brake from 0 to 100 1.8 s at all four limits, and world time matched the clock at all of them.

Positions don't judder above 66 FPS either: the world interpolates them between physics steps. The trailer code can't be reached: nothing calls or points at `FUN_00431320`, so `trailer_push` and `trailer_fade` from part 9 never run. They do no harm and stayed in.

### What wasn't

| What | Where | What the game does | Result |
|---|---|---|---|
| Police brake | `FUN_00407D90`, `FUN_00407ED0`, `FUN_00408030`, `FUN_00408E10` | `FUN_004037A0` sets the brake to 0, then these add `dt × 400` (or 200) in the same frame, so the brake is one frame's amount | 13.3 at 30 FPS, 2.4 at 165: a chasing car hardly slows down, and runs into or past its target. On the six stages with police |
| Supercop reverse | `FUN_0041F5E0` at `0x0041F7F9`, `FUN_004200E0` at `0x004204B3` | `pedal = dt × 800`, not added up | 26.7 at 30 FPS, 4.85 at 165: from about 120 FPS it gives up on getting free after 1 second. Stages 1, 3 and 4 |
| Supercop patrol | `FUN_004060D0` | Gas ±1 per frame | From full gas to none takes 3.3 s at 30 FPS, 0.6 s at 165 |
| Chase camera | `FUN_004B1380` at `0x004B195F`, `0x004B1974`, `0x004B198D` | Moves a fixed part of the way per frame, with no time step | Vertical time constant 0.32 s at 30 FPS, 0.06 s at 165: it sits closer at speed and passes on every bump |
| Car lighting | `FUN_004A8200` | `c = (int)(c + (road - c) × dt × k)` per color channel | A step below 1 does nothing going up and loses a whole level going down. A car stays up to 165 levels too dark at 165 FPS when standing, 41 when driving |
| Skid mark length | `FUN_00444D20` | One section per frame, up to 48 | 1.6 s at 30 FPS, 0.29 s at 165, and the rest of a long slide leaves nothing |
| Skid mark fade | `FUN_00444F80` | At least 1 alpha per frame | Gone in 1.8 to 5 s at 30 FPS, 0.33 to 0.92 s at 165 |
| Smoke fade | `FUN_00446730`, `FUN_0043D8F0` | At least 1 alpha per frame, while the size follows time | Visible for 4 s at 30 FPS, 0.8 s at 165, at a quarter of the size |
| Smoke drift | `FUN_004467F0`, `FUN_0043D970` | Speed × `min(0.99, dt × 15)` per frame (20 for damage smoke): the time step the wrong way around | Moves 0.67 times the car's speed at 30 FPS, 0.067 at 165. At 15 FPS or below it keeps going and shoots far ahead of the car |
| Mud and water | `FUN_00451DD0`, `FUN_004553B0` | 4 new particle systems per frame in a zone, with no time limit | The room for 100 systems is full in 0.83 s at 30 FPS, 0.15 s at 165, and then sparks and debris get refused too. Stages 2, 5, 7 and 8 |
| Pickup spin | `FUN_00451380` | `PerSecToPerFrame(600)` in its script runs while loading, when the time step is still a default of 0.1, and gives 60 units per frame | 1.8 turns per second at 30 FPS, 9.7 at 165 |
| Pickup shrink | `bonus.dso` `DoDefault_OnFadeout` | Size × 0.6 per frame | Takes 0.2 s at 30 FPS, 0.036 s at 165 |
| Animated objects | `FUN_00469C60` | A step waits a frame longer than its time and loses what it went over | A 50 ms frame shows for 100 ms at 30 FPS and 61 ms at 165 |
| Debris spin | `FUN_0045AF90`, `FUN_0045C660`, `FUN_0045CF30`, `FUN_00461150`, `FUN_00462300` | Adds a random 0.1 radians on average per frame, on each axis | 3 rad/s at 30 FPS, 16.5 at 165 |
| Letters | `FUN_0045CCA0` | Speed × 0.99 per frame | 74% left after a second at 30 FPS, 19% at 165. Stage 4 |
| Speed camera flash | `FUN_0043B130` | Lasts one frame | 33 ms at 30 FPS, 4 ms at 240. Without vertical sync that can miss the screen altogether |
| Portrait outline | `FUN_00493D00` | Truncates its step | Peaks at 254 at 30 FPS, 227 at 165, and stops pulsing above 212 FPS |
| Turbo tank | `FUN_0044E970` | One unit per at least 100 ms, rounded up to a whole frame and to the tick of `GetTickCount` | Worked out for ticks of 15.6 ms: 12.4 s at 30 FPS, 10.8 s at 165 |

The figures in this table come from the code. The measurements are below.

### The fix

Most of these get what they did at 25 FPS, at any rate above that. It's the same rate as `frame_share` in part 9. The game doesn't say what it was tuned for. Below 25 FPS a frame stands for a whole step, as it always did.

| Hook | Used by | What it does |
|---|---|---|
| `TICK`, in `frame_limit` | `skid_section`, `skid_fade`, `tyre_smoke_fade`, `damage_smoke_fade`, `mud_spray`, `water_spray`, `pickup_fade`, `animation_step` | Adds up the time step per frame and sets a byte in frames where 0.04 s has passed. Those calls run only in such a frame, so they run 25 times per second. Below 25 FPS that's every frame |
| `frame_share` | `camera_damping`, `patrol_step`, `pickup_spin`, `particle_spin`, `mail_drift`, `police_brake` | `min(1, dt × 25)`, from part 9 |
| `long_step` | The Supercop's pedal, the rise of smoke, the time inside `animation_step` | `max(dt, 0.04)` |
| `camera_damping` | | Replaces a debug print at `0x004B18D4`. Works out `k × s / (1 - k + k × s)` for each axis, with `s` from `frame_share`, and the three FMULs read those. That keeps the distance the camera lags behind a car at a steady speed the same at any rate, which `1 - (1 - k)^s` wouldn't |
| `color_round` | Car lighting and the portrait outline | Adds a different part of a level before the conversion, each time, from a sequence with even spread. A step of 0.3 then goes through 3 times out of 10, going up or down. It needs no room per car, and it can't pass the target |
| `police_brake` | | The brake becomes at least what a frame at 25 FPS would add: 16, or 8 at `0x00408ECC`. Where the brake does add up, it goes on doing so |
| `smoke_drift_tyre`, `smoke_drift_damage` | | Multiply by `1 - 10 × dt` and `1 - 5 × dt`, equal at 25 FPS. Smoke then travels as far at any rate, also below 25 FPS |
| `turbo_stamp` | | Keeps what a unit went over 100 ms, unless the key has been up. A tank takes 10 s at any rate, the time the game's own number gives |
| `flash_done` | | The flash goes on until 0.04 s has passed |

What this means for the camera: at speed it sits about as far back as at 25 FPS, and it follows softly. Anyone used to the game at a high frame rate sees a camera that lags more than they knew.

### Measurements

Under Wine with software rendering at 640x480, with the same bot, on stage 5 unless noted. The bot's route differs between runs, so car lighting, smoke drift and turbo are rough. Another job kept the machine busy during these runs, so the runs with a limit of 60 and 240 FPS reached the rates given.

| Measure | 15 FPS | 30 FPS | About 48 FPS | About 61 FPS |
|---|---|---|---|---|
| Camera distance at speed 30, before | 84.2 | 77.4 | 73.7 | 72.3 |
| The same, after | 84.0 | 78.3 | 77.9 | 78.9 |
| Pickup spin in units per second, before | 900 | 1780 | 2615 | 3185 |
| The same, after | 900 | 1503 | 1489 | 1542 |
| Steps per second of an animated object, before | 6.7 | 11.7 | 15.7 | 17.4 |
| The same, after | 6.7 | 10.2 | 10.1 | 10.1 |
| Vertices added to a skid mark per second, before | | 61 | 81 | 115 |
| The same, after | | 54 | 55 | 42 |
| Seconds until a skid mark at alpha 192 is gone, before | 3.6 | 1.8 | 0.9 | 0.8 |
| The same, after | 3.6 | 2.2 | 2.1 | 2.2 |
| Alpha of tyre smoke of 1 to 2 s old, before | 86 | 85 | 54 | 37 |
| The same, after | 86 | 92 | 91 | 82 |
| How far a puff of tyre smoke moved, before | 653 | 3.4 | 1.9 | 0.5 |
| The same, after | 5.5 | 19 | 14 | 14 |
| Player's color, mean of red, green and blue, before | 211 | 195 | 189 | 152 |
| The same, after | 217 | 209 | 211 | 201 |

A later run on a less busy machine reached 98 FPS before and after: pickups spun at 4328 units per second before and 1503 after, and animated objects took 19.7 steps per second before and 10.2 after.

The camera distance is corrected for the one frame between the game moving the car and moving the camera, which a reading between frames sees. Without that a slower frame rate looks about 6 units further away than it is.

On stage 1:

| Measure | Before | After |
|---|---|---|
| Median brake of chasing police | 13.3 at 30 FPS, 7.9 at 50, 7.2 at 55 | 16.0 at 30, 57, 60 and 59 FPS |
| Mean reverse pedal of the Supercop | 14.2 at 55 FPS | 30.1 at 30 FPS, 31.5 at 59 |

A full turbo tank with the bot holding the key, worked out from how fast it drains: 10.6 s, 11.8, 11.0 and 11.0 before, 10.0, 10.0, 10.2 and 10.0 after, at 30 and at 46 to 50 FPS. `GetTickCount` steps by 1 ms under Wine, so the larger difference in the table above doesn't show here.

The new code also ran on all nine stages at 48 to 75 FPS for 60 seconds each, with no error, and it passed mud, water, pickups and speed cameras there.

### Left as it is

- `FUN_004AA0C0` steps the world by the mean time step of the last 50 frames. It has no lasting error, but after a sudden change in frame rate the world runs at another pace for a moment: from 165 to 60 FPS it starts at 36% and is back after 0.8 s.
- Path objects such as planes and helicopters take their number of frames from the time step when they start, the form part 9 calls fine. A slow frame at exactly that moment makes one run too fast. Rare, and only looks.
- The number of particles in a system falls with the time step, at 4 per dirt system at 30 FPS and 13 at 165. It's the game's own rule for slow PCs, and more isn't worse.
- Traffic comes back with a chance of 20% per frame, but the rules for free space decide nearly everything. Below 15 FPS on the smoothed time step it doesn't come back, as the game intends.
- The alert lamp of a Supercop goes off 14 frames after it leaves: 0.47 s at 30 FPS, 0.085 s at 165.
- Police lights, the helicopter rotor, the game over orbit and the finish flag use whole steps, with at most a few percent of difference.
- The 60 ms wait between damage from hits uses the real time, so below about 17 FPS sustained contact can do damage every frame.

### What this doesn't establish

- The numbers are from Wine with software rendering, with a bot. The author tested the build in-game before the release, without these measurements.
- With the machine busy nothing above 98 FPS could be measured for this part. Each of these fixes follows from the time step or the tick, so nothing depends on the rate above 25 FPS, but that is inferred for 120 to 240 FPS.
- The damage smoke wasn't seen in these runs: the numbers above are for tyre smoke, and the damage smoke takes the same route with other constants.
- Whether 25 FPS is how the game was meant to look isn't known. It's the one rate the game's own code points at.

## All added and changed bytes

The added code is built from [`A2Racer4Fixes_source/spel_patch.asm`](A2Racer4Fixes_source/spel_patch.asm). It goes in unused space at the end of `.text`, file offset `0x175500`, VA `0x00575500`, and the section's virtual size is raised so that space is certainly mapped. That space must be all zero before patching. A `spel.dat` from v1.2.0 has older code there, so the patcher starts from the copy in `4x3_backup` in that case.

2728 bytes at `0x175500`:

```text
83 7C 24 04 03 75 60 A1 26 B8 73 00 83 F8 FF 74 56 69 C0 B0 00 00 00 03
05 D8 B7 73 00 83 78 54 10 75 44 C7 44 24 04 04 00 00 00 6A 00 6A 18 A1
B4 B4 73 00 50 8B 08 FF 51 5C 6A 05 6A 19 A1 B4 B4 73 00 50 8B 08 FF 51
5C 6A 01 6A 0F A1 B4 B4 73 00 50 8B 08 FF 51 5C 6A 00 6A 29 A1 B4 B4 73
00 50 8B 08 FF 51 5C B8 90 2B 4C 00 FF E0 01 F0 5E 5B EB 04 5B 01 F0 5E
85 C0 74 06 0B 05 A8 09 74 00 C3 BA 01 00 00 00 EB 0C 8B 54 24 0C 85 D2
0F 94 C2 0F B6 D2 52 FF 74 24 10 6A 1B FF 74 24 10 8B 04 24 8B 08 FF 51
5C 5A 50 A1 2E B8 73 00 3B 05 26 B8 73 00 75 35 52 6A 0F FF 74 24 10 8B
04 24 8B 08 FF 51 5C 83 3D 05 B5 73 00 02 75 1D 8B 44 24 10 F7 D8 19 C0
83 E0 02 83 C0 02 50 6A 15 FF 74 24 10 8B 04 24 8B 08 FF 51 5C 58 C2 0C
00 A1 2E B8 73 00 3B 05 26 B8 73 00 75 4A 50 54 6A 0F A1 B4 B4 73 00 50
8B 08 FF 51 58 6A 00 6A 0F A1 B4 B4 73 00 50 8B 08 FF 51 5C FF 74 24 14
FF 74 24 14 FF 74 24 14 FF 74 24 14 8B 04 24 8B 08 FF 51 30 5A 50 52 6A
0F A1 B4 B4 73 00 50 8B 08 FF 51 5C 58 C2 10 00 8B 44 24 04 8B 08 FF 61
30 60 68 DF 5E 57 00 FF 15 A0 60 57 00 89 C6 85 F6 74 12 68 FF 5E 57 00
56 FF 15 FC 60 57 00 85 C0 74 02 FF D0 8B 1D A8 5F 57 00 8B 2D AC 5F 57
00 85 DB 75 61 81 EC 9C 00 00 00 89 E7 B9 27 00 00 00 31 C0 F3 AB 66 C7
44 24 24 9C 00 85 F6 74 2B 68 EA 5E 57 00 56 FF 15 FC 60 57 00 85 C0 74
1B 54 6A FF 6A 00 FF D0 85 C0 74 10 8B 5C 24 6C 8B 6C 24 70 85 DB 74 04
85 ED 75 14 6A 00 FF 15 F4 61 57 00 89 C3 6A 01 FF 15 F4 61 57 00 89 C5
81 C4 9C 00 00 00 BE 78 5F 57 00 B9 0C 00 00 00 AD 89 18 89 68 04 E2 F8
8D 04 AD 01 00 00 00 31 D2 B9 03 00 00 00 F7 F1 A3 38 1F 75 00 61 E9 CD
29 EE FF 50 A1 98 37 5B 00 8D 04 40 50 DB 04 24 A1 9C 37 5B 00 C1 E0 02
89 04 24 DA 34 24 58 D9 C0 D9 E0 D9 5E 14 DC C0 D9 5E 1C 58 C3 FF 74 24
0C FF 74 24 0C FF 74 24 0C E8 22 B8 F0 FF 84 C0 74 2D 50 8B 44 24 08 8B
40 04 85 C0 74 20 E8 4F 00 00 00 85 C0 74 17 50 E8 15 00 00 00 59 0F AF
C1 50 DB 04 24 58 8B 4C 24 10 D8 01 D9 19 58 C2 0C 00 A1 98 37 5B 00 8D
04 40 8B 0D 9C 37 5B 00 8D 14 8D 00 00 00 00 29 D0 69 C0 40 1F 00 00 6B
C9 63 89 CA D1 EA 85 C0 79 02 F7 DA 01 D0 99 F7 F9 C3 56 57 89 C6 83 EC
40 89 E2 6A 40 52 68 34 A0 5A 00 56 E8 47 E5 F4 FF 83 C4 10 89 E0 BF 12
5F 57 00 E8 6A 00 00 00 74 58 89 F0 BF 2B 5F 57 00 E8 5C 00 00 00 74 4A
89 F0 BF 42 5F 57 00 E8 4E 00 00 00 74 3C 89 F0 BF 51 5F 57 00 E8 40 00
00 00 74 2E 89 E0 BF 1E 5F 57 00 E8 32 00 00 00 74 27 89 F0 BF 60 5F 57
00 E8 2F 00 00 00 74 19 89 F0 BF 6F 5F 57 00 E8 21 00 00 00 74 0B 31 C0
EB 0A B8 01 00 00 00 EB 03 83 C8 FF 83 C4 40 5F 5E C3 E8 06 00 00 00 75
03 80 38 00 C3 57 8A 0F 84 C9 74 17 8A 28 80 FD 61 72 08 80 FD 7A 77 03
80 ED 20 38 CD 75 04 40 47 EB E3 5F C3 56 8B 74 24 0C FF 15 AC 60 57 00
3C 06 72 27 C7 46 18 18 00 00 00 E8 24 00 00 00 85 C0 74 1C C7 46 18 20
00 00 00 E8 14 00 00 00 85 C0 74 0C C7 46 18 10 00 00 00 E8 04 00 00 00
5E C2 10 00 FF 74 24 18 FF 74 24 18 FF 74 24 18 FF 74 24 18 8B 04 24 8B
08 FF 51 18 C3 FF 74 24 04 FF 15 58 60 57 00 85 C0 74 3B 8B 4C 24 04 A1
10 1F 75 00 0B 05 14 1F 75 00 75 0F 8B 01 A3 10 1F 75 00 8B 41 04 A3 14
1F 75 00 8B 01 8B 51 04 2B 05 10 1F 75 00 1B 15 14 1F 75 00 89 01 89 51
04 B8 01 00 00 00 C2 04 00 FF 15 50 62 57 00 83 3D 1C 1F 75 00 00 75 0F
A3 18 1F 75 00 C7 05 1C 1F 75 00 01 00 00 00 2B 05 18 1F 75 00 C3 D9 C0
DC 25 20 1F 75 00 D8 76 04 D9 5E 0C DD 15 20 1F 75 00 D8 76 04 D9 5E 08
C3 D9 44 24 04 8B 44 24 04 89 41 78 DC 05 28 1F 75 00 DD 15 28 1F 75 00
D9 51 74 83 EC 08 DD 1C 24 8B 49 14 B8 80 83 4F 00 FF D0 C2 04 00 50 51
B9 B0 28 71 00 B8 00 68 4A 00 FF D0 D8 0D BB 5E 57 00 D9 E8 D8 D1 DF E0
9E 73 02 D9 C9 DD D8 59 58 C3 D8 3D 18 63 57 00 E8 D1 FF FF FF DE C9 C3
E8 C9 FF FF FF D9 C0 D8 4C 24 04 D9 5C 24 04 D9 C0 D8 4C 24 08 D9 5C 24
08 D8 4C 24 0C D9 5C 24 0C 56 89 CE 8B 46 10 68 F6 97 4A 00 C3 89 44 24
10 D9 44 24 0C D9 E0 D8 81 84 00 00 00 D9 99 84 00 00 00 D9 44 24 08 D8
81 80 00 00 00 D9 99 80 00 00 00 D9 44 24 10 D8 81 88 00 00 00 D9 99 88
00 00 00 68 BE 5C 4A 00 C3 51 B8 80 96 4F 00 FF D0 59 31 C0 89 01 89 41
04 89 41 08 C3 B9 30 1F 75 00 EB 05 B9 34 1F 75 00 D8 01 D9 C0 B8 24 85
55 00 FF D0 50 DA 24 24 58 D9 19 C3 51 B9 3C 1F 75 00 E8 E2 FF FF FF 59
C3 FF 15 AC 60 57 00 8B 15 A0 37 5B 00 83 FA 10 75 09 3C 06 72 05 BA 20
00 00 00 C3 8B 44 24 5C 83 78 0C 20 74 19 FF 74 24 08 FF 74 24 08 E8 25
27 F5 FF 83 C4 08 66 89 07 83 C7 02 C2 08 00 FF 74 24 04 E8 40 24 F5 FF
83 C4 04 89 07 83 C7 04 C2 08 00 FF 74 24 04 B8 70 31 40 00 FF D0 60 8B
74 24 24 31 D2 31 C9 8B 44 8E 34 8B 40 08 83 78 28 00 74 07 89 C8 D1 E8
40 09 C2 41 83 F9 04 72 E6 89 D7 89 E8 2D 7C EA 5C 00 31 D2 B9 94 02 00
00 F7 F1 83 F8 13 72 05 B8 13 00 00 00 8D 34 85 40 1F 75 00 8B 0D 50 5E
71 00 01 D9 D9 81 BC 00 00 00 DC C8 D9 81 C0 00 00 00 DC C8 DE C1 D9 81
C4 00 00 00 DC C8 DE C1 D8 1D CF 5E 57 00 DF E0 9E 73 5F 83 FF 03 75 1D
8B 41 24 69 C0 A9 00 00 00 03 05 D0 B0 73 00 D9 40 24 D8 1D D3 5E 57 00
DF E0 9E 73 3D B9 B0 28 71 00 B8 00 68 4A 00 FF D0 D8 06 D9 16 D8 1D D7
5E 57 00 DF E0 9E 72 28 6A 00 8B 0D 50 5E 71 00 FF 74 19 34 89 D8 31 D2
B9 F0 00 00 00 F7 F1 50 B8 A0 E5 40 00 FF D0 83 C4 0C C7 06 00 00 00 00
61 C2 04 00 C6 41 60 01 81 EC B0 00 00 00 E9 29 01 F9 FF 51 6A 01 B8 10
29 4F 00 FF D0 59 81 EC D8 00 00 00 E9 7D D5 F7 FF D9 C0 D8 64 24 40 D9
E1 D8 1D DB 5E 57 00 DF E0 9E 76 21 D9 EE D8 D9 DF E0 9E 74 12 8B 44 24
6C 6B C0 50 03 05 B8 5E 71 00 F6 00 04 75 06 DD D8 D9 44 24 40 D8 05 10
63 57 00 C3 52 8B 44 3A 3C 85 C0 78 1E 3B 05 BC 5E 71 00 7F 16 89 F8 31
D2 B9 F0 00 00 00 F7 F1 50 B8 20 70 4A 00 FF D0 83 C4 04 5A 8B 4C 3A 10
8D 54 24 48 C3 A1 50 5E 71 00 8B 44 38 10 8B 40 08 8B 80 A4 00 00 00 31
D2 89 90 94 00 00 00 89 90 98 00 00 00 89 90 9C 00 00 00 89 50 74 89 50
78 89 50 7C 89 90 84 00 00 00 89 90 88 00 00 00 89 90 8C 00 00 00 81 7C
24 60 0A D7 44 00 75 07 D9 1D 00 1B 5D 00 C3 DD D8 C3 46 81 C5 94 09 00
00 3B 35 04 5F 71 00 7C 04 31 F6 31 ED C3 4E 81 ED 94 09 00 00 79 0D 8B
35 04 5F 71 00 4E 69 EE 94 09 00 00 C3 E8 D4 FC FF FF 31 C9 D9 E8 D8 A4
8D 88 00 00 00 D9 84 8D 88 00 00 00 D8 CA DC C1 DE F1 D9 1C 8D 98 1F 75
00 41 83 F9 03 72 DD DD D8 C3 A1 A4 1F 75 00 05 B9 79 37 9E A3 A4 1F 75
00 C1 E8 10 50 DB 04 24 58 D8 0D C3 5E 57 00 DE C1 E9 2E 28 FE FF B8 20
4D 44 00 EB 21 B8 80 4F 44 00 EB 1A B8 30 67 44 00 EB 13 B8 F0 D8 43 00
EB 0C B8 70 B6 45 00 EB 05 B8 D0 B9 45 00 80 3D 90 1F 75 00 00 74 02 FF
E0 C3 80 3D 90 1F 75 00 00 0F 85 D9 22 F0 FF C2 08 00 80 3D 90 1F 75 00
00 0F 85 19 3F EF FF 31 C0 C2 04 00 E8 AF 0A F3 FF D8 15 BF 5E 57 00 DF
E0 9E 73 08 DD D8 D9 05 BF 5E 57 00 C3 E8 96 0A F3 FF D8 0D 58 63 57 00
EB 0B E8 89 0A F3 FF D8 0D 08 63 57 00 D9 E8 DE E1 C3 E8 F7 FB FF FF D8
7C 24 04 D8 61 04 D8 54 24 04 DF E0 9E 76 04 D9 54 24 04 DD D8 E9 DE D0
E8 FF E8 D7 FB FF FF D8 4B 30 51 D9 1C 24 59 8B 53 28 C3 D9 81 CC 00 00
00 E8 C0 FB FF FF DE C9 DE C1 C3 FF 74 24 08 FF 74 24 08 E8 10 A5 EE FF
83 C4 08 E8 A6 FB FF FF DE C9 C3 E8 9E FB FF FF D8 0D C7 5E 57 00 D9 E8
DE E1 DE C9 C3 81 F9 C8 00 00 00 73 03 8D 42 64 A3 40 BA 6F 00 C3 B9 B0
28 71 00 E8 F8 09 F3 FF D8 05 A8 1F 75 00 D9 15 A8 1F 75 00 D8 1D BF 5E
57 00 DF E0 9E 0F 93 C0 0F B6 C0 72 07 83 25 A8 1F 75 00 00 C3 83 39 00
74 46 51 83 EC 08 54 FF 15 58 60 57 00 8B 4C 24 08 DF 2C 24 DF 2D 00 1F
75 00 DE E9 D8 71 04 D8 1D CB 5E 57 00 DF E0 9E 73 11 A1 00 1F 75 00 0B
05 04 1F 75 00 74 04 F3 90 EB CB 58 A3 00 1F 75 00 58 A3 04 1F 75 00 59
E8 83 08 F3 FF B9 B0 28 71 00 E8 79 09 F3 FF D8 05 94 1F 75 00 D8 15 BF
5E 57 00 DF E0 9E 0F 93 05 90 1F 75 00 72 15 D8 25 BF 5E 57 00 D8 15 BF
5E 57 00 DF E0 9E 72 04 DD D8 D9 EE D9 1D 94 1F 75 00 C3 00 00 C8 41 0A
D7 23 3D 00 00 80 37 0A D7 23 3C 89 88 88 3B 00 00 10 40 00 00 00 3F 00
00 40 40 00 00 C8 41 55 53 45 52 33 32 2E 44 4C 4C 00 45 6E 75 6D 44 69
73 70 6C 61 79 53 65 74 74 69 6E 67 73 41 00 53 65 74 50 72 6F 63 65 73
73 44 50 49 41 77 61 72 65 00 53 50 45 45 44 4F 4D 45 54 45 52 00 43 4F
4D 4D 55 4E 49 43 41 54 4F 52 00 53 54 52 49 4E 47 5F 52 41 43 45 5F 54
49 4D 45 5F 56 41 4C 55 45 00 53 54 52 49 4E 47 5F 43 55 52 5F 4C 41 50
00 53 54 52 49 4E 47 5F 43 55 52 5F 50 4F 53 00 4F 56 4C 5F 50 4F 52 54
52 41 49 54 53 5F 00 50 4C 41 59 45 52 5F 00 90 98 37 5B 00 EC 37 5B 00
00 38 5B 00 14 38 5B 00 64 38 5B 00 78 38 5B 00 8C 38 5B 00 A0 38 5B 00
B4 38 5B 00 04 39 5B 00 18 39 5B 00 2C 39 5B 00
```

After it, at `0x175FA8`, come two 32-bit values: a fixed width and height, or `0` and `0` to follow the display.

| File offset | Original | Patched | What |
|---|---|---|---|
| `0x0582AA` | `E8 31 FE FF FF` | `E8 A2 D3 11 00` | startup call |
| `0x07FDCF` | `E8 9C 11 00 00` | `E8 69 59 0F 00` | HUD position read |
| `0x07FF43` | `E8 28 10 00 00` | `E8 F5 57 0F 00` | HUD position read |
| `0x080610` | `E8 5B 09 00 00` | `E8 28 51 0F 00` | HUD position read |
| `0x0C287D` | `8E` | `8D` | alpha format choice |
| `0x0C058A` | `E8 01 26 00 00` | `E8 71 4F 0B 00` | texture format choice |
| `0x0C7FF9` | `03 C6 5E 5B C3` | `E9 70 D5 0A 00` | 24-bit color conversion |
| `0x0C82C9` | `5B 03 C6 5E C3` | `E9 A6 D2 0A 00` | palette color conversion |
| `0x03DEF9` | `8B 08 FF 51 5C` | `E8 85 76 13 00` | alpha blend switch |
| `0x03E04A` | `8B 08 FF 51 5C` | `E8 34 75 13 00` | alpha blend switch |
| `0x040224` | `8B 08 FF 51 5C` | `E8 5A 53 13 00` | alpha blend switch |
| `0x04031A` | `8B 10 FF 52 5C` | `E8 64 52 13 00` | alpha blend switch |
| `0x04275C` | `8B 08 FF 51 5C` | `E8 29 2E 13 00` | alpha blend switch |
| `0x042B4E` | `8B 08 FF 51 5C` | `E8 30 2A 13 00` | alpha blend switch |
| `0x043D8E` | `8B 10 FF 52 5C` | `E8 F0 17 13 00` | alpha blend switch |
| `0x043E9C` | `8B 10 FF 52 5C` | `E8 E2 16 13 00` | alpha blend switch |
| `0x04523A` | `8B 08 FF 51 5C` | `E8 4B 03 13 00` | alpha blend switch |
| `0x0453F9` | `8B 10 FF 52 5C` | `E8 85 01 13 00` | alpha blend switch |
| `0x0470C3` | `8B 08 FF 51 5C` | `E8 BB E4 12 00` | alpha blend switch |
| `0x047276` | `8B 10 FF 52 5C` | `E8 08 E3 12 00` | alpha blend switch |
| `0x05DD24` | `8B 08 FF 51 5C` | `E8 5A 78 11 00` | alpha blend switch |
| `0x05DD98` | `8B 10 FF 52 5C` | `E8 E6 77 11 00` | alpha blend switch |
| `0x085F29` | `8B 08 FF 51 5C` | `E8 55 F6 0E 00` | alpha blend switch |
| `0x08614A` | `8B 08 FF 51 5C` | `E8 34 F4 0E 00` | alpha blend switch |
| `0x0B5E4D` | `8B 08 50 FF 51 5C` | `50 E8 37 F7 0B 00` | alpha blend switch |
| `0x0B5E6C` | `8B 10 50 FF 52 5C` | `50 E8 11 F7 0B 00` | alpha blend switch |
| `0x0C0F80` | `8B 11 50 6A 01 51 FF 52 30` | `50 6A 01 51 E8 68 46 0B 00` | viewport clear |
| `0x0C0679` | `8B 08 52 50 FF 51 18` | `52 50 E8 ED 51 0B 00` | Z-buffer creation |
| `0x0A6710` | `FF 15 58 60 57 00` | `E8 B0 F1 0C 00 90` | timer counter |
| `0x0A6850` | `FF 15 58 60 57 00` | `E8 70 F0 0C 00 90` | timer counter |
| `0x0A673B` | `FF 15 50 62 57 00` | `E8 D1 F1 0C 00 90` | timer ticks |
| `0x0A687E` | `FF 15 50 62 57 00` | `E8 8E F0 0C 00 90` | timer ticks |
| `0x04CB9E` | `E8 5D 9B 05 00` | `E8 8A 92 12 00` | frame limit |
| `0x0A6751` | `D8 76 04 D9 C0 D8 66` | `E8 E0 F1 0C 00 EB 07` | timer step |
| `0x0A6894` | `D8 76 04 D9 C0 D8 66` | `E8 9D F0 0C 00 EB 07` | timer step |
| `0x0A45D0` | `D9 44 24 04 D8` | `E9 7C 13 0D 00` | world time |
| `0x02898F` | `D8 3D 18 63 57 00` | `E8 0E D0 14 00 90` | traffic mass |
| `0x016002` | `D8 3D 18 63 57 00` | `E8 9B F9 15 00 90` | traffic mass |
| `0x0A97F0` | `56 8B F1 8B 46 10` | `E9 BB C1 0C 00 90` | trailer push |
| `0x0A5C9E` | `D9 44 24 0C 8B` | `E9 3A FD 0C 00` | driving force |
| `0x0A5D9C` | `E8 DF 38 05 00` | `E8 78 FC 0C 00` | driving force |
| `0x06F2C6` | `E8 59 92 0E 00` | `E8 62 67 10 00` | gas pedal |
| `0x06F308` | `E8 17 92 0E 00` | `E8 27 67 10 00` | brake pedal |
| `0x030F36` | `E8 E9 75 12 00` | `E8 11 4B 14 00` | trailer fade |
| `0x030F5D` | `E8 C2 75 12 00` | `E8 EA 4A 14 00` | trailer fade |
| `0x030FA4` | `E8 7B 75 12 00` | `E8 A3 4A 14 00` | trailer fade |
| `0x0310E6` | `E8 39 74 12 00` | `E8 61 49 14 00` | trailer fade |
| `0x0C58AB` | `8B 15 A0 37 5B 00` | `E8 A9 01 0B 00 90` | display depth |
| `0x0C03C0` | `E8 EB 7D 00 00 83 C4` | `E8 AF 56 0B 00 EB 07` | image pixel |
| `0x028F30` | `E8 3B A2 FD FF` | `E8 76 CB 14 00` | hung car |
| `0x105CC6` | `81 EC B0 00 00 00` | `E9 C9 FE 06 00 90` | contact check |
| `0x0F3130` | `81 EC D8 00 00 00` | `E9 6E 2A 08 00 90` | object move |
| `0x00E7C0` | `8B 4C 17 10 8D 54 24 44` | `E8 2F 74 16 00 90 90 90` | reset waypoint |
| `0x00E818` | `D9 1D 00 1B 5D 00` | `E8 08 74 16 00 90` | reset time and rotation |
| `0x00E838` | `46 81 C5 94 09 00 00` | `E8 3D 74 16 00 90 90` | reset next section |
| `0x00E841` | `4E 81 ED 94 09 00 00` | `E8 48 74 16 00 90 90` | reset previous section |
| `0x00E7B6` | `D8 05 10 63 57 00` | `E8 FE 73 16 00 90` | reset height |
| `0x0B18D4` | `E8 C7 26 01 00` | `E8 CC 43 0C 00` | camera damping |
| `0x0B195F` | `D8 8D 88 00 00 00` | `D8 0D 98 1F 75 00` | camera damping |
| `0x0B1974` | `D8 8D 8C 00 00 00` | `D8 0D 9C 1F 75 00` | camera damping |
| `0x0B198D` | `D8 8D 90 00 00 00` | `D8 0D A0 1F 75 00` | camera damping |
| `0x0A83A1` | `E8 7E 01 0B 00` | `E8 2C D9 0C 00` | car lighting |
| `0x0A83B1` | `E8 6E 01 0B 00` | `E8 1C D9 0C 00` | car lighting |
| `0x0A83BD` | `E8 62 01 0B 00` | `E8 10 D9 0C 00` | car lighting |
| `0x093D41` | `E8 DE 47 0C 00` | `E8 8C 1F 0E 00` | portrait outline |
| `0x044EA6` | `E8 75 FE FF FF` | `E8 4B 0E 13 00` | skid mark length |
| `0x04516B` | `E8 10 FE FF FF` | `E8 8D 0B 13 00` | skid mark fade |
| `0x0467E2` | `E8 49 FF FF FF` | `E8 1D F5 12 00` | smoke fade |
| `0x03D962` | `E8 89 FF FF FF` | `E8 A4 83 13 00` | smoke fade |
| `0x04685D` | `E8 9E FF 05 00 D8 0D 90 67 57 00` | `E8 03 F5 12 00 90 90 90 90 90 90` | smoke drift |
| `0x03D9D3` | `E8 28 8E 06 00 D8 0D E4 66 57 00` | `E8 9A 83 13 00 90 90 90 90 90 90` | smoke drift |
| `0x046AC3` | `E8 38 FD 05 00` | `E8 84 F2 12 00` | smoke rise |
| `0x03DB45` | `E8 B6 8C 06 00` | `E8 02 82 13 00` | smoke rise |
| `0x051E0F` | `E8 5C 98 00 00` | `E8 FE 3E 12 00` | mud spray |
| `0x0553EF` | `E8 DC 65 00 00` | `E8 25 09 12 00` | water spray |
| `0x0513DC` | `D8 81 CC 00 00 00` | `E8 D2 49 12 00 90` | pickup spin |
| `0x05153B` | `E8 D0 6A 02 00` | `E8 EA 47 12 00` | pickup fade |
| `0x05366A` | `E8 F1 65 01 00` | `E8 CB 26 12 00` | animation |
| `0x053693` | `E8 C8 65 01 00` | `E8 A2 26 12 00` | animation |
| `0x069D3C` | `E8 BF CA 03 00` | `E8 0B C0 10 00` | animation |
| `0x03B1AE` | `B8 01 00 00 00` | `E8 4B AC 13 00` | speed camera flash |
| `0x007EA4` | `E8 D7 AF FF FF` | `E8 D9 DE 16 00` | police brake |
| `0x007FFE` | `E8 7D AE FF FF` | `E8 7F DD 16 00` | police brake |
| `0x0080EB` | `E8 90 AD FF FF` | `E8 92 DC 16 00` | police brake |
| `0x008ECC` | `E8 AF 9F FF FF` | `E8 B1 CE 16 00` | police brake |
| `0x01F7F9` | `E8 02 70 08 00` | `E8 4E 65 15 00` | Supercop pedal |
| `0x0204B3` | `E8 48 63 08 00` | `E8 94 58 15 00` | Supercop pedal |
| `0x01F29A` | `8B 4B 30 8B 53 28` | `E8 03 6B 15 00 90` | Supercop patrol |
| `0x04E9D5` | `A3 40 BA 6F 00` | `E8 13 74 12 00` | turbo tank |
| `0x05CCE8` | `D8 0D D8 68 57 00` | `E8 EE 90 11 00 90` | mail drift |
| `0x05CCFC` | `D8 0D D8 68 57 00` | `E8 DA 90 11 00 90` | mail drift |
| `0x05B0B1` | `E8 2A 52 00 00` | `E8 0D AD 11 00` | debris spin |
| `0x05B0C6` | `E8 15 52 00 00` | `E8 F8 AC 11 00` | debris spin |
| `0x05B0DB` | `E8 00 52 00 00` | `E8 E3 AC 11 00` | debris spin |
| `0x05C736` | `E8 A5 3B 00 00` | `E8 88 96 11 00` | debris spin |
| `0x05C74B` | `E8 90 3B 00 00` | `E8 73 96 11 00` | debris spin |
| `0x05C760` | `E8 7B 3B 00 00` | `E8 5E 96 11 00` | debris spin |
| `0x05D006` | `E8 D5 32 00 00` | `E8 B8 8D 11 00` | debris spin |
| `0x05D01B` | `E8 C0 32 00 00` | `E8 A3 8D 11 00` | debris spin |
| `0x05D030` | `E8 AB 32 00 00` | `E8 8E 8D 11 00` | debris spin |
| `0x061271` | `E8 6A F0 FF FF` | `E8 4D 4B 11 00` | debris spin |
| `0x061286` | `E8 55 F0 FF FF` | `E8 38 4B 11 00` | debris spin |
| `0x06129B` | `E8 40 F0 FF FF` | `E8 23 4B 11 00` | debris spin |
| `0x062421` | `E8 BA DE FF FF` | `E8 9D 39 11 00` | debris spin |
| `0x062436` | `E8 A5 DE FF FF` | `E8 88 39 11 00` | debris spin |
| `0x06244B` | `E8 90 DE FF FF` | `E8 73 39 11 00` | debris spin |
| `0x000248` | `08 44 1C 00` | `00 50 1C 00` | data section size |
| `0x0001F8` | `4A 44 17 00` | `00 50 17 00` | code section size |
| `0x0CD478` | `68 70` | `EB B6` | CD check |

## Manual patching on Windows

### Recommended tools

Use one or more of:

- HxD
- 010 Editor
- x32dbg
- Ghidra
- IDA Free
- CFF Explorer
- PE-bear

### Step 1: back up the original file

Copy the original file:

```text
spel.dat
```

to something like:

```text
spel_original_backup.dat
```

Never patch the only copy.

### Step 2: confirm it is a PE executable

Open `spel.dat` in CFF Explorer, PE-bear, Ghidra, or a hex editor.

You should see:

```text
MZ
PE
```

This confirms that the `.dat` file is really a Windows executable.

### Step 3: add the code

Write the code and the two zero values from [All added and changed bytes](#all-added-and-changed-bytes) at file offset `0x175500`, and apply every row of the table there. This covers the startup code, the transparency fix and the CD check in `spel.dat`.

### Step 4: redirect the aspect division and the HUD

Apply the changes from [Patch part 2](#patch-part-2-43-aspect-denominator) and [Patch part 5](#patch-part-5-hud-proportions).

### Step 5: set up the horizontal view

Apply the changes from [Patch part 3](#patch-part-3-horizontal-clip-range).

### Step 6: fix the texture memory crash

At file offset:

```text
0x0BC0F0
```

replace:

```text
B8 00 10 00 00 E8 06 D3 09 00 53
```

with:

```text
C7 81 A1 02 00 00 00 00 00 04 C3
```

This step also works on its own, for example on an original 4:3 `spel.dat`.

### Step 7: save as `spel.dat`

Save the patched file and rename it to:

```text
spel.dat
```

Then place it in the game directory.

### Step 8: remove the CD check from `menu.exe`

Back up `menu.exe` and apply its row from [Patch part 7](#patch-part-7-cd-check-removal).

### Step 9: check the overlay `.ini` files

They must be the game's own files. A file an older version of this fix changed is moved a second time. Restore it from `4x3_backup` or the game CD.

## Manual patching on Linux

### Recommended tools

Useful Linux tools:

```text
python3
xxd
hexdump
objdump
Ghidra
radare2 / rizin
Bless Hex Editor
okteta
```

### Step 1: back up the original

```bash
cp spel.dat spel_original_backup.dat
```

### Step 2: inspect the viewport setup

You can disassemble the relevant range with:

```bash
objdump -D -Mintel \
  --start-address=0x4c0e30 \
  --stop-address=0x4c0eb0 \
  spel.dat
```

In the original file, look for:

```asm
004c0e47: db 05 9c 37 5b 00     fild   DWORD PTR ds:0x5b379c
004c0e57: da 35 98 37 5b 00     fidiv  DWORD PTR ds:0x5b3798
...
004c0e8a: c7 46 14 00 00 80 bf  mov    DWORD PTR [esi+0x14],0xbf800000
004c0e96: c7 46 1c 00 00 00 40  mov    DWORD PTR [esi+0x1c],0x40000000
```

After patching, this should become:

```asm
004c0e57: da 35 38 1f 75 00     fidiv  DWORD PTR ds:0x751f38
...
004c0e8a: c7 46 14 ab aa aa bf  mov    DWORD PTR [esi+0x14],0xbfaaaaab   ; 16:9
004c0e96: c7 46 1c ab aa 2a 40  mov    DWORD PTR [esi+0x1c],0x402aaaab   ; 16:9
```

### Step 3: patch with Python

Save this as `patch_spel.py`:

```python
#!/usr/bin/env python3
from pathlib import Path
import struct
import sys

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
fixed = sys.argv[3].lower().split("x") if len(sys.argv) > 3 else ["0", "0"]
width, height = int(fixed[0]), int(fixed[1])

data = bytearray(input_path.read_bytes())

if data[:2] != b"MZ":
    raise RuntimeError("Not a PE executable")

CODE_OFFSET = 0x175500
CODE = bytes.fromhex("""
83 7C 24 04 03 75 60 A1 26 B8 73 00 83 F8 FF 74 56 69 C0 B0 00 00 00 03
05 D8 B7 73 00 83 78 54 10 75 44 C7 44 24 04 04 00 00 00 6A 00 6A 18 A1
B4 B4 73 00 50 8B 08 FF 51 5C 6A 05 6A 19 A1 B4 B4 73 00 50 8B 08 FF 51
5C 6A 01 6A 0F A1 B4 B4 73 00 50 8B 08 FF 51 5C 6A 00 6A 29 A1 B4 B4 73
00 50 8B 08 FF 51 5C B8 90 2B 4C 00 FF E0 01 F0 5E 5B EB 04 5B 01 F0 5E
85 C0 74 06 0B 05 A8 09 74 00 C3 BA 01 00 00 00 EB 0C 8B 54 24 0C 85 D2
0F 94 C2 0F B6 D2 52 FF 74 24 10 6A 1B FF 74 24 10 8B 04 24 8B 08 FF 51
5C 5A 50 A1 2E B8 73 00 3B 05 26 B8 73 00 75 35 52 6A 0F FF 74 24 10 8B
04 24 8B 08 FF 51 5C 83 3D 05 B5 73 00 02 75 1D 8B 44 24 10 F7 D8 19 C0
83 E0 02 83 C0 02 50 6A 15 FF 74 24 10 8B 04 24 8B 08 FF 51 5C 58 C2 0C
00 A1 2E B8 73 00 3B 05 26 B8 73 00 75 4A 50 54 6A 0F A1 B4 B4 73 00 50
8B 08 FF 51 58 6A 00 6A 0F A1 B4 B4 73 00 50 8B 08 FF 51 5C FF 74 24 14
FF 74 24 14 FF 74 24 14 FF 74 24 14 8B 04 24 8B 08 FF 51 30 5A 50 52 6A
0F A1 B4 B4 73 00 50 8B 08 FF 51 5C 58 C2 10 00 8B 44 24 04 8B 08 FF 61
30 60 68 DF 5E 57 00 FF 15 A0 60 57 00 89 C6 85 F6 74 12 68 FF 5E 57 00
56 FF 15 FC 60 57 00 85 C0 74 02 FF D0 8B 1D A8 5F 57 00 8B 2D AC 5F 57
00 85 DB 75 61 81 EC 9C 00 00 00 89 E7 B9 27 00 00 00 31 C0 F3 AB 66 C7
44 24 24 9C 00 85 F6 74 2B 68 EA 5E 57 00 56 FF 15 FC 60 57 00 85 C0 74
1B 54 6A FF 6A 00 FF D0 85 C0 74 10 8B 5C 24 6C 8B 6C 24 70 85 DB 74 04
85 ED 75 14 6A 00 FF 15 F4 61 57 00 89 C3 6A 01 FF 15 F4 61 57 00 89 C5
81 C4 9C 00 00 00 BE 78 5F 57 00 B9 0C 00 00 00 AD 89 18 89 68 04 E2 F8
8D 04 AD 01 00 00 00 31 D2 B9 03 00 00 00 F7 F1 A3 38 1F 75 00 61 E9 CD
29 EE FF 50 A1 98 37 5B 00 8D 04 40 50 DB 04 24 A1 9C 37 5B 00 C1 E0 02
89 04 24 DA 34 24 58 D9 C0 D9 E0 D9 5E 14 DC C0 D9 5E 1C 58 C3 FF 74 24
0C FF 74 24 0C FF 74 24 0C E8 22 B8 F0 FF 84 C0 74 2D 50 8B 44 24 08 8B
40 04 85 C0 74 20 E8 4F 00 00 00 85 C0 74 17 50 E8 15 00 00 00 59 0F AF
C1 50 DB 04 24 58 8B 4C 24 10 D8 01 D9 19 58 C2 0C 00 A1 98 37 5B 00 8D
04 40 8B 0D 9C 37 5B 00 8D 14 8D 00 00 00 00 29 D0 69 C0 40 1F 00 00 6B
C9 63 89 CA D1 EA 85 C0 79 02 F7 DA 01 D0 99 F7 F9 C3 56 57 89 C6 83 EC
40 89 E2 6A 40 52 68 34 A0 5A 00 56 E8 47 E5 F4 FF 83 C4 10 89 E0 BF 12
5F 57 00 E8 6A 00 00 00 74 58 89 F0 BF 2B 5F 57 00 E8 5C 00 00 00 74 4A
89 F0 BF 42 5F 57 00 E8 4E 00 00 00 74 3C 89 F0 BF 51 5F 57 00 E8 40 00
00 00 74 2E 89 E0 BF 1E 5F 57 00 E8 32 00 00 00 74 27 89 F0 BF 60 5F 57
00 E8 2F 00 00 00 74 19 89 F0 BF 6F 5F 57 00 E8 21 00 00 00 74 0B 31 C0
EB 0A B8 01 00 00 00 EB 03 83 C8 FF 83 C4 40 5F 5E C3 E8 06 00 00 00 75
03 80 38 00 C3 57 8A 0F 84 C9 74 17 8A 28 80 FD 61 72 08 80 FD 7A 77 03
80 ED 20 38 CD 75 04 40 47 EB E3 5F C3 56 8B 74 24 0C FF 15 AC 60 57 00
3C 06 72 27 C7 46 18 18 00 00 00 E8 24 00 00 00 85 C0 74 1C C7 46 18 20
00 00 00 E8 14 00 00 00 85 C0 74 0C C7 46 18 10 00 00 00 E8 04 00 00 00
5E C2 10 00 FF 74 24 18 FF 74 24 18 FF 74 24 18 FF 74 24 18 8B 04 24 8B
08 FF 51 18 C3 FF 74 24 04 FF 15 58 60 57 00 85 C0 74 3B 8B 4C 24 04 A1
10 1F 75 00 0B 05 14 1F 75 00 75 0F 8B 01 A3 10 1F 75 00 8B 41 04 A3 14
1F 75 00 8B 01 8B 51 04 2B 05 10 1F 75 00 1B 15 14 1F 75 00 89 01 89 51
04 B8 01 00 00 00 C2 04 00 FF 15 50 62 57 00 83 3D 1C 1F 75 00 00 75 0F
A3 18 1F 75 00 C7 05 1C 1F 75 00 01 00 00 00 2B 05 18 1F 75 00 C3 D9 C0
DC 25 20 1F 75 00 D8 76 04 D9 5E 0C DD 15 20 1F 75 00 D8 76 04 D9 5E 08
C3 D9 44 24 04 8B 44 24 04 89 41 78 DC 05 28 1F 75 00 DD 15 28 1F 75 00
D9 51 74 83 EC 08 DD 1C 24 8B 49 14 B8 80 83 4F 00 FF D0 C2 04 00 50 51
B9 B0 28 71 00 B8 00 68 4A 00 FF D0 D8 0D BB 5E 57 00 D9 E8 D8 D1 DF E0
9E 73 02 D9 C9 DD D8 59 58 C3 D8 3D 18 63 57 00 E8 D1 FF FF FF DE C9 C3
E8 C9 FF FF FF D9 C0 D8 4C 24 04 D9 5C 24 04 D9 C0 D8 4C 24 08 D9 5C 24
08 D8 4C 24 0C D9 5C 24 0C 56 89 CE 8B 46 10 68 F6 97 4A 00 C3 89 44 24
10 D9 44 24 0C D9 E0 D8 81 84 00 00 00 D9 99 84 00 00 00 D9 44 24 08 D8
81 80 00 00 00 D9 99 80 00 00 00 D9 44 24 10 D8 81 88 00 00 00 D9 99 88
00 00 00 68 BE 5C 4A 00 C3 51 B8 80 96 4F 00 FF D0 59 31 C0 89 01 89 41
04 89 41 08 C3 B9 30 1F 75 00 EB 05 B9 34 1F 75 00 D8 01 D9 C0 B8 24 85
55 00 FF D0 50 DA 24 24 58 D9 19 C3 51 B9 3C 1F 75 00 E8 E2 FF FF FF 59
C3 FF 15 AC 60 57 00 8B 15 A0 37 5B 00 83 FA 10 75 09 3C 06 72 05 BA 20
00 00 00 C3 8B 44 24 5C 83 78 0C 20 74 19 FF 74 24 08 FF 74 24 08 E8 25
27 F5 FF 83 C4 08 66 89 07 83 C7 02 C2 08 00 FF 74 24 04 E8 40 24 F5 FF
83 C4 04 89 07 83 C7 04 C2 08 00 FF 74 24 04 B8 70 31 40 00 FF D0 60 8B
74 24 24 31 D2 31 C9 8B 44 8E 34 8B 40 08 83 78 28 00 74 07 89 C8 D1 E8
40 09 C2 41 83 F9 04 72 E6 89 D7 89 E8 2D 7C EA 5C 00 31 D2 B9 94 02 00
00 F7 F1 83 F8 13 72 05 B8 13 00 00 00 8D 34 85 40 1F 75 00 8B 0D 50 5E
71 00 01 D9 D9 81 BC 00 00 00 DC C8 D9 81 C0 00 00 00 DC C8 DE C1 D9 81
C4 00 00 00 DC C8 DE C1 D8 1D CF 5E 57 00 DF E0 9E 73 5F 83 FF 03 75 1D
8B 41 24 69 C0 A9 00 00 00 03 05 D0 B0 73 00 D9 40 24 D8 1D D3 5E 57 00
DF E0 9E 73 3D B9 B0 28 71 00 B8 00 68 4A 00 FF D0 D8 06 D9 16 D8 1D D7
5E 57 00 DF E0 9E 72 28 6A 00 8B 0D 50 5E 71 00 FF 74 19 34 89 D8 31 D2
B9 F0 00 00 00 F7 F1 50 B8 A0 E5 40 00 FF D0 83 C4 0C C7 06 00 00 00 00
61 C2 04 00 C6 41 60 01 81 EC B0 00 00 00 E9 29 01 F9 FF 51 6A 01 B8 10
29 4F 00 FF D0 59 81 EC D8 00 00 00 E9 7D D5 F7 FF D9 C0 D8 64 24 40 D9
E1 D8 1D DB 5E 57 00 DF E0 9E 76 21 D9 EE D8 D9 DF E0 9E 74 12 8B 44 24
6C 6B C0 50 03 05 B8 5E 71 00 F6 00 04 75 06 DD D8 D9 44 24 40 D8 05 10
63 57 00 C3 52 8B 44 3A 3C 85 C0 78 1E 3B 05 BC 5E 71 00 7F 16 89 F8 31
D2 B9 F0 00 00 00 F7 F1 50 B8 20 70 4A 00 FF D0 83 C4 04 5A 8B 4C 3A 10
8D 54 24 48 C3 A1 50 5E 71 00 8B 44 38 10 8B 40 08 8B 80 A4 00 00 00 31
D2 89 90 94 00 00 00 89 90 98 00 00 00 89 90 9C 00 00 00 89 50 74 89 50
78 89 50 7C 89 90 84 00 00 00 89 90 88 00 00 00 89 90 8C 00 00 00 81 7C
24 60 0A D7 44 00 75 07 D9 1D 00 1B 5D 00 C3 DD D8 C3 46 81 C5 94 09 00
00 3B 35 04 5F 71 00 7C 04 31 F6 31 ED C3 4E 81 ED 94 09 00 00 79 0D 8B
35 04 5F 71 00 4E 69 EE 94 09 00 00 C3 E8 D4 FC FF FF 31 C9 D9 E8 D8 A4
8D 88 00 00 00 D9 84 8D 88 00 00 00 D8 CA DC C1 DE F1 D9 1C 8D 98 1F 75
00 41 83 F9 03 72 DD DD D8 C3 A1 A4 1F 75 00 05 B9 79 37 9E A3 A4 1F 75
00 C1 E8 10 50 DB 04 24 58 D8 0D C3 5E 57 00 DE C1 E9 2E 28 FE FF B8 20
4D 44 00 EB 21 B8 80 4F 44 00 EB 1A B8 30 67 44 00 EB 13 B8 F0 D8 43 00
EB 0C B8 70 B6 45 00 EB 05 B8 D0 B9 45 00 80 3D 90 1F 75 00 00 74 02 FF
E0 C3 80 3D 90 1F 75 00 00 0F 85 D9 22 F0 FF C2 08 00 80 3D 90 1F 75 00
00 0F 85 19 3F EF FF 31 C0 C2 04 00 E8 AF 0A F3 FF D8 15 BF 5E 57 00 DF
E0 9E 73 08 DD D8 D9 05 BF 5E 57 00 C3 E8 96 0A F3 FF D8 0D 58 63 57 00
EB 0B E8 89 0A F3 FF D8 0D 08 63 57 00 D9 E8 DE E1 C3 E8 F7 FB FF FF D8
7C 24 04 D8 61 04 D8 54 24 04 DF E0 9E 76 04 D9 54 24 04 DD D8 E9 DE D0
E8 FF E8 D7 FB FF FF D8 4B 30 51 D9 1C 24 59 8B 53 28 C3 D9 81 CC 00 00
00 E8 C0 FB FF FF DE C9 DE C1 C3 FF 74 24 08 FF 74 24 08 E8 10 A5 EE FF
83 C4 08 E8 A6 FB FF FF DE C9 C3 E8 9E FB FF FF D8 0D C7 5E 57 00 D9 E8
DE E1 DE C9 C3 81 F9 C8 00 00 00 73 03 8D 42 64 A3 40 BA 6F 00 C3 B9 B0
28 71 00 E8 F8 09 F3 FF D8 05 A8 1F 75 00 D9 15 A8 1F 75 00 D8 1D BF 5E
57 00 DF E0 9E 0F 93 C0 0F B6 C0 72 07 83 25 A8 1F 75 00 00 C3 83 39 00
74 46 51 83 EC 08 54 FF 15 58 60 57 00 8B 4C 24 08 DF 2C 24 DF 2D 00 1F
75 00 DE E9 D8 71 04 D8 1D CB 5E 57 00 DF E0 9E 73 11 A1 00 1F 75 00 0B
05 04 1F 75 00 74 04 F3 90 EB CB 58 A3 00 1F 75 00 58 A3 04 1F 75 00 59
E8 83 08 F3 FF B9 B0 28 71 00 E8 79 09 F3 FF D8 05 94 1F 75 00 D8 15 BF
5E 57 00 DF E0 9E 0F 93 05 90 1F 75 00 72 15 D8 25 BF 5E 57 00 D8 15 BF
5E 57 00 DF E0 9E 72 04 DD D8 D9 EE D9 1D 94 1F 75 00 C3 00 00 C8 41 0A
D7 23 3D 00 00 80 37 0A D7 23 3C 89 88 88 3B 00 00 10 40 00 00 00 3F 00
00 40 40 00 00 C8 41 55 53 45 52 33 32 2E 44 4C 4C 00 45 6E 75 6D 44 69
73 70 6C 61 79 53 65 74 74 69 6E 67 73 41 00 53 65 74 50 72 6F 63 65 73
73 44 50 49 41 77 61 72 65 00 53 50 45 45 44 4F 4D 45 54 45 52 00 43 4F
4D 4D 55 4E 49 43 41 54 4F 52 00 53 54 52 49 4E 47 5F 52 41 43 45 5F 54
49 4D 45 5F 56 41 4C 55 45 00 53 54 52 49 4E 47 5F 43 55 52 5F 4C 41 50
00 53 54 52 49 4E 47 5F 43 55 52 5F 50 4F 53 00 4F 56 4C 5F 50 4F 52 54
52 41 49 54 53 5F 00 50 4C 41 59 45 52 5F 00 90 98 37 5B 00 EC 37 5B 00
00 38 5B 00 14 38 5B 00 64 38 5B 00 78 38 5B 00 8C 38 5B 00 A0 38 5B 00
B4 38 5B 00 04 39 5B 00 18 39 5B 00 2C 39 5B 00
""")
if data[CODE_OFFSET:CODE_OFFSET + len(CODE)] not in (bytes(len(CODE)), CODE):
    raise RuntimeError("Unexpected bytes where the code goes. Wrong executable version?")
data[CODE_OFFSET:CODE_OFFSET + len(CODE)] = CODE
# A fixed resolution, or 0 and 0 to follow the display.
data[CODE_OFFSET + len(CODE):CODE_OFFSET + len(CODE) + 8] = struct.pack("<II", width, height)

for offset, old, new in [
    (0x0582AA, "E8 31 FE FF FF", "E8 A2 D3 11 00"),
    (0x07FDCF, "E8 9C 11 00 00", "E8 69 59 0F 00"),
    (0x07FF43, "E8 28 10 00 00", "E8 F5 57 0F 00"),
    (0x080610, "E8 5B 09 00 00", "E8 28 51 0F 00"),
    (0x0C287D, "8E", "8D"),
    (0x0C058A, "E8 01 26 00 00", "E8 71 4F 0B 00"),
    (0x0C7FF9, "03 C6 5E 5B C3", "E9 70 D5 0A 00"),
    (0x0C82C9, "5B 03 C6 5E C3", "E9 A6 D2 0A 00"),
    (0x03DEF9, "8B 08 FF 51 5C", "E8 85 76 13 00"),
    (0x03E04A, "8B 08 FF 51 5C", "E8 34 75 13 00"),
    (0x040224, "8B 08 FF 51 5C", "E8 5A 53 13 00"),
    (0x04031A, "8B 10 FF 52 5C", "E8 64 52 13 00"),
    (0x04275C, "8B 08 FF 51 5C", "E8 29 2E 13 00"),
    (0x042B4E, "8B 08 FF 51 5C", "E8 30 2A 13 00"),
    (0x043D8E, "8B 10 FF 52 5C", "E8 F0 17 13 00"),
    (0x043E9C, "8B 10 FF 52 5C", "E8 E2 16 13 00"),
    (0x04523A, "8B 08 FF 51 5C", "E8 4B 03 13 00"),
    (0x0453F9, "8B 10 FF 52 5C", "E8 85 01 13 00"),
    (0x0470C3, "8B 08 FF 51 5C", "E8 BB E4 12 00"),
    (0x047276, "8B 10 FF 52 5C", "E8 08 E3 12 00"),
    (0x05DD24, "8B 08 FF 51 5C", "E8 5A 78 11 00"),
    (0x05DD98, "8B 10 FF 52 5C", "E8 E6 77 11 00"),
    (0x085F29, "8B 08 FF 51 5C", "E8 55 F6 0E 00"),
    (0x08614A, "8B 08 FF 51 5C", "E8 34 F4 0E 00"),
    (0x0B5E4D, "8B 08 50 FF 51 5C", "50 E8 37 F7 0B 00"),
    (0x0B5E6C, "8B 10 50 FF 52 5C", "50 E8 11 F7 0B 00"),
    (0x0C0F80, "8B 11 50 6A 01 51 FF 52 30", "50 6A 01 51 E8 68 46 0B 00"),
    (0x0C0679, "8B 08 52 50 FF 51 18", "52 50 E8 ED 51 0B 00"),
    (0x0A6710, "FF 15 58 60 57 00", "E8 B0 F1 0C 00 90"),
    (0x0A6850, "FF 15 58 60 57 00", "E8 70 F0 0C 00 90"),
    (0x0A673B, "FF 15 50 62 57 00", "E8 D1 F1 0C 00 90"),
    (0x0A687E, "FF 15 50 62 57 00", "E8 8E F0 0C 00 90"),
    (0x04CB9E, "E8 5D 9B 05 00", "E8 8A 92 12 00"),
    (0x0A6751, "D8 76 04 D9 C0 D8 66", "E8 E0 F1 0C 00 EB 07"),
    (0x0A6894, "D8 76 04 D9 C0 D8 66", "E8 9D F0 0C 00 EB 07"),
    (0x0A45D0, "D9 44 24 04 D8", "E9 7C 13 0D 00"),
    (0x02898F, "D8 3D 18 63 57 00", "E8 0E D0 14 00 90"),
    (0x016002, "D8 3D 18 63 57 00", "E8 9B F9 15 00 90"),
    (0x0A97F0, "56 8B F1 8B 46 10", "E9 BB C1 0C 00 90"),
    (0x0A5C9E, "D9 44 24 0C 8B", "E9 3A FD 0C 00"),
    (0x0A5D9C, "E8 DF 38 05 00", "E8 78 FC 0C 00"),
    (0x06F2C6, "E8 59 92 0E 00", "E8 62 67 10 00"),
    (0x06F308, "E8 17 92 0E 00", "E8 27 67 10 00"),
    (0x030F36, "E8 E9 75 12 00", "E8 11 4B 14 00"),
    (0x030F5D, "E8 C2 75 12 00", "E8 EA 4A 14 00"),
    (0x030FA4, "E8 7B 75 12 00", "E8 A3 4A 14 00"),
    (0x0310E6, "E8 39 74 12 00", "E8 61 49 14 00"),
    (0x0C58AB, "8B 15 A0 37 5B 00", "E8 A9 01 0B 00 90"),
    (0x0C03C0, "E8 EB 7D 00 00 83 C4", "E8 AF 56 0B 00 EB 07"),
    (0x028F30, "E8 3B A2 FD FF", "E8 76 CB 14 00"),
    (0x105CC6, "81 EC B0 00 00 00", "E9 C9 FE 06 00 90"),
    (0x0F3130, "81 EC D8 00 00 00", "E9 6E 2A 08 00 90"),
    (0x00E7C0, "8B 4C 17 10 8D 54 24 44", "E8 2F 74 16 00 90 90 90"),
    (0x00E818, "D9 1D 00 1B 5D 00", "E8 08 74 16 00 90"),
    (0x00E838, "46 81 C5 94 09 00 00", "E8 3D 74 16 00 90 90"),
    (0x00E841, "4E 81 ED 94 09 00 00", "E8 48 74 16 00 90 90"),
    (0x00E7B6, "D8 05 10 63 57 00", "E8 FE 73 16 00 90"),
    (0x0B18D4, "E8 C7 26 01 00", "E8 CC 43 0C 00"),
    (0x0B195F, "D8 8D 88 00 00 00", "D8 0D 98 1F 75 00"),
    (0x0B1974, "D8 8D 8C 00 00 00", "D8 0D 9C 1F 75 00"),
    (0x0B198D, "D8 8D 90 00 00 00", "D8 0D A0 1F 75 00"),
    (0x0A83A1, "E8 7E 01 0B 00", "E8 2C D9 0C 00"),
    (0x0A83B1, "E8 6E 01 0B 00", "E8 1C D9 0C 00"),
    (0x0A83BD, "E8 62 01 0B 00", "E8 10 D9 0C 00"),
    (0x093D41, "E8 DE 47 0C 00", "E8 8C 1F 0E 00"),
    (0x044EA6, "E8 75 FE FF FF", "E8 4B 0E 13 00"),
    (0x04516B, "E8 10 FE FF FF", "E8 8D 0B 13 00"),
    (0x0467E2, "E8 49 FF FF FF", "E8 1D F5 12 00"),
    (0x03D962, "E8 89 FF FF FF", "E8 A4 83 13 00"),
    (0x04685D, "E8 9E FF 05 00 D8 0D 90 67 57 00", "E8 03 F5 12 00 90 90 90 90 90 90"),
    (0x03D9D3, "E8 28 8E 06 00 D8 0D E4 66 57 00", "E8 9A 83 13 00 90 90 90 90 90 90"),
    (0x046AC3, "E8 38 FD 05 00", "E8 84 F2 12 00"),
    (0x03DB45, "E8 B6 8C 06 00", "E8 02 82 13 00"),
    (0x051E0F, "E8 5C 98 00 00", "E8 FE 3E 12 00"),
    (0x0553EF, "E8 DC 65 00 00", "E8 25 09 12 00"),
    (0x0513DC, "D8 81 CC 00 00 00", "E8 D2 49 12 00 90"),
    (0x05153B, "E8 D0 6A 02 00", "E8 EA 47 12 00"),
    (0x05366A, "E8 F1 65 01 00", "E8 CB 26 12 00"),
    (0x053693, "E8 C8 65 01 00", "E8 A2 26 12 00"),
    (0x069D3C, "E8 BF CA 03 00", "E8 0B C0 10 00"),
    (0x03B1AE, "B8 01 00 00 00", "E8 4B AC 13 00"),
    (0x007EA4, "E8 D7 AF FF FF", "E8 D9 DE 16 00"),
    (0x007FFE, "E8 7D AE FF FF", "E8 7F DD 16 00"),
    (0x0080EB, "E8 90 AD FF FF", "E8 92 DC 16 00"),
    (0x008ECC, "E8 AF 9F FF FF", "E8 B1 CE 16 00"),
    (0x01F7F9, "E8 02 70 08 00", "E8 4E 65 15 00"),
    (0x0204B3, "E8 48 63 08 00", "E8 94 58 15 00"),
    (0x01F29A, "8B 4B 30 8B 53 28", "E8 03 6B 15 00 90"),
    (0x04E9D5, "A3 40 BA 6F 00", "E8 13 74 12 00"),
    (0x05CCE8, "D8 0D D8 68 57 00", "E8 EE 90 11 00 90"),
    (0x05CCFC, "D8 0D D8 68 57 00", "E8 DA 90 11 00 90"),
    (0x05B0B1, "E8 2A 52 00 00", "E8 0D AD 11 00"),
    (0x05B0C6, "E8 15 52 00 00", "E8 F8 AC 11 00"),
    (0x05B0DB, "E8 00 52 00 00", "E8 E3 AC 11 00"),
    (0x05C736, "E8 A5 3B 00 00", "E8 88 96 11 00"),
    (0x05C74B, "E8 90 3B 00 00", "E8 73 96 11 00"),
    (0x05C760, "E8 7B 3B 00 00", "E8 5E 96 11 00"),
    (0x05D006, "E8 D5 32 00 00", "E8 B8 8D 11 00"),
    (0x05D01B, "E8 C0 32 00 00", "E8 A3 8D 11 00"),
    (0x05D030, "E8 AB 32 00 00", "E8 8E 8D 11 00"),
    (0x061271, "E8 6A F0 FF FF", "E8 4D 4B 11 00"),
    (0x061286, "E8 55 F0 FF FF", "E8 38 4B 11 00"),
    (0x06129B, "E8 40 F0 FF FF", "E8 23 4B 11 00"),
    (0x062421, "E8 BA DE FF FF", "E8 9D 39 11 00"),
    (0x062436, "E8 A5 DE FF FF", "E8 88 39 11 00"),
    (0x06244B, "E8 90 DE FF FF", "E8 73 39 11 00"),
    (0x000248, "08 44 1C 00", "00 50 1C 00"),
    (0x0001F8, "4A 44 17 00", "00 50 17 00"),
    (0x0CD478, "68 70", "EB B6"),
    # Use the 4:3 reference width for the viewport and the HUD.
    (0x0C0E57, "DA 35 98 37 5B 00", "DA 35 38 1F 75 00"),
    (0x07CDD1, "DA 35 98 37 5B 00", "DA 35 38 1F 75 00"),
    (0x07FE55, "DB 05 98 37 5B 00", "DB 05 38 1F 75 00"),
    (0x080534, "DB 05 98 37 5B 00", "DB 05 38 1F 75 00"),
    # Texture memory crash fix: skip the probe and report 64 MB.
    (0x0BC0F0, "B8 00 10 00 00 E8 06 D3 09 00 53", "C7 81 A1 02 00 00 00 00 00 04 C3"),
]:
    old, new = bytes.fromhex(old), bytes.fromhex(new)
    if data[offset:offset + len(old)] != old and data[offset:offset + len(new)] != new:
        raise RuntimeError(f"Unexpected bytes at 0x{offset:X}. Wrong executable version?")
    data[offset:offset + len(new)] = new

# The horizontal view comes from the added code. v1.2.0 and older changed the
# values in these instructions, so only their first bytes are checked.
for offset, opcode, new in [
    (0x0C0E8A, "C7 46 14", "E8 84 48 0B 00 90 90"),
    (0x0C0E96, "C7 46 1C", "90 90 90 90 90 90 90"),
]:
    new = bytes.fromhex(new)
    if data[offset:offset + 3] != bytes.fromhex(opcode) and data[offset:offset + len(new)] != new:
        raise RuntimeError(f"Unexpected bytes at 0x{offset:X}. Wrong executable version?")
    data[offset:offset + len(new)] = new

output_path.write_bytes(data)
print(f"Patched {input_path} -> {output_path}")
```

Run it like this. Add a resolution such as `2560x1440` at the end to fix it instead of following the display:

```bash
python3 patch_spel.py spel.dat spel_patched.dat
```

Then install:

```bash
cp spel_patched.dat /path/to/A2Racer4/spel.dat
```

### Step 4: verify the patch

```bash
objdump -D -Mintel --start-address=0x4c0e50 --stop-address=0x4c0ea0 spel_patched.dat
```

Check that the `fidiv` line points to `0x751f38`, that a `call` sits at `0x4c0e8a`, and that `0x4c0e96` holds `nop`s.

Check the crash fix as well:

```bash
objdump -D -Mintel --start-address=0x4bc0f0 --stop-address=0x4bc0fb spel_patched.dat
```

It should store `0x4000000` at `[ecx+0x2a1]` and return.

## Values for other resolutions

The added code calculates these at startup:

| Resolution | Reference denominator | dvClipX | dvClipWidth | HUD shift |
|---|---|---:|---:|---:|
| 1280×1024 | 1365 | -0.9375 | 1.875 | -20 |
| 1600×1200 | 1600 | -1.0 | 2.0 | 0 |
| 1680×1050 | 1400 | -1.2 | 2.4 | +65 |
| 1920×1080 | 1440 | -1.3333 | 2.6667 | +108 |
| 2560×1440 | 1920 | -1.3333 | 2.6667 | +108 |
| 3440×1440 | 1920 | -1.7917 | 3.5833 | +256 |
| 5120×1440 | 1920 | -2.6667 | 5.3333 | +539 |

## Overlay files

The HUD uses separate configuration files, `overlay*.ini`, on a 640×480 canvas. Since v1.3.0 they stay as the game ships them. The three calls that read a `Position` (`0x0047FDCF`, `0x0047FF43` and `0x00480610`) go through `read_position` in the added code, which changes only the `x` it just read:

```text
shift = (0.75 × W / H - 1) × 320 / 0.99, rounded
```

- **Add the shift:** every section with `Parent = Speedometer`, and `STRING_RACE_TIME_VALUE`, `STRING_CUR_LAP` and `STRING_CUR_POS`.
- **Subtract the shift:** every section with `Parent = Communicator`, and every `OVL_PORTRAITS_*` and `PLAYER_*`.
- **Leave alone:** everything else, including `Scale`.

## Troubleshooting

### The screen goes black and the game crashes when a race starts

That is the texture memory probe overflowing on a modern graphics card (more than ~128 MB of VRAM). Check that the bytes at `0x0BC0F0` are `C7 81 A1 02 00 00 00 00 00 04 C3`; see [Patch part 4](#patch-part-4-texture-memory-crash-fix).

### Objects have black edges or black boxes around them

That is the game's color key on a current driver. Check the changes in [Patch part 6](#patch-part-6-transparency-fix).

### The game asks for the CD

Check both changes in [Patch part 7](#patch-part-7-cd-check-removal). The menu and the race each have their own check.

### The game stops with "could not set display mode"

The display's current resolution is not available at 32-bit color, or at 16-bit color on Windows XP and older. Run the patcher again and type a fixed resolution that is.

### Cars lift up or lose all speed

Check the rows for the timer, the world time, the traffic mass, the driving force, the pedals, the hung car, the contact check and the object move in [All added and changed bytes](#all-added-and-changed-bytes). See [Patch part 12](#patch-part-12-contacts-that-outlive-their-triangle), [Patch part 9](#patch-part-9-car-physics) and [Patch part 11](#patch-part-11-cars-that-get-hung-up). A collision can still throw a car, and the Enter reset can drop your car on top of another one.

### The countdown before the race is missing

Check that the instructions at file offsets `0x0C0E57`, `0x07CDD1`, `0x07FE55` and `0x080534` point to `0x00751F38`. See [Patch part 2](#patch-part-2-43-aspect-denominator).

### Surfaces flicker where they meet

The Z-buffer is still 16 bits. Check that the call at file offset `0x0C0679` goes to `create_zbuffer`. Windows XP and older keep 16 bits on purpose, see [Patch part 8](#patch-part-8-deeper-z-buffer).

### The game still opens in the old resolution

Check that the call at file offset `0x0582AA` goes to `startup`, and that the two values after the added code are `0` or the resolution you want.

### The 3D image is stretched

Check the `fidiv` patch at `0x0C0E57`. It must divide by the 4:3 reference denominator at `0x00751F38`, not by the actual 16:9 width.

### The 3D image is zoomed or cropped

Check the horizontal clip constants against the formula in [Patch part 3](#patch-part-3-horizontal-clip-range).

### The HUD is stretched or misplaced

Elements too far out or too far in mean the `overlay*.ini` files are not the game's own, so they move twice. A squashed HUD means the three HUD changes in [Patch part 5](#patch-part-5-hud-proportions) are missing.

### Finish-result text position does not move through `.ini`

Testing showed me that the finish string entries read scale and color from the `.ini` files, but their position appears to be assigned by game code at runtime. This is a separate issue from the main 16:9 3D fix.
