# A2Racer4WidescreenPatcher source

This folder contains the Go source code for `A2Racer4WidescreenPatcher.exe`. Build the whole folder (`.`), not a single `.go` file:
- the patched HUD files in `overlays/` are built in with `go:embed`;
- `admin_windows.go` and `admin_other.go` hold the platform-specific parts;
- `rsrc_windows_amd64.syso` adds the Windows manifest that asks for administrator rights.

## Build on Windows

Install Go, then run:

```cmd
go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher.exe .
```

## Cross-compile from Linux

```bash
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher.exe .
```
## Compile a native Linux version
```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher .
```

Current Go versions build Windows binaries that need Windows 10 or newer.

## Windows manifest

`A2Racer4WidescreenPatcher.exe.manifest` sets `requireAdministrator`, so Windows asks for administrator rights before the patcher starts. `rsrc_windows_amd64.syso` is that manifest compiled as a resource; Go links it into Windows builds automatically. After changing the manifest, regenerate it with MinGW's `windres` (for example from llvm-mingw):

```bash
x86_64-w64-mingw32-windres -O coff -i A2Racer4WidescreenPatcher.rc -o rsrc_windows_amd64.syso
```

## Usage

Run `A2Racer4WidescreenPatcher` from anywhere. It asks for:
- the A2 Racer 4 game folder, the one with `spel.dat`. Press Enter for the suggested folder: the patcher's own folder when `spel.dat` is there, otherwise the current folder;
- a resolution such as:

```text
2560x1440
```

The patcher creates a `4x3_backup` folder in the game folder, moves the original `spel.dat` into it, and writes a new widescreen-patched `spel.dat`. It then installs the patched overlay `.ini` files the same way:
- each replaced file is moved to `4x3_backup`, and an existing backup is never overwritten;
- files that are already up to date are skipped;
- `overlay7.ini` is only replaced when the "Schaduw" extra car update has installed one.

File names are matched case-insensitively, and quoted, escaped and `~` paths are accepted.

The patched file also contains the texture memory crash fix for modern graphics cards. Every code change is checked against the expected original bytes first, so an unknown `spel.dat` version is left untouched. Running the patcher on an already patched `spel.dat` updates it to the current patch.

On Windows the patcher only runs with administrator rights; without them it stops before changing anything. The Linux version needs no root rights, because the game lives in your own Wine prefix.

Nothing fails silently:
- every written file is read back and compared;
- every error names the file and says what state the game files are in;
- the exit code is 1 on failure;
- on Windows the window stays open until you press Enter whenever it would otherwise close.
