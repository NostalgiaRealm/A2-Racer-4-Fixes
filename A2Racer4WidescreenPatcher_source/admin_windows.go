//go:build windows

package main

import (
	"errors"
	"syscall"
	"unsafe"
)

// checkAdmin refuses to continue without administrator rights, which are
// needed to write into C:\Program Files. The embedded manifest makes Windows
// ask for them; this catches the cases where that request is bypassed. It
// checks for an enabled Administrators group: tokens that only carry it as
// "deny only" (no UAC elevation, restricted tokens) cannot write there.
func checkAdmin() error {
	administrators, err := syscall.StringToSid("S-1-5-32-544")
	if err != nil {
		return err
	}

	var member int32
	ok, _, callErr := syscall.NewLazyDLL("advapi32.dll").NewProc("CheckTokenMembership").Call(
		0, uintptr(unsafe.Pointer(administrators)), uintptr(unsafe.Pointer(&member)))
	if ok == 0 {
		return callErr
	}

	if member == 0 {
		return errors.New("the patcher needs administrator rights to write the game files. Right-click it and choose \"Run as administrator\"")
	}

	return nil
}

// consoleWillClose reports whether the patcher is alone in its console, as
// when it is started from Explorer. Windows closes that window as soon as the
// patcher exits.
func consoleWillClose() bool {
	var ids [2]uint32
	count, _, _ := syscall.NewLazyDLL("kernel32.dll").NewProc("GetConsoleProcessList").Call(
		uintptr(unsafe.Pointer(&ids[0])), uintptr(len(ids)))
	return count == 1
}
