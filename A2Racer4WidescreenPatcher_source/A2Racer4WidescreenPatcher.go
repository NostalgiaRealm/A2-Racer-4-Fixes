package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	patcherVersion  = "1.0.8"
	gameFileName    = "spel.dat"
	backupDir       = "4x3_backup"
	extraCarOverlay = "overlay7.ini"
)

// The 32-bit Windows version is built with Go 1.10, the last release that runs
// on Windows XP, so this code sticks to what Go 1.10 has: ioutil and %v instead
// of their newer replacements. The patched HUD files reach overlayNames and
// overlayData through overlays_embed.go or, for Go 1.10, gen_overlays_legacy.go.

var widthOffsets = []int{
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
}

var heightOffsets = []int{
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
}

func main() {
	ok := run()
	waitBeforeClosing()
	if !ok {
		os.Exit(1)
	}
}

// run does the actual work. Every failure is reported, together with what it
// means for the game files, so the patcher never fails silently.
func run() bool {
	fmt.Println("A2 Racer 4 Widescreen Patcher v" + patcherVersion)
	fmt.Println("--------------------------------")
	fmt.Println()

	if err := checkAdmin(); err != nil {
		fmt.Println("Error:", err)
		fmt.Println("Nothing was changed.")
		return false
	}

	reader := bufio.NewReader(os.Stdin)

	gameDir, err := askGameDir(reader)
	if err != nil {
		fmt.Println("Error:", err)
		fmt.Println("Nothing was changed.")
		return false
	}

	width, height, err := askResolution(reader)
	if err != nil {
		fmt.Println("Error:", err)
		fmt.Println("Nothing was changed.")
		return false
	}

	if err := patchInPlace(gameDir, width, height); err != nil {
		fmt.Println()
		fmt.Println("Patch failed:", err)
		return false
	}

	fmt.Println()
	fmt.Printf("Created patched %s for %dx%d.\n", gameFileName, width, height)
	fmt.Println("The texture memory crash fix for modern graphics cards is included.")
	fmt.Println()

	if err := installOverlays(gameDir); err != nil {
		fmt.Println()
		fmt.Println("Copying the HUD files failed:", err)
		fmt.Println(gameFileName + " is patched, but not every HUD file was installed.")
		fmt.Println("Fix the problem and run the patcher again.")
		return false
	}

	fmt.Println()
	fmt.Println("Done. Original files were moved to the " + backupDir + " folder in:")
	fmt.Println("  " + gameDir)
	return true
}

// waitBeforeClosing keeps a console window that closes together with the
// patcher open, so the result can always be read.
func waitBeforeClosing() {
	if !consoleWillClose() {
		return
	}

	fmt.Println()
	fmt.Print("Press Enter to close.")
	_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
}

// askGameDir asks for the game folder instead of assuming the current one,
// because installations differ, especially in Wine prefixes on Linux.
func askGameDir(reader *bufio.Reader) (string, error) {
	suggested := defaultGameDir()

	fmt.Println("Enter the A2 Racer 4 game folder (the folder that contains spel.dat).")
	fmt.Println("Press Enter to use this folder:")
	fmt.Println("  " + suggested)
	fmt.Print("Game folder: ")

	line, err := reader.ReadString('\n')
	if err != nil && len(line) == 0 {
		return "", err
	}

	dir := cleanPath(line)
	if dir == "" {
		dir = suggested
	}

	// Terminals on Linux often escape spaces and brackets when a folder is
	// dragged in, e.g. Program\ Files\ \(x86\).
	if _, err := os.Stat(dir); err != nil && runtime.GOOS != "windows" && strings.Contains(dir, `\`) {
		dir = filepath.Clean(regexp.MustCompile(`\\(.)`).ReplaceAllString(dir, "$1"))
	}

	info, err := os.Stat(dir)
	if err != nil || !info.IsDir() {
		return "", fmt.Errorf("%s is not a folder", dir)
	}

	if _, found := findFile(dir, gameFileName); !found {
		return "", fmt.Errorf("there is no %s in %s. Choose the A2 Racer 4 game folder", gameFileName, dir)
	}

	fmt.Println()
	return dir, nil
}

// defaultGameDir suggests the folder the patcher itself is in when spel.dat is
// there, since Windows does not always start programs that need administrator
// rights in their own folder. Otherwise it falls back to the current folder.
func defaultGameDir() string {
	var candidates []string

	if exe, err := os.Executable(); err == nil {
		if resolved, err := filepath.EvalSymlinks(exe); err == nil {
			exe = resolved
		}
		candidates = append(candidates, filepath.Dir(exe))
	}

	if current, err := os.Getwd(); err == nil {
		candidates = append(candidates, current)
	}

	for _, dir := range candidates {
		if _, found := findFile(dir, gameFileName); found {
			return dir
		}
	}

	if len(candidates) > 0 {
		return candidates[len(candidates)-1]
	}

	return "."
}

// writeVerified writes data and reads it back, so a write that silently did
// not happen, for example because a virus scanner undid it, is reported.
func writeVerified(path string, data []byte) error {
	if err := ioutil.WriteFile(path, data, 0644); err != nil {
		return err
	}

	written, err := ioutil.ReadFile(path)
	if err != nil {
		return fmt.Errorf("could not read %s back after writing: %v", path, err)
	}

	if !bytes.Equal(written, data) {
		return fmt.Errorf("%s does not contain the patched data after writing", path)
	}

	return nil
}

// cleanPath accepts a folder the way people tend to enter it: surrounded by
// quotes (drag and drop) or starting with ~ for the home folder.
func cleanPath(input string) string {
	path := strings.TrimSpace(input)

	if len(path) >= 2 && (path[0] == '"' || path[0] == '\'') && path[len(path)-1] == path[0] {
		path = path[1 : len(path)-1]
	}

	if path == "~" || strings.HasPrefix(path, "~/") {
		if home := userHomeDir(); home != "" {
			path = filepath.Join(home, path[1:])
		}
	}

	if path == "" {
		return ""
	}

	return filepath.Clean(path)
}

// userHomeDir returns the home folder, or "" when it is unknown.
func userHomeDir() string {
	if runtime.GOOS == "windows" {
		return os.Getenv("USERPROFILE")
	}

	return os.Getenv("HOME")
}

// findFile looks up name in dir ignoring case, so SPEL.DAT is found as well
// on case-sensitive Linux file systems. It only stats the matching name, so one
// unreadable file elsewhere in the folder cannot hide spel.dat.
func findFile(dir string, name string) (string, bool) {
	if f, err := os.Open(dir); err == nil {
		names, err := f.Readdirnames(-1)
		f.Close()
		if err == nil {
			sort.Strings(names)
			for _, entry := range names {
				if strings.EqualFold(entry, name) {
					path := filepath.Join(dir, entry)
					if info, err := os.Lstat(path); err != nil || !info.IsDir() {
						return path, true
					}
				}
			}
		}
	}

	return filepath.Join(dir, name), false
}

// backupPathFor returns where an original file is moved to. An existing
// backup is never overwritten, since it may hold the untouched 4:3 file.
func backupPathFor(gameDir string, name string) (string, error) {
	dir := filepath.Join(gameDir, backupDir)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("could not create %s folder: %v", backupDir, err)
	}

	path := filepath.Join(dir, name)
	if _, err := os.Stat(path); err == nil {
		stamp := time.Now().Format("20060102_150405")
		ext := filepath.Ext(name)
		path = filepath.Join(dir, strings.TrimSuffix(name, ext)+"_"+stamp+ext)
	}

	return path, nil
}

func askResolution(reader *bufio.Reader) (int, int, error) {
	fmt.Print("Enter desired 16:9 resolution, for example 2560x1440: ")

	line, err := reader.ReadString('\n')
	if err != nil && len(line) == 0 {
		return 0, 0, err
	}

	line = strings.TrimSpace(line)

	re := regexp.MustCompile(`(?i)^\s*([0-9]{3,5})\s*x\s*([0-9]{3,5})\s*$`)
	matches := re.FindStringSubmatch(line)
	if matches == nil {
		return 0, 0, fmt.Errorf("invalid resolution format. Use something like 2560x1440")
	}

	width, err := strconv.Atoi(matches[1])
	if err != nil {
		return 0, 0, err
	}

	height, err := strconv.Atoi(matches[2])
	if err != nil {
		return 0, 0, err
	}

	if width <= 0 || height <= 0 || width > 65535 || height > 65535 {
		return 0, 0, fmt.Errorf("resolution values must be between 1 and 65535")
	}

	// The patch was designed for 16:9. Warn, but do not reject, so custom 16:9-ish
	// modes like 1366x768 can still be tested.
	aspect := float64(width) / float64(height)
	if aspect < 1.70 || aspect > 1.82 {
		fmt.Printf("Warning: %dx%d is not very close to 16:9. Continuing anyway.\n", width, height)
	}

	return width, height, nil
}

func patchInPlace(gameDir string, width int, height int) error {
	inputPath, _ := findFile(gameDir, gameFileName)

	// Everything up to moving the original happens before spel.dat is touched.
	unchanged := func(err error) error {
		return fmt.Errorf("%v. Nothing was changed", err)
	}

	data, err := ioutil.ReadFile(inputPath)
	if err != nil {
		return unchanged(fmt.Errorf("could not read %s: %v", gameFileName, err))
	}

	if len(data) < 0x1B3932 {
		return unchanged(fmt.Errorf("%s is smaller than expected; wrong file?", gameFileName))
	}

	if len(data) < 2 || data[0] != 'M' || data[1] != 'Z' {
		return unchanged(fmt.Errorf("%s does not look like a Windows PE executable", gameFileName))
	}

	patched := make([]byte, len(data))
	copy(patched, data)

	if err := applyWidescreenPatch(patched, width, height); err != nil {
		return unchanged(err)
	}

	backupPath, err := backupPathFor(gameDir, filepath.Base(inputPath))
	if err != nil {
		return unchanged(err)
	}

	if err := os.Rename(inputPath, backupPath); err != nil {
		return unchanged(fmt.Errorf("could not move original %s to %s: %v", gameFileName, backupPath, err))
	}

	if err := writeVerified(inputPath, patched); err != nil {
		// Try to restore the original if writing fails.
		if restoreErr := os.Rename(backupPath, inputPath); restoreErr != nil {
			return fmt.Errorf("could not write patched %s: %v. The original is still in %s", gameFileName, err, backupPath)
		}
		return fmt.Errorf("could not write patched %s: %v. The original %s was put back", gameFileName, err, gameFileName)
	}

	return nil
}

// installOverlays copies the patched HUD overlay files into the game folder
// and moves the files they replace to the backup folder. overlay7.ini comes
// with the "Schaduw" extra car update, which would overwrite it again, so it
// is only replaced when that update is already installed.
func installOverlays(gameDir string) error {
	names, err := overlayNames()
	if err != nil {
		return err
	}

	for _, name := range names {
		data, err := overlayData(name)
		if err != nil {
			return err
		}

		target, exists := findFile(gameDir, name)

		if name == extraCarOverlay && !exists {
			fmt.Printf("Skipped %s: the \"Schaduw\" extra car update is not installed.\n", name)
			fmt.Println("  Install that update first, then run the patcher again.")
			continue
		}

		backupPath := ""
		if exists {
			current, err := ioutil.ReadFile(target)
			if err != nil {
				return fmt.Errorf("could not read %s: %v", target, err)
			}

			if bytes.Equal(current, data) {
				fmt.Printf("%s is already up to date.\n", name)
				continue
			}

			backupPath, err = backupPathFor(gameDir, filepath.Base(target))
			if err != nil {
				return err
			}

			if err := os.Rename(target, backupPath); err != nil {
				return fmt.Errorf("could not move original %s to %s: %v", name, backupPath, err)
			}
		}

		if err := writeVerified(target, data); err != nil {
			// Try to restore the original if writing fails.
			if backupPath != "" {
				if restoreErr := os.Rename(backupPath, target); restoreErr != nil {
					return fmt.Errorf("could not write %s: %v. The original is still in %s", name, err, backupPath)
				}
			}
			return fmt.Errorf("could not write %s: %v", name, err)
		}

		fmt.Printf("Installed %s\n", name)
	}

	return nil
}

func applyWidescreenPatch(data []byte, width int, height int) error {
	putU16 := func(offset int, value uint16) error {
		if offset < 0 || offset+2 > len(data) {
			return fmt.Errorf("offset 0x%X is outside the file", offset)
		}
		binary.LittleEndian.PutUint16(data[offset:offset+2], value)
		return nil
	}

	putU32 := func(offset int, value uint32) error {
		if offset < 0 || offset+4 > len(data) {
			return fmt.Errorf("offset 0x%X is outside the file", offset)
		}
		binary.LittleEndian.PutUint32(data[offset:offset+4], value)
		return nil
	}

	patchBytes := func(offset int, original []byte, replacement []byte, label string) error {
		if offset < 0 || offset+len(replacement) > len(data) {
			return fmt.Errorf("%s offset 0x%X is outside the file", label, offset)
		}

		current := data[offset : offset+len(replacement)]

		if bytes.Equal(current, replacement) {
			return nil // already patched
		}

		if !bytes.Equal(current, original) {
			return fmt.Errorf("%s bytes did not match expected original pattern at 0x%X. This may be the wrong spel.dat version", label, offset)
		}

		copy(current, replacement)
		return nil
	}

	for _, offset := range widthOffsets {
		if err := putU16(offset, uint16(width)); err != nil {
			return err
		}
	}

	for _, offset := range heightOffsets {
		if err := putU16(offset, uint16(height)); err != nil {
			return err
		}
	}

	// Keep a 4:3 projection reference width for the chosen output height.
	// Examples:
	// 1080 -> 1440
	// 1440 -> 1920
	// 2160 -> 2880
	aspectDenominator := uint32((height*4 + 1) / 3)

	if err := putU32(0x1973D0, aspectDenominator); err != nil {
		return err
	}

	// Redirect viewport aspect division:
	// fidiv dword ptr ds:0x005B3798 -> fidiv dword ptr ds:0x005973D0
	if err := patchBytes(
		0x0C0E57,
		[]byte{0xDA, 0x35, 0x98, 0x37, 0x5B, 0x00},
		[]byte{0xDA, 0x35, 0xD0, 0x73, 0x59, 0x00},
		"aspect division",
	); err != nil {
		return err
	}

	// Candidate J horizontal clip tuning:
	// -1.0 -> -1.25
	if err := patchBytes(
		0x0C0E8A,
		[]byte{0xC7, 0x46, 0x14, 0x00, 0x00, 0x80, 0xBF},
		[]byte{0xC7, 0x46, 0x14, 0x00, 0x00, 0xA0, 0xBF},
		"horizontal clip x",
	); err != nil {
		return err
	}

	// 2.0 -> 2.5
	if err := patchBytes(
		0x0C0E96,
		[]byte{0xC7, 0x46, 0x1C, 0x00, 0x00, 0x00, 0x40},
		[]byte{0xC7, 0x46, 0x1C, 0x00, 0x00, 0x20, 0x40},
		"horizontal clip width",
	); err != nil {
		return err
	}

	// Texture memory crash fix (not widescreen related):
	// at race start the game measures texture memory by creating 256x256 video
	// memory textures until CreateSurface fails, keeping them in a 1024-entry
	// stack array. With more than ~128 MB of VRAM that array overflows and the
	// game crashes. Skip the probe and report 64 MB instead; the game still uses
	// min(custom_texture_memory, measured):
	// mov eax, 0x1000 / call 0x00559400 / push ebx -> mov dword ptr [ecx+0x2A1], 0x04000000 / ret
	if err := patchBytes(
		0x0BC0F0,
		[]byte{0xB8, 0x00, 0x10, 0x00, 0x00, 0xE8, 0x06, 0xD3, 0x09, 0x00, 0x53},
		[]byte{0xC7, 0x81, 0xA1, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0xC3},
		"texture memory probe",
	); err != nil {
		return err
	}

	return nil
}
