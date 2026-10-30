//go:build !windows
// +build !windows

package main

// checkAdmin needs nothing outside Windows: on Linux the game lives in the
// user's own Wine prefix, and running as root would leave files behind that
// the game can no longer change.
func checkAdmin() error {
	return nil
}

// consoleWillClose is false because a terminal stays open after the patcher exits.
func consoleWillClose() bool {
	return false
}
