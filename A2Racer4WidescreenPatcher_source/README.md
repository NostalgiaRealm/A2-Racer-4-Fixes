# A2Racer4WidescreenPatcher source

This folder contains the Go source code for the patcher, `A2Racer4WidescreenPatcher`. Build the whole folder (`.`), not a single `.go` file:
- the patched HUD files in `overlays/` are built in with `go:embed` (`overlays_embed.go`), or as generated code for Go 1.10 (`gen_overlays_legacy.go`);
- `admin_windows.go` and `admin_other.go` hold the platform-specific parts;
- `rsrc_windows_amd64.syso` and `rsrc_windows_386.syso` add the Windows manifest that asks for administrator rights.

## Build on Windows

Install Go, then run:

```cmd
go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher.exe .
```

The 32-bit version is built on Linux, see [Compile the 32-bit versions](#compile-the-32-bit-versions). Those steps have not been tried on Windows.

## Cross-compile from Linux

```bash
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher.exe .
```
## Compile a native Linux version
```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher_linux_x86_64 .
```

## Compile the 32-bit versions

The 32-bit Windows version is built with Go 1.10.8, the last Go release that runs on Windows XP. Current Go versions build Windows binaries that need Windows 10 or newer. Download Go 1.10.8 from https://go.dev/dl/ and use its `go` command where the example says `go1.10.8`.

Stock Go 1.10.8 loads `winmm.dll` and `ws2_32.dll` from the program's own folder (CVE-2019-9634), which would let a stray DLL in Downloads run with the patcher's administrator rights. Later Go versions fixed this, so patch your Go 1.10.8 once with the backport of that fix. Only the Windows runtime changes:

```bash
patch -p1 -d "$(go1.10.8 env GOROOT)" < go110_runtime_dll_fix.diff
```

Go 1.10 ignores `go.mod` and has no `go:embed`, so generate the overlay data first. Any Go version can run the generator:

```bash
go run gen_overlays_legacy.go
```

```bash
GOROOT_FINAL=/usr/local/go GOOS=windows GOARCH=386 GO386=387 CGO_ENABLED=0 go1.10.8 build -gcflags="all='-trimpath=$PWD'" -ldflags="-s -w -buildid=" -o A2Racer4WidescreenPatcher_32bit.exe .
```

Go 1.10 has no `go build -trimpath`. `-gcflags` and `GOROOT_FINAL` keep the paths of your own folders out of the file instead. The inner quotes are needed when the path has spaces.

```bash
GOOS=linux GOARCH=386 GO386=softfloat CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o A2Racer4WidescreenPatcher_linux_32bit .
```

`GO386=387` and `GO386=softfloat` mean these versions need MMX but not SSE2, so they also run on older 32-bit processors. Current Go versions build Linux binaries that need Linux 3.2 or newer.

Release binaries are built from a clean git checkout of the tagged commit: the 32-bit Windows version with Go 1.10.8 from go.dev plus `go110_runtime_dll_fix.diff`, the others with Fedora 44's Go 1.26.10 package (`go version` prints `go1.26.10-X:nodwarf5`). Go 1.26 stamps the commit and whether the checkout is clean into the binary; `.gitignore` keeps the files built above from counting as changes. These steps give byte-identical files. Go 1.26.10 built from the upstream source does too, with `GOEXPERIMENT=nodwarf5` set.

## Windows manifest

`A2Racer4WidescreenPatcher.exe.manifest` (64-bit) and `A2Racer4WidescreenPatcher_32bit.exe.manifest` (32-bit) set `requireAdministrator`, so Windows asks for administrator rights before the patcher starts. The 32-bit one says `x86` and also lists Windows Vista, 7, 8 and 8.1 as supported. Windows XP ignores the request, so there the check in `admin_windows.go` is what stops a user without administrator rights. `rsrc_windows_amd64.syso` and `rsrc_windows_386.syso` are those manifests compiled as resources; Go links the one for the target architecture into Windows builds automatically, so a Windows architecture without its own `.syso` would lose the administrator prompt. After changing a manifest, regenerate its resource with MinGW's `windres` (for example from llvm-mingw or binutils):

```bash
x86_64-w64-mingw32-windres -O coff -i A2Racer4WidescreenPatcher.rc -o rsrc_windows_amd64.syso
```

```bash
x86_64-w64-mingw32-windres -F pe-i386 -O coff -i A2Racer4WidescreenPatcher_32bit.rc -o rsrc_windows_386.syso
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
