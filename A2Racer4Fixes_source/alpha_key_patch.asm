; Code added to spel.dat by the transparency fix. Source for the cave bytes in
; A2Racer4Fixes.go and win32/A2Racer4Fixes_32bit.c.
;   nasm -f bin -o alpha_key_patch.bin alpha_key_patch.asm
;
; The game marks transparent texels with a color key on 16-bit textures. On some
; current drivers that shows black around objects. This code switches textures to
; a 16-bit format with alpha, clears alpha only on transparent texels, discards
; them with the alpha test and turns the color key off. Key and alpha test together
; broke all 3D on a Radeon 760M.

bits 32
org 0x575500

%define device_ptr    dword [0x73b4b4]  ; IDirect3DDevice2 *
%define cur_format    dword [0x73b82e]  ; selected texture format index
%define alpha_format  dword [0x73b826]  ; 16BPP_ALPHA format index, -1 if none
%define format_array  dword [0x73b7d8]  ; 0xb0-byte entries, DDPIXELFORMAT at +0x48
%define alpha_mask    dword [0x7409a8]  ; 0 unless current masks have alpha
%define blend_cache   dword [0x73b505]  ; cached D3DRENDERSTATE_TEXTUREMAPBLEND

SELECT_FORMAT equ 0x4c2b90

STATE_ALPHATESTENABLE  equ 0x0f
STATE_TEXTUREMAPBLEND  equ 0x15
STATE_ALPHAREF         equ 0x18
STATE_ALPHAFUNC        equ 0x19
STATE_COLORKEYENABLE   equ 0x29
STATE_ALPHABLENDENABLE equ 0x1b
TBLEND_MODULATE        equ 2
TBLEND_MODULATEALPHA   equ 4
CMP_GREATER            equ 5

%macro set_state 2
    push %2
    push %1
    mov eax, device_ptr
    push eax
    mov ecx, [eax]
    call [ecx+0x5c]
%endmacro

; Replaces the CALL to the format selector in the 3D init function.
; __cdecl, one argument: 3 selects 16BPP_RGB, 4 selects 16BPP_ALPHA.
select_texture_format:
    cmp dword [esp+4], 3
    jne .go
    mov eax, alpha_format
    cmp eax, -1
    je .go
    imul eax, eax, 0xb0
    add eax, format_array
    cmp dword [eax+0x54], 16            ; ddpf.dwRGBBitCount
    jne .go
    mov dword [esp+4], 4
    set_state STATE_ALPHAREF, 0
    set_state STATE_ALPHAFUNC, CMP_GREATER
    set_state STATE_ALPHATESTENABLE, 1
    set_state STATE_COLORKEYENABLE, 0
.go:
    mov eax, SELECT_FORMAT
    jmp eax

; Replaces the end of the 24-bit color converter (FUN_004c7ee0).
convert_24bit_end:
    add eax, esi
    pop esi
    pop ebx
    jmp set_alpha

; Replaces the end of the palette color converter (FUN_004c81b0, case 8).
convert_palette_end:
    pop ebx
    add eax, esi
    pop esi
; Only the transparent color converts to 0: the converters move any other
; color that lands on 0 off it.
set_alpha:
    test eax, eax
    jz .done
    or eax, alpha_mask
.done:
    ret

; Replace SetRenderState(device, ALPHABLENDENABLE, value) at every site that
; switches blending. Same stack contract as the COM call: three arguments,
; callee cleans up, returns the HRESULT.
;
; D3DTBLEND_MODULATE takes alpha from a texture that has alpha, ignoring vertex
; alpha, so blended draws need MODULATEALPHA to keep their translucency.
blend_keep_test:
    mov edx, 1
    jmp short blend_common
; For blended draws where alpha 0 can still be visible: the inverted blend of
; skidmarks and radar (fresh marks have alpha 0), and objects, whose blend modes
; include ONE/INVSRCCOLOR. Turning blending off turns the test back on.
blend_test_off:
    mov edx, [esp+12]
    test edx, edx
    setz dl
    movzx edx, dl
blend_common:
    push edx                            ; alpha test value
    push dword [esp+16]                 ; value
    push STATE_ALPHABLENDENABLE
    push dword [esp+16]                 ; device
    mov eax, [esp]
    mov ecx, [eax]
    call [ecx+0x5c]
    pop edx
    push eax                            ; keep the HRESULT
    mov eax, cur_format
    cmp eax, alpha_format
    jne .done
    push edx
    push STATE_ALPHATESTENABLE
    push dword [esp+16]                 ; device
    mov eax, [esp]
    mov ecx, [eax]
    call [ecx+0x5c]
    cmp blend_cache, TBLEND_MODULATE    ; the flash effect uses COPY: leave it
    jne .done
    mov eax, [esp+16]                   ; value
    neg eax
    sbb eax, eax
    and eax, TBLEND_MODULATEALPHA - TBLEND_MODULATE
    add eax, TBLEND_MODULATE
    push eax
    push STATE_TEXTUREMAPBLEND
    push dword [esp+16]                 ; device
    mov eax, [esp]
    mov ecx, [eax]
    call [ecx+0x5c]
.done:
    pop eax
    ret 12

; Replaces the call to IDirect3DViewport2::Clear, which clears the Z-buffer every
; frame. Same stack contract as the COM call: four arguments, callee cleans up,
; returns the HRESULT. A clear should not depend on the alpha test, so the test is
; off meanwhile. This alone did not fix the Radeon 760M, but the build confirmed
; there includes it and no build without it has been tried.
viewport_clear:
    mov eax, cur_format
    cmp eax, alpha_format
    jne .plain
    push eax                            ; room for the current alpha test value
    push esp
    push STATE_ALPHATESTENABLE
    mov eax, device_ptr
    push eax
    mov ecx, [eax]
    call [ecx+0x58]                     ; GetRenderState
    set_state STATE_ALPHATESTENABLE, 0
    push dword [esp+20]                 ; flags
    push dword [esp+20]                 ; rectangles
    push dword [esp+20]                 ; count
    push dword [esp+20]                 ; viewport
    mov eax, [esp]
    mov ecx, [eax]
    call [ecx+0x30]
    pop edx                             ; the saved alpha test value
    push eax                            ; keep the HRESULT
    set_state STATE_ALPHATESTENABLE, edx
    pop eax
    ret 16
.plain:
    mov eax, [esp+4]
    mov ecx, [eax]
    jmp [ecx+0x30]
