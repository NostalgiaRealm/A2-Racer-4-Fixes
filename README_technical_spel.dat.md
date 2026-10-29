# Technical notes: A2 Racer 4 `spel.dat` 16:9 widescreen patch

This document explains how the patched `spel.dat` was modified so **A2 Racer 4** can render the racing part of the game at a native 16:9 resolution without horizontally stretching the 3D image.

The working reference build discussed here is the patched spel.dat fixed for 2560x1440 output.

The explanations below are written for the **2560×1440** version, but the same method can be adapted to other 16:9 resolutions.

## Important background

A2 Racer 4 uses `spel.dat` as the executable module for the actual DirectDraw/Direct3D racing portion of the game. Even though the extension is `.dat`, it is a normal PE32 Windows executable.

The original game is designed around 4:3 display modes. If a 16:9 display mode is forced naively, the game does not automatically become proper widescreen. Depending on what is patched, the result can be:

- a horizontally stretched 3D image;
- a vertically zoomed/cropped image;
- a correct 3D image but stretched HUD;
- a correct 3D image with HUD fixed separately through the overlay `.ini` files.

The final working approach is:

1. patch the display-mode table to request the desired 16:9 resolution;
2. patch the Direct3D viewport/projection setup so the 3D image uses a Hor+ widescreen view;
3. leave HUD layout correction to the `overlay*.ini` files.

## What “Hor+” means here

The goal is not to stretch the old 4:3 frame.

The desired behavior is:

```text
Original 4:3:
  same vertical view
  narrower horizontal view

Patched 16:9:
  same vertical view
  wider horizontal view
```

This is usually called **Hor+** widescreen behavior.

For a 2560×1440 16:9 output, the game should keep the 4:3 vertical framing that would correspond to:

```text
1440 × 4 / 3 = 1920
```

So internally, the projection should behave as if the 1440-pixel-tall frame had a 4:3 reference width of **1920**, while the actual output surface is **2560×1440**.

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
file offset 0x1973D0 -> VA 0x005973D0
```

## Summary of the 2560×1440 patch

It contains three important changes:

1. display-mode table values changed to `2560×1440`;
2. the Direct3D viewport aspect calculation redirects its divisor to a new 4:3 reference width value, `1920`;
3. the horizontal clip range is widened from `[-1.0, +1.0]` to approximately `[-1.25, +1.25]`.

The third part is an empirical tuning specific to this game. A mathematically pure 16:9 conversion would suggest a 4:3-to-16:9 factor of `1.333...`, but in this game that was not the best result. Testing showed that `1.25` produced the correct-looking 3D image without visible stretching.

Since v1.0.4 the patcher also applies a fourth change that is not widescreen related: a fix for the crash at race start on graphics cards with more than ~128 MB of video memory. See [Patch part 4](#patch-part-4-texture-memory-crash-fix).

## Patch part 1: display-mode table

The original executable contains repeated display-mode entries such as:

```text
640×480
800×600
1024×768
1280×1024
1600×1200
```

The 2560×1440 patch changes those relevant entries to:

```text
2560×1440
```

The values are stored as little-endian 16-bit integers.

For 2560:

```text
2560 decimal = 0x0A00
little endian bytes = 00 0A
```

For 1440:

```text
1440 decimal = 0x05A0
little endian bytes = A0 05
```

### 2560×1440 display-mode table offsets

These are the file offsets changed in the original `spel.dat` for the 2560×1440 build:

| File offset | VA | Original | Patched |
|---:|---:|---:|---:|
| `0x1B3798` | `0x005B3798` | `640` | `2560` |
| `0x1B379C` | `0x005B379C` | `480` | `1440` |
| `0x1B37EC` | `0x005B37EC` | `640` | `2560` |
| `0x1B37F0` | `0x005B37F0` | `480` | `1440` |
| `0x1B3800` | `0x005B3800` | `800` | `2560` |
| `0x1B3804` | `0x005B3804` | `600` | `1440` |
| `0x1B3814` | `0x005B3814` | `1024` | `2560` |
| `0x1B3818` | `0x005B3818` | `768` | `1440` |
| `0x1B3864` | `0x005B3864` | `640` | `2560` |
| `0x1B3868` | `0x005B3868` | `480` | `1440` |
| `0x1B3878` | `0x005B3878` | `800` | `2560` |
| `0x1B387C` | `0x005B387C` | `600` | `1440` |
| `0x1B388C` | `0x005B388C` | `1024` | `2560` |
| `0x1B3890` | `0x005B3890` | `768` | `1440` |
| `0x1B38A0` | `0x005B38A0` | `1280` | `2560` |
| `0x1B38A4` | `0x005B38A4` | `1024` | `1440` |
| `0x1B38B4` | `0x005B38B4` | `1600` | `2560` |
| `0x1B38B8` | `0x005B38B8` | `1200` | `1440` |
| `0x1B3904` | `0x005B3904` | `640` | `2560` |
| `0x1B3908` | `0x005B3908` | `480` | `1440` |
| `0x1B3918` | `0x005B3918` | `800` | `2560` |
| `0x1B391C` | `0x005B391C` | `600` | `1440` |
| `0x1B392C` | `0x005B392C` | `1024` | `2560` |
| `0x1B3930` | `0x005B3930` | `768` | `1440` |

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

So the patch stores `1920` at an unused/safe data location and changes the `fidiv` operand to point to that value.

### Aspect denominator storage

The 2560×1440 patch writes the value `1920` here:

```text
file offset: 0x1973D0
VA:          0x005973D0
value:       1920
bytes:       80 07 00 00
```

The important bytes for a 16-bit write are:

```text
80 07
```

The full 32-bit value is safer for readability:

```text
80 07 00 00
```

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
fidiv dword ptr ds:0x005973D0
```

Patched bytes:

```text
DA 35 D0 73 59 00
```

This makes the game divide by the 4:3 reference width instead of the actual 16:9 output width.

## Patch part 3: horizontal clip expansion

The same viewport setup block writes the Direct3D clip rectangle.

Original values include:

```asm
mov dword ptr [esi+0x14], 0xBF800000   ; -1.0
mov dword ptr [esi+0x1C], 0x40000000   ;  2.0
```

These represent a horizontal clip range from `-1.0` with a width of `2.0`, which gives:

```text
-1.0 to +1.0
```

The 2560×1440 patch changes this to:

```asm
mov dword ptr [esi+0x14], 0xBFA00000   ; -1.25
mov dword ptr [esi+0x1C], 0x40200000   ;  2.5
```

That gives:

```text
-1.25 to +1.25
```

This expands the horizontal 3D view while preserving the vertical framing.

### Horizontal clip bytes

At file offset `0x0C0E8A`, VA `0x004C0E8A`:

Original:

```text
C7 46 14 00 00 80 BF
```

Patched:

```text
C7 46 14 00 00 A0 BF
```

At file offset `0x0C0E96`, VA `0x004C0E96`:

Original:

```text
C7 46 1C 00 00 00 40
```

Patched:

```text
C7 46 1C 00 00 20 40
```

## Patch part 4: texture memory crash fix

This part is not related to widescreen. It fixes a crash in the original game that happens on every PC with a modern graphics card, at any resolution.

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

Game versions 1.00 and 1.01 ship an identical `spel.dat`, so the same bytes apply to both. None of the widescreen changes are near this offset.

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

### Step 3: patch the display-mode table

In HxD or 010 Editor, go to each display-mode table file offset listed above and overwrite the 16-bit little-endian values.

For 2560×1440:

```text
Width  2560 -> 00 0A
Height 1440 -> A0 05
```

Example:

At file offset `0x1B3798`, write:

```text
00 0A
```

At file offset `0x1B379C`, write:

```text
A0 05
```

Repeat for all relevant width/height offsets.

### Step 4: create the 4:3 reference denominator

At file offset:

```text
0x1973D0
```

write the 32-bit little-endian value for `1920`:

```text
80 07 00 00
```

### Step 5: redirect the aspect division

At file offset:

```text
0x0C0E57
```

replace:

```text
DA 35 98 37 5B 00
```

with:

```text
DA 35 D0 73 59 00
```

### Step 6: expand the horizontal clip range

At file offset:

```text
0x0C0E8A
```

replace:

```text
C7 46 14 00 00 80 BF
```

with:

```text
C7 46 14 00 00 A0 BF
```

At file offset:

```text
0x0C0E96
```

replace:

```text
C7 46 1C 00 00 00 40
```

with:

```text
C7 46 1C 00 00 20 40
```

### Step 7: fix the texture memory crash

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

### Step 8: save as `spel.dat`

Save the patched file and rename it to:

```text
spel.dat
```

Then place it in the game directory.

### Step 9: install the overlay `.ini` files

The executable patch fixes the 3D rendering. It does not fully fix the HUD by itself.

Use the overlay package as well, which contains:

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

paste them into the same directory as the game expects them. `overlay7.ini` is only needed with the "Schaduw" extra car update.

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
004c0e57: da 35 d0 73 59 00     fidiv  DWORD PTR ds:0x5973d0
...
004c0e8a: c7 46 14 00 00 a0 bf  mov    DWORD PTR [esi+0x14],0xbfa00000
004c0e96: c7 46 1c 00 00 20 40  mov    DWORD PTR [esi+0x1c],0x40200000
```

### Step 3: patch with Python

This Python script applies the 2560×1440 patch to an input `spel.dat`.

Save as:

```text
patch_spel_16x9.py
```

```python
from pathlib import Path
import struct
import sys

if len(sys.argv) != 4:
    print("Usage: python3 patch_spel_16x9.py <input_spel.dat> <output_spel.dat> <width>x<height>")
    raise SystemExit(1)

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
resolution = sys.argv[3].lower()

width_text, height_text = resolution.split("x")
width = int(width_text)
height = int(height_text)

data = bytearray(input_path.read_bytes())

# The game stores these mode values as 16-bit little-endian integers.
if not (0 <= width <= 65535 and 0 <= height <= 65535):
    raise ValueError("Width and height must fit in an unsigned 16-bit value.")

# For Hor+ widescreen, keep a 4:3 reference width for the chosen height.
aspect_denominator = round(height * 4 / 3)

if not (0 <= aspect_denominator <= 65535):
    raise ValueError("Aspect denominator must fit in an unsigned 16-bit value.")

# Display-mode table entries seen in the tested executable.
width_offsets = [
    0x1B3798,
    0x1B37EC,
    0x1B3800,
    0x1B3814,
    0x1B3864,
    0x1B3878,
    0x1B388C,
    0x1B38A0,
    0x1B38B4,
    0x1B3904,
    0x1B3918,
    0x1B392C,
]

height_offsets = [
    0x1B379C,
    0x1B37F0,
    0x1B3804,
    0x1B3818,
    0x1B3868,
    0x1B387C,
    0x1B3890,
    0x1B38A4,
    0x1B38B8,
    0x1B3908,
    0x1B391C,
    0x1B3930,
]

for offset in width_offsets:
    data[offset:offset + 2] = struct.pack("<H", width)

for offset in height_offsets:
    data[offset:offset + 2] = struct.pack("<H", height)

# Store the 4:3 reference denominator.
# For 2560x1440 this is 1920.
data[0x1973D0:0x1973D0 + 4] = struct.pack("<I", aspect_denominator)

# Redirect: fidiv dword ptr ds:0x005B3798
# to:       fidiv dword ptr ds:0x005973D0
old = bytes.fromhex("DA 35 98 37 5B 00")
new = bytes.fromhex("DA 35 D0 73 59 00")
offset = 0x0C0E57

if data[offset:offset + len(old)] != old and data[offset:offset + len(new)] != new:
    raise RuntimeError("Unexpected bytes at aspect-division instruction. Wrong executable version?")

data[offset:offset + len(new)] = new

# Horizontal clip expansion.
# -1.0 -> -1.25
old = bytes.fromhex("C7 46 14 00 00 80 BF")
new = bytes.fromhex("C7 46 14 00 00 A0 BF")
offset = 0x0C0E8A

if data[offset:offset + len(old)] != old and data[offset:offset + len(new)] != new:
    raise RuntimeError("Unexpected bytes at clip-x instruction. Wrong executable version?")

data[offset:offset + len(new)] = new

# 2.0 -> 2.5
old = bytes.fromhex("C7 46 1C 00 00 00 40")
new = bytes.fromhex("C7 46 1C 00 00 20 40")
offset = 0x0C0E96

if data[offset:offset + len(old)] != old and data[offset:offset + len(new)] != new:
    raise RuntimeError("Unexpected bytes at clip-width instruction. Wrong executable version?")

data[offset:offset + len(new)] = new

# Texture memory crash fix: skip the probe and report 64 MB.
# mov eax, 0x1000 / call 0x00559400 / push ebx
# -> mov dword ptr [ecx+0x2A1], 0x04000000 / ret
old = bytes.fromhex("B8 00 10 00 00 E8 06 D3 09 00 53")
new = bytes.fromhex("C7 81 A1 02 00 00 00 00 00 04 C3")
offset = 0x0BC0F0

if data[offset:offset + len(old)] != old and data[offset:offset + len(new)] != new:
    raise RuntimeError("Unexpected bytes at texture memory probe. Wrong executable version?")

data[offset:offset + len(new)] = new

output_path.write_bytes(data)

print(f"Patched {input_path} -> {output_path}")
print(f"Resolution: {width}x{height}")
print(f"4:3 reference denominator: {aspect_denominator}")
```

Run it like this:

```bash
python3 patch_spel_16x9.py spel.dat spel_2560x1440.dat 2560x1440
```

Then install:

```bash
cp spel_2560x1440.dat /path/to/A2Racer4/spel.dat
```

### Step 4: verify the patch

Use `objdump` again:

```bash
objdump -D -Mintel \
  --start-address=0x4c0e30 \
  --stop-address=0x4c0eb0 \
  spel_2560x1440.dat
```

Check that the `fidiv` line points to `0x5973d0` and the clip constants are `0xbfa00000` and `0x40200000`.

Check the crash fix as well:

```bash
objdump -D -Mintel \
  --start-address=0x4bc0f0 \
  --stop-address=0x4bc0fb \
  spel_2560x1440.dat
```

It should show:

```asm
4bc0f0:  c7 81 a1 02 00 00 00   mov    DWORD PTR [ecx+0x2a1],0x4000000
4bc0f7:  00 00 04
4bc0fa:  c3                     ret
```

You can also verify the table values with Python:

```python
from pathlib import Path
import struct

data = Path("spel_2560x1440.dat").read_bytes()

for offset in [0x1B3798, 0x1B3800, 0x1B3814]:
    print(hex(offset), struct.unpack_from("<H", data, offset)[0])

for offset in [0x1B379C, 0x1B3804, 0x1B3818]:
    print(hex(offset), struct.unpack_from("<H", data, offset)[0])

print("aspect denominator:", struct.unpack_from("<I", data, 0x1973D0)[0])
```

Expected output for 2560×1440:

```text
2560
2560
2560
1440
1440
1440
aspect denominator: 1920
```

## Adapting to other 16:9 resolutions

For another 16:9 resolution:

```text
W × H
```

write:

```text
display width  = W
display height = H
aspect denominator = H × 4 / 3
```

Examples:

| Resolution | Display width | Display height | 4:3 reference denominator |
|---:|---:|---:|---:|
| 1280×720 | 1280 | 720 | 960 |
| 1600×900 | 1600 | 900 | 1200 |
| 1920×1080 | 1920 | 1080 | 1440 |
| 2560×1440 | 2560 | 1440 | 1920 |
| 3840×2160 | 3840 | 2160 | 2880 |
| 7680×4320 | 7680 | 4320 | 5760 |

The horizontal clip constants from the 2560×1440 patch remain:

```text
clip x     = -1.25
clip width =  2.5
```

Those values were empirically chosen for this game and should generally remain the same across 16:9 resolutions.

## Why the overlay `.ini` files are still needed

The `spel.dat` patch fixes the 3D world, but the HUD uses separate overlay configuration files.

Without the overlay fix, the HUD can look stretched or misplaced even when the 3D scene is correct.

Use the overlay files together with the patched executable.

## Troubleshooting

### The screen goes black and the game crashes when a race starts

That is the texture memory probe overflowing on a modern graphics card (more than ~128 MB of VRAM). Check that the bytes at `0x0BC0F0` are `C7 81 A1 02 00 00 00 00 00 04 C3`; see [Patch part 4](#patch-part-4-texture-memory-crash-fix).

### The game still opens in the old resolution

Check that all relevant mode-table entries were patched. The game has several repeated mode tables, so patching only one `640×480` or `800×600` entry may not be enough.

### The 3D image is stretched

Check the `fidiv` patch at `0x0C0E57`. It must divide by the 4:3 reference denominator at `0x005973D0`, not by the actual 16:9 width.

### The 3D image is zoomed or cropped

Check the horizontal clip constants. The 2560×1440 patch uses:

```text
-1.25 and 2.5
```

Using the wrong clip direction can produce Vert- behavior instead of Hor+ behavior.

### The HUD is stretched or misplaced

That is handled by the `overlay*.ini` files, not by the `spel.dat` 3D patch alone.

### Finish-result text position does not move through `.ini`

Testing showed me that the finish string entries read scale and color from the `.ini` files, but their position appears to be assigned by game code at runtime. This is a separate issue from the main 16:9 3D fix.
