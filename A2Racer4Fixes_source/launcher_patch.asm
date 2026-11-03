; Code added to A2Racer4.exe, in unused space at the end of the code section.
; Source for the bytes in A2Racer4Fixes.go and win32/A2Racer4Fixes_32bit.c.
;   nasm -f bin -o launcher_patch.bin launcher_patch.asm
;
; A2Racer4.exe covers the screen with a black window, then runs menu.exe and
; spel.dat in turn and waits for each to end, without handling the messages for
; its windows. The menu switches to 800x600 as it starts. Wine then sends
; WM_DISPLAYCHANGE to every window and waits up to 2 seconds for each to answer,
; unless their program has not checked its messages for a while. The launcher
; checks them just before it starts the menu, and its thread owns three windows:
; its own and two for text input (IME). So under Wine the menu stayed black for
; 6 seconds at startup and after every race. Now the launcher handles its
; messages while it waits.

bits 32
org 0x405900

WaitForSingleObject equ 0x406014        ; import table slots
GetModuleHandleA    equ 0x406060
GetProcAddress      equ 0x406050
PeekMessageA        equ 0x406110
TranslateMessage    equ 0x406108
DispatchMessageA    equ 0x4060d4
PostQuitMessage     equ 0x4060dc

WM_QUIT     equ 0x12
PM_REMOVE   equ 1
QS_ALLINPUT equ 0xff                    ; without QS_RAWINPUT, which older Windows refuses
INFINITE    equ -1

; Called instead of WaitForSingleObject(process, INFINITE) where the C library
; starts a program and waits for it (spawn with P_WAIT). Same arguments and result.
wait_for_process:
    push ebx
    push esi
    push edi
    sub esp, 28                         ; MSG
    mov ebx, [esp+44]                   ; the process
    push user32_name
    call [GetModuleHandleA]
    test eax, eax
    jz .plain_wait
    push wait_name
    push eax
    call [GetProcAddress]
    test eax, eax
    jz .plain_wait
    mov esi, eax                        ; MsgWaitForMultipleObjects
    mov edi, esp
.handle_messages:
    push PM_REMOVE
    push 0
    push 0
    push 0
    push edi
    call [PeekMessageA]
    test eax, eax
    jz .wait
    cmp dword [edi+4], WM_QUIT
    je .quit
    push edi
    call [TranslateMessage]
    push edi
    call [DispatchMessageA]
    jmp .handle_messages
.wait:
    push QS_ALLINPUT
    push INFINITE
    push 0                              ; any of the objects
    lea eax, [esp+56]                   ; the process argument
    push eax
    push 1
    call esi
    cmp eax, 1                          ; WAIT_OBJECT_0 + 1: messages came in
    je .handle_messages
    test eax, eax                       ; WAIT_OBJECT_0: the program ended
    jz .done
    jmp .plain_wait
.quit:
    push dword [edi+8]                  ; leave WM_QUIT for the launcher's own loop
    call [PostQuitMessage]
.plain_wait:
    push INFINITE
    push ebx
    call [WaitForSingleObject]
.done:
    add esp, 28
    pop edi
    pop esi
    pop ebx
    ret 8

user32_name db "USER32.DLL", 0
wait_name   db "MsgWaitForMultipleObjects", 0
