package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	patcherVersion = "1.0.4"
	gameFileName   = "spel.dat"
	backupDir      = "4x3_backup"
)

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
	fmt.Println("A2 Racer 4 Widescreen Patcher v" + patcherVersion)
	fmt.Println("--------------------------------")
	fmt.Println("Run this patcher from the folder containing spel.dat.")
	fmt.Println()

	width, height, err := askResolution()
	if err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}

	if err := patchInPlace(width, height); err != nil {
		fmt.Println()
		fmt.Println("Patch failed:", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Printf("Done. Created patched %s for %dx%d.\n", gameFileName, width, height)
	fmt.Println("The texture memory crash fix for modern graphics cards is included.")
	fmt.Println("Original file was moved to the 4x3_backup folder.")
}

func askResolution() (int, int, error) {
	reader := bufio.NewReader(os.Stdin)
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

func patchInPlace(width int, height int) error {
	inputPath := filepath.Join(".", gameFileName)

	data, err := os.ReadFile(inputPath)
	if err != nil {
		return fmt.Errorf("could not read %s: %w", gameFileName, err)
	}

	if len(data) < 0x1B3932 {
		return fmt.Errorf("%s is smaller than expected; wrong file?", gameFileName)
	}

	if len(data) < 2 || data[0] != 'M' || data[1] != 'Z' {
		return fmt.Errorf("%s does not look like a Windows PE executable", gameFileName)
	}

	patched := make([]byte, len(data))
	copy(patched, data)

	if err := applyWidescreenPatch(patched, width, height); err != nil {
		return err
	}

	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return fmt.Errorf("could not create %s folder: %w", backupDir, err)
	}

	backupPath := filepath.Join(backupDir, gameFileName)
	if _, err := os.Stat(backupPath); err == nil {
		stamp := time.Now().Format("20060102_150405")
		backupPath = filepath.Join(backupDir, "spel_"+stamp+".dat")
	}

	if err := os.Rename(inputPath, backupPath); err != nil {
		return fmt.Errorf("could not move original %s to %s: %w", gameFileName, backupPath, err)
	}

	if err := os.WriteFile(inputPath, patched, 0644); err != nil {
		// Try to restore the original if writing fails.
		_ = os.Rename(backupPath, inputPath)
		return fmt.Errorf("could not write patched %s; original was restored if possible: %w", gameFileName, err)
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
