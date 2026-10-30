# Technical notes: A2 Racer 4 `spel.dat` resolution patch

This document explains how `spel.dat` is modified so **A2 Racer 4** renders correctly at any resolution. Everything depends only on the chosen width `W` and height `H`. The examples use 2560×1440.

## Important background

A2 Racer 4 uses `spel.dat` as the executable module for the actual DirectDraw/Direct3D racing portion of the game. Even though the extension is `.dat`, it is a normal PE32 Windows executable.

The original game is designed around 4:3 display modes. If another display mode is forced, the game does not adapt by itself: the 3D view and the HUD both distort.

The patch:

1. sets the display-mode table to the chosen resolution;
2. keeps the vertical view of the Direct3D viewport at 4:3 and calculates the horizontal view from the screen shape;
3. makes the HUD use the 4:3 shape as well, and leaves its horizontal placement to the `overlay*.ini` files, which the patcher moves to the screen edges.

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
file offset 0x1973D0 -> VA 0x005973D0
```

## Summary of the patch

| Part | Change |
|---|---|
| 1 | Display-mode table set to `W`×`H` |
| 2 | Viewport divides by a stored 4:3 reference width `(H × 4 + 1) / 3` instead of `W` |
| 3 | Horizontal clip range becomes `±0.75 × W / H` |
| 4 | Texture memory crash fix, not related to the screen shape |
| 5 | HUD code uses the 4:3 reference width instead of `W`, in three places |

## Patch part 1: display-mode table

The original executable contains repeated display-mode entries such as:

```text
640×480
800×600
1024×768
1280×1024
1600×1200
```

For 2560×1440 those entries become:

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

The values are written as 32-bit floats. At 4:3 this gives the original `-1.0` and `2.0`. At 16:9 it gives `-1.3333` and `2.6667`.

| File offset | VA | Original | Patched for 16:9 |
|---|---|---|---|
| `0x0C0E8A` | `0x004C0E8A` | `C7 46 14 00 00 80 BF` | `C7 46 14 AB AA AA BF` |
| `0x0C0E96` | `0x004C0E96` | `C7 46 1C 00 00 00 40` | `C7 46 1C AB AA 2A 40` |

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
| `0x07CDD1` | `0x0047CDD1` | `DA 35 98 37 5B 00` | `DA 35 D0 73 59 00` |
| `0x07FE55` | `0x0047FE55` | `DB 05 98 37 5B 00` | `DB 05 D0 73 59 00` |
| `0x080534` | `0x00480534` | `DB 05 98 37 5B 00` | `DB 05 D0 73 59 00` |

Horizontally, HUD `x` reaches the screen edges where `0.99 / 320 × x - 1 = ±0.75 × W / H`. Compared with 4:3 the edges move by `(0.75 × W / H - 1) × 320 / 0.99`, which is the shift the patcher applies to elements attached to an edge. See [Overlay files](#overlay-files).

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

In HxD or 010 Editor, go to each display-mode table file offset listed above and overwrite the 16-bit little-endian values with your width and height. For 2560×1440 that is `00 0A` and `A0 05`.

### Step 4: create the 4:3 reference denominator

At file offset `0x1973D0`, write `(H × 4 + 1) / 3`, rounded down, as a 32-bit little-endian value. For a height of 1440 that is `1920`: `80 07 00 00`.

### Step 5: redirect the aspect division and the HUD

Make the changes from [Patch part 2](#patch-part-2-43-aspect-denominator) and [Patch part 5](#patch-part-5-hud-proportions).

### Step 6: set the horizontal clip range

At file offsets `0x0C0E8D` and `0x0C0E99`, write `-0.75 × W / H` and `1.5 × W / H` as 32-bit little-endian floats. A value for 16:9 is in [Patch part 3](#patch-part-3-horizontal-clip-range).

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

See [Overlay files](#overlay-files), or use `A2Racer4_DashboardFix.zip` on a 16:9 screen.

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
004c0e8a: c7 46 14 ab aa aa bf  mov    DWORD PTR [esi+0x14],0xbfaaaaab   ; 16:9
004c0e96: c7 46 1c ab aa 2a 40  mov    DWORD PTR [esi+0x1c],0x402aaaab   ; 16:9
```

### Step 3: patch with Python

This Python script applies the patch to an input `spel.dat`.

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
# For a height of 1440 this is 1920.
data[0x1973D0:0x1973D0 + 4] = struct.pack("<I", aspect_denominator)

def patch(offset, old, new, label):
    old = bytes.fromhex(old)
    new = bytes.fromhex(new)
    if data[offset:offset + len(old)] != old and data[offset:offset + len(new)] != new:
        raise RuntimeError(f"Unexpected bytes at {label}. Wrong executable version?")
    data[offset:offset + len(new)] = new

# Use the 4:3 reference width for the viewport and the HUD.
patch(0x0C0E57, "DA 35 98 37 5B 00", "DA 35 D0 73 59 00", "aspect division")
patch(0x07CDD1, "DA 35 98 37 5B 00", "DA 35 D0 73 59 00", "HUD scale")
patch(0x07FE55, "DB 05 98 37 5B 00", "DB 05 D0 73 59 00", "HUD position")
patch(0x080534, "DB 05 98 37 5B 00", "DB 05 D0 73 59 00", "HUD position")

# Horizontal clip range for this screen shape.
if data[0x0C0E8A:0x0C0E8D] != bytes.fromhex("C7 46 14") or data[0x0C0E96:0x0C0E99] != bytes.fromhex("C7 46 1C"):
    raise RuntimeError("Unexpected bytes at the clip range. Wrong executable version?")
data[0x0C0E8D:0x0C0E91] = struct.pack("<f", -0.75 * width / height)
data[0x0C0E99:0x0C0E9D] = struct.pack("<f", 1.5 * width / height)

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

Check that the `fidiv` line points to `0x5973d0` and the clip constants match your screen shape.

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

## Values for other resolutions

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

The HUD uses separate configuration files, `overlay*.ini`, on a 640×480 canvas. Only the `x` of `Position` changes, starting from the game's own files:

```text
shift = (0.75 × W / H - 1) × 320 / 0.99, rounded
```

- **Add the shift:** every section with `Parent = Speedometer`, and `STRING_RACE_TIME_VALUE`, `STRING_CUR_LAP` and `STRING_CUR_POS`.
- **Subtract the shift:** every section with `Parent = Communicator`, and every `OVL_PORTRAITS_*` and `PLAYER_*`.
- **Leave alone:** everything else, including `Scale`.

## Troubleshooting

### The screen goes black and the game crashes when a race starts

That is the texture memory probe overflowing on a modern graphics card (more than ~128 MB of VRAM). Check that the bytes at `0x0BC0F0` are `C7 81 A1 02 00 00 00 00 00 04 C3`; see [Patch part 4](#patch-part-4-texture-memory-crash-fix).

### The game still opens in the old resolution

Check that all relevant mode-table entries were patched. The game has several repeated mode tables, so patching only one `640×480` or `800×600` entry may not be enough.

### The 3D image is stretched

Check the `fidiv` patch at `0x0C0E57`. It must divide by the 4:3 reference denominator at `0x005973D0`, not by the actual 16:9 width.

### The 3D image is zoomed or cropped

Check the horizontal clip constants against the formula in [Patch part 3](#patch-part-3-horizontal-clip-range).

### The HUD is stretched or misplaced

Elements in the wrong place come from the `overlay*.ini` files. A squashed HUD means the three HUD changes in [Patch part 5](#patch-part-5-hud-proportions) are missing.

### Finish-result text position does not move through `.ini`

Testing showed me that the finish string entries read scale and color from the `.ini` files, but their position appears to be assigned by game code at runtime. This is a separate issue from the main 16:9 3D fix.
