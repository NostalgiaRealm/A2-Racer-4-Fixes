//go:build go1.16
// +build go1.16

package main

import "embed"

// Patched HUD layout files (the dashboard fix), installed next to spel.dat.
//
//go:embed overlays/*.ini
var overlayFiles embed.FS

// overlayNames lists the built-in overlay files in name order.
func overlayNames() ([]string, error) {
	entries, err := overlayFiles.ReadDir("overlays")
	if err != nil {
		return nil, err
	}

	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		names = append(names, entry.Name())
	}

	return names, nil
}

// overlayData returns the contents of a built-in overlay file.
func overlayData(name string) ([]byte, error) {
	return overlayFiles.ReadFile("overlays/" + name)
}
