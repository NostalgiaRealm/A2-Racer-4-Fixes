# A2Racer4WidescreenPatcher source

This folder contains the Go source code for `A2Racer4WidescreenPatcher.exe`.

The patched HUD files in `overlays/` are built into the patcher with `go:embed`, so build from inside this folder.

## Build on Windows

Install Go, then run:

```cmd
go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher.exe A2Racer4WidescreenPatcher.go
```

## Cross-compile from Linux

```bash
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher.exe A2Racer4WidescreenPatcher.go
```
## Compile a native Linux version
```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher A2Racer4WidescreenPatcher.go
```

Current Go versions build Windows binaries that need Windows 10 or newer.

## Usage

Run `A2Racer4WidescreenPatcher` from anywhere. It asks for the A2 Racer 4 game folder, the one with `spel.dat` (press Enter for the current folder), and for a resolution such as:

```text
2560x1440
```

The patcher creates a `4x3_backup` folder in the game folder, moves the original `spel.dat` into it, and writes a new widescreen-patched `spel.dat`. It then installs the patched overlay `.ini` files the same way:
- each replaced file is moved to `4x3_backup`, and an existing backup is never overwritten;
- files that are already up to date are skipped;
- `overlay7.ini` is only replaced when the "Schaduw" extra car update has installed one.

File names are matched case-insensitively, and quoted, escaped and `~` paths are accepted.

The patched file also contains the texture memory crash fix for modern graphics cards. Every code change is checked against the expected original bytes first, so an unknown `spel.dat` version is left untouched. Running the patcher on an already patched `spel.dat` updates it to the current patch.
