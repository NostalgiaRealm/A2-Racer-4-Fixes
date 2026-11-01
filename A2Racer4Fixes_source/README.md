# A2Racer4Fixes source

This folder contains the source code for the patcher, `A2Racer4Fixes`. The 64-bit Windows and both Linux versions are written in Go. Build the whole folder (`.`), not a single `.go` file:
- `admin_windows.go` and `admin_other.go` hold the platform-specific parts;
- `rsrc_windows_amd64.syso` adds the Windows manifest that asks for administrator rights;
- `spel_patch.asm` is the source of the code added to `spel.dat`, whose bytes are in both patchers. Rebuild it with `nasm -f bin -o spel_patch.bin spel_patch.asm`;
- `win32/` holds the separate C version for 32-bit Windows, which covers the systems current Go cannot target.

## Build on Windows

Install Go, then run:

```cmd
go build -trimpath -ldflags="-s -w" -o A2Racer4Fixes.exe .
```

## Cross-compile from Linux

```bash
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4Fixes.exe .
```
## Compile a native Linux version
```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4Fixes_linux_x86_64 .
```

## Compile the 32-bit Linux version

```bash
GOOS=linux GOARCH=386 GO386=softfloat CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4Fixes_linux_32bit .
```

`GO386=softfloat` means this version needs MMX but not SSE2, so it also runs on older 32-bit processors. Current Go versions build Linux binaries that need Linux 3.2 or newer, and Windows binaries that need Windows 10 or newer.

## Compile the 32-bit Windows version

Current Go versions don't run on anything older than Windows 10, and Go has never supported Windows 9x, so `win32/A2Racer4Fixes_32bit.c` is a separate program with the same patches and messages. It imports only functions that exist since Windows 95, looks up anything newer at runtime, and uses no C runtime. Any change to the patcher has to go into both versions, and their output has to be compared before a release.

Build it in the `win32` folder with llvm-mingw. Release binaries use llvm-mingw 20261006:

```bash
i686-w64-mingw32-windres A2Racer4Fixes_32bit.rc -O coff -o resources.o
```

```bash
i686-w64-mingw32-clang -march=i486 -Os -nostdlib -ffreestanding -fno-builtin -fno-stack-protector -fno-asynchronous-unwind-tables -mno-stack-arg-probe A2Racer4Fixes_32bit.c resources.o -o A2Racer4Fixes_32bit.exe -lkernel32 -luser32 -s -Wl,-e,_start@0 -Wl,--subsystem,console:4.0 -Wl,--major-os-version=4 -Wl,--minor-os-version=0 -Wl,--disable-dynamicbase -Wl,--disable-nxcompat -Wl,--disable-tsaware -Wl,--no-insert-timestamp
```

## Reproducing release binaries

Release binaries are built from a clean git checkout of the tagged commit. The Go versions use Fedora 44's Go 1.26.10 package (`go version` prints `go1.26.10-X:nodwarf5`). Go stamps the commit and whether the checkout is clean into the binary; `.gitignore` keeps the files built above from counting as changes. These steps give byte-identical files. Go 1.26.10 built from the upstream source does too, with `GOEXPERIMENT=nodwarf5` set.

## Windows manifest

`A2Racer4Fixes.exe.manifest` (64-bit) and `win32/A2Racer4Fixes_32bit.exe.manifest` (32-bit) set `requireAdministrator`, so Windows Vista and newer ask for administrator rights before the patcher starts. The 32-bit one says `x86` and also lists Windows Vista, 7, 8 and 8.1 as supported. Older Windows ignores the request, so on Windows XP the patcher's own check is what stops a user without administrator rights. `rsrc_windows_amd64.syso` is the 64-bit manifest compiled as a resource; Go links it into 64-bit Windows builds automatically. After changing it, regenerate it with MinGW's `windres`:

```bash
x86_64-w64-mingw32-windres -O coff -i A2Racer4Fixes.rc -o rsrc_windows_amd64.syso
```

## Usage

Run `A2Racer4Fixes` from anywhere. It asks for:
- the A2 Racer 4 game folder, the one with `spel.dat`. Press Enter for the suggested folder: the patcher's own folder when `spel.dat` is there, otherwise the current folder;
- a resolution: press Enter to follow the display, or type a fixed one such as:

```text
2560x1440
```

The patcher creates a `4x3_backup` folder in the game folder, moves the original `spel.dat` into it, and writes a new patched `spel.dat`. A `spel.dat` from an older version with other added code is rebuilt from the copy in `4x3_backup`.

The resolution is not in the patched file unless you fix one: the added code reads it when the game starts, see `spel_patch.asm`. Overlay `.ini` files stay as the game ships them. Where an older version changed them, the patcher puts them back:
- the original comes from `4x3_backup` after an earlier run, otherwise from the game folder, and a file an older HUD fix changed is refused;
- each replaced file is moved to `4x3_backup`, and an existing backup is never overwritten;
- files that are already the original are skipped;
- a missing `overlay7.ini` is fine, since only the "Schaduw" extra car update brings it.

File names are matched case-insensitively, and quoted, escaped and `~` paths are accepted. The 32-bit Windows version uses the non-Unicode file functions, so a game folder with characters outside the system's code page gives an error there.

The patched file also contains the texture memory crash fix for modern graphics cards, the transparency fix, the CD check removal, the deeper Z-buffer, the car physics fixes, the 32-bit display mode, the check for cars that get hung up and the fix for contacts in the physics engine. The patcher also moves `menu.exe` to `4x3_backup` and writes a copy without the CD check; a file that already has the change is left alone. Every code change is checked against the expected original bytes first, so an unknown `spel.dat` version is left untouched. Running the patcher on an already patched `spel.dat` updates it to the current patch.

On Windows the patcher only runs with administrator rights; without them it stops before changing anything. Windows 95, 98 and Me have no such rights. The Linux version needs no root rights, because the game lives in your own Wine prefix.

Nothing fails silently:
- every written file is read back and compared;
- every error names the file and says what state the game files are in;
- the exit code is 1 on failure;
- on Windows the window stays open until you press Enter whenever it would otherwise close.
