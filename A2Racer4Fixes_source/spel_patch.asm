; Code added to spel.dat, in unused space at the end of the code section. Source
; for the bytes in A2Racer4Fixes.go and win32/A2Racer4Fixes_32bit.c.
;   nasm -f bin -o spel_patch.bin spel_patch.asm
;
; Screen resolution: at startup the game takes the resolution of the display,
; or the one fixed by the patcher, and fills in everything that depends on it.
; This happens in memory only, so no file changes when the display changes.
;
; Transparency:
; The game marks transparent texels with a color key on 16-bit textures. On some
; current drivers that shows black around objects. This code switches textures to
; a 16-bit format with alpha, clears alpha only on transparent texels, discards
; them with the alpha test and turns the color key off. Key and alpha test together
; broke all 3D on a Radeon 760M.
;
; Car physics:
; The physics world steps at a fixed 66 Hz, but the game sets forces once per frame,
; and it kept its time in a float. See the code at the end for what that broke.

bits 32
org 0x575500

%define device_ptr    dword [0x73b4b4]  ; IDirect3DDevice2 *
%define cur_format    dword [0x73b82e]  ; selected texture format index
%define alpha_format  dword [0x73b826]  ; 16BPP_ALPHA format index, -1 if none
%define format_array  dword [0x73b7d8]  ; 0xb0-byte entries, DDPIXELFORMAT at +0x48
%define alpha_mask    dword [0x7409a8]  ; 0 unless current masks have alpha
%define blend_cache   dword [0x73b505]  ; cached D3DRENDERSTATE_TEXTUREMAPBLEND

%define screen_width  dword [0x5b3798]  ; the current display mode
%define screen_height dword [0x5b379c]
%define reference_width dword [0x5973d0] ; 4:3 width for this height

SELECT_FORMAT equ 0x4c2b90
INIT_MAIN     equ 0x4580e0
READ_VECTOR   equ 0x480f70
READ_INI_TEXT equ 0x4c3d10
PARENT_KEY    equ 0x5aa034

GetModuleHandleA equ 0x5760a0           ; import table slots
GetProcAddress   equ 0x5760fc
GetSystemMetrics equ 0x5761f4
GetVersion       equ 0x5760ac
QueryPerformanceCounter equ 0x576058
timeGetTime      equ 0x576250

GAME_TIMER_UPDATE equ 0x4a6700
GAME_TIMER_OBJECT equ 0x7128b0
GAME_TIME_STEP    equ 0x4a6800          ; returns the time step in st0
TIMER_FREQUENCY   equ 4                 ; float, in the timer object
TIMER_SECONDS     equ 8                 ; float
TIMER_STEP        equ 12                ; float

FLOAT_TO_INTEGER  equ 0x558524          ; takes st0, rounds toward zero, returns eax
STEP_WORLD_UNTIL  equ 0x4f8380          ; ecx = world, double on the stack
NORMALIZE_VECTOR  equ 0x4f9680          ; ecx = vector, returns its old length in st0
FLOAT_ONE         equ 0x576318
FORCE_SET_CONTINUE equ 0x4a5cbe
TRAILER_PUSH_CONTINUE equ 0x4a97f6

; Free memory after the game's data, in the last page of its data section.
LAST_FRAME   equ 0x751f00               ; counter at the start of the last frame
QPC_START    equ 0x751f10               ; counter when the game started
TICKS_START  equ 0x751f18               ; the same for timeGetTime
LAST_COUNT   equ 0x751f20               ; double, counter at the last timer update
WORLD_TIME   equ 0x751f28               ; double, seconds simulated
GAS_REST     equ 0x751f30               ; float, what the gas pedal value lost to rounding
BRAKE_REST   equ 0x751f34               ; float, the same for the brake

MODE_COUNT    equ 12

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

; Replaces the call to the game's init function in WinMain, whose two arguments
; stay on the stack.
startup:
    pushad
    push user32_name
    call [GetModuleHandleA]
    mov esi, eax
    test esi, esi
    jz .aware
    ; With Windows display scaling above 100%, Windows would otherwise scale what
    ; this process sees and shows only part of the picture. Not there before Vista.
    push dpi_aware_name
    push esi
    call [GetProcAddress]
    test eax, eax
    jz .aware
    call eax
.aware:
    mov ebx, [fixed_width]
    mov ebp, [fixed_height]
    test ebx, ebx
    jnz .fill
    sub esp, 156                        ; DEVMODEA
    mov edi, esp
    mov ecx, 39
    xor eax, eax
    rep stosd
    mov word [esp+36], 156              ; dmSize
    test esi, esi
    jz .metrics
    push enum_settings_name             ; spel.dat does not import it
    push esi
    call [GetProcAddress]
    test eax, eax
    jz .metrics
    push esp
    push -1                             ; ENUM_CURRENT_SETTINGS
    push 0                              ; the primary display
    call eax
    test eax, eax
    jz .metrics
    mov ebx, [esp+108]                  ; dmPelsWidth
    mov ebp, [esp+112]                  ; dmPelsHeight
    test ebx, ebx
    jz .metrics
    test ebp, ebp
    jnz .got
.metrics:
    push 0                              ; SM_CXSCREEN
    call [GetSystemMetrics]
    mov ebx, eax
    push 1                              ; SM_CYSCREEN
    call [GetSystemMetrics]
    mov ebp, eax
.got:
    add esp, 156
.fill:
    mov esi, mode_entries
    mov ecx, MODE_COUNT
.next_mode:
    lodsd
    mov [eax], ebx
    mov [eax+4], ebp
    loop .next_mode
    lea eax, [ebp*4+1]                  ; (height * 4 + 1) / 3
    xor edx, edx
    mov ecx, 3
    div ecx
    mov reference_width, eax
    popad
    jmp INIT_MAIN

; Replaces the two instructions that set the horizontal view in the viewport
; setup: with the vertical view fixed at +-0.75, +-0.75*width/height gives square
; pixels, and exactly +-1 at 4:3.
set_horizontal_view:
    push eax
    mov eax, screen_width
    lea eax, [eax+eax*2]
    push eax
    fild dword [esp]                    ; 3 * width
    mov eax, screen_height
    shl eax, 2
    mov [esp], eax
    fidiv dword [esp]                   ; / (4 * height)
    pop eax
    fld st0
    fchs
    fstp dword [esi+0x14]               ; x = -0.75 * width / height
    fadd st0, st0
    fstp dword [esi+0x1c]               ; width = 1.5 * width / height
    pop eax
    ret

; Replaces the call that reads an overlay element's Position. Same contract as
; that function: this in ecx, three arguments, callee cleans up. Elements attached
; to a screen edge move to that edge. The overlay files stay as they are.
read_position:
    push dword [esp+12]                 ; x, y, z
    push dword [esp+12]                 ; key
    push dword [esp+12]                 ; section
    call READ_VECTOR
    test al, al
    jz .out
    push eax                            ; keep the result
    mov eax, [esp+8]                    ; section
    mov eax, [eax+4]                    ; its text
    test eax, eax
    jz .keep
    call hud_edge
    test eax, eax
    jz .keep
    push eax
    call hud_shift
    pop ecx
    imul eax, ecx
    push eax
    fild dword [esp]
    pop eax
    mov ecx, [esp+16]                   ; x, y, z
    fadd dword [ecx]
    fstp dword [ecx]
.keep:
    pop eax
.out:
    ret 12

; How far HUD elements attached to a screen edge move, in the game's HUD units.
; The game places HUD x at x*0.99/320-1 in view space, and the view reaches
; +-0.75*width/height, so the edges move by (0.75*width/height-1)*320/0.99, which
; is 0 at 4:3. Returns it in eax, rounded.
hud_shift:
    mov eax, screen_width
    lea eax, [eax+eax*2]
    mov ecx, screen_height
    lea edx, [ecx*4]
    sub eax, edx
    imul eax, eax, 8000
    imul ecx, ecx, 99
    mov edx, ecx
    shr edx, 1
    test eax, eax
    jns .positive
    neg edx
.positive:
    add eax, edx
    cdq
    idiv ecx
    ret

; Which screen edge a HUD element is attached to: -1 left, 1 right, 0 for elements
; that stay centered or that the game places itself. Section name in eax, result
; in eax.
hud_edge:
    push esi
    push edi
    mov esi, eax
    sub esp, 64
    mov edx, esp
    push 64
    push edx
    push PARENT_KEY
    push esi
    call READ_INI_TEXT
    add esp, 16
    mov eax, esp
    mov edi, text_speedometer
    call text_equals
    jz .right
    mov eax, esi
    mov edi, text_race_time
    call text_equals
    jz .right
    mov eax, esi
    mov edi, text_cur_lap
    call text_equals
    jz .right
    mov eax, esi
    mov edi, text_cur_pos
    call text_equals
    jz .right
    mov eax, esp
    mov edi, text_communicator
    call text_equals
    jz .left
    mov eax, esi
    mov edi, text_portraits
    call text_starts_with
    jz .left
    mov eax, esi
    mov edi, text_player
    call text_starts_with
    jz .left
    xor eax, eax
    jmp short .done
.right:
    mov eax, 1
    jmp short .done
.left:
    or eax, -1
.done:
    add esp, 64
    pop edi
    pop esi
    ret

; Does the text in eax equal the uppercase text in edi, ignoring case? ZF set if
; so. Changes eax and ecx.
text_equals:
    call text_starts_with
    jnz .out
    cmp byte [eax], 0
.out:
    ret

; The same for only the start of the text. On a match eax points behind it.
text_starts_with:
    push edi
.next:
    mov cl, [edi]
    test cl, cl
    jz .out
    mov ch, [eax]
    cmp ch, 'a'
    jb .compare
    cmp ch, 'z'
    ja .compare
    sub ch, 32
.compare:
    cmp ch, cl
    jne .out
    inc eax
    inc edi
    jmp short .next
.out:
    pop edi
    ret

; Replaces the call to IDirectDraw::CreateSurface for the Z-buffer. Same contract
; as the COM call: four arguments, callee cleans up, returns the HRESULT. The game
; asks for 16 bits, which is too coarse for its 10 to 12500 view range, so surfaces
; close together flicker. Ask for more from Windows Vista on: older cards could
; refuse a Z-buffer of another depth than the 16-bit screen only when drawing.
create_zbuffer:
    push esi
    mov esi, [esp+12]                   ; surface description
    call [GetVersion]
    cmp al, 6
    jb .last_try
    mov dword [esi+0x18], 24            ; dwZBufferBitDepth
    call .create
    test eax, eax
    jz .done
    mov dword [esi+0x18], 32
    call .create
    test eax, eax
    jz .done
    mov dword [esi+0x18], 16
.last_try:
    call .create
.done:
    pop esi
    ret 16
.create:
    push dword [esp+24]
    push dword [esp+24]
    push dword [esp+24]
    push dword [esp+24]
    mov eax, [esp]
    mov ecx, [eax]
    call [ecx+0x18]
    ret

; Replaces both QueryPerformanceCounter calls of the game timer. That counter runs
; from when Windows started, which only adds a large number that means nothing here.
timer_counter:
    push dword [esp+4]
    call [QueryPerformanceCounter]
    test eax, eax
    jz .out
    mov ecx, [esp+4]
    mov eax, [QPC_START]
    or eax, [QPC_START+4]
    jnz .have_start
    mov eax, [ecx]
    mov [QPC_START], eax
    mov eax, [ecx+4]
    mov [QPC_START+4], eax
.have_start:
    mov eax, [ecx]
    mov edx, [ecx+4]
    sub eax, [QPC_START]
    sbb edx, [QPC_START+4]
    mov [ecx], eax
    mov [ecx+4], edx
    mov eax, 1
.out:
    ret 4

; The same for the timeGetTime calls, for the rare system without that counter.
timer_ticks:
    call [timeGetTime]
    cmp dword [TICKS_START+4], 0
    jne .have_start
    mov [TICKS_START], eax
    mov dword [TICKS_START+4], 1
.have_start:
    sub eax, [TICKS_START]
    ret

; Replaces how both timer functions turn the counter in st0 into time, with the timer
; object in esi. The game kept seconds in a 32-bit float and took the time step from
; that, so the step got noisy the longer the clock had run, and after weeks it was
; negative half of the time, which slows the whole world down and at high frame rates
; stops it. Take the step from the counter itself, so it is always exact.
timer_step:
    fld st0
    fsub qword [LAST_COUNT]
    fdiv dword [esi+TIMER_FREQUENCY]
    fstp dword [esi+TIMER_STEP]
    fst qword [LAST_COUNT]
    fdiv dword [esi+TIMER_FREQUENCY]
    fstp dword [esi+TIMER_SECONDS]
    ret

; Replaces the world step, with the world in ecx and the time step on the stack. It
; added up world time in a float as well, which loses precision over a long session.
world_step:
    fld dword [esp+4]
    mov eax, [esp+4]
    mov [ecx+0x78], eax
    fadd qword [WORLD_TIME]
    fst qword [WORLD_TIME]
    fst dword [ecx+0x74]
    sub esp, 8
    fstp qword [esp]
    mov ecx, [ecx+0x14]
    mov eax, STEP_WORLD_UNTIL
    call eax
    ret 4

; Returns in st0 the share of a whole push that this frame stands for. The game pushes
; traffic and trailers once per frame, with amounts that suit AI_FRAME_RATE frames per
; second: 25, the rate its turbo formula is written for. At a higher frame rate each
; frame gets its share. Below that rate a frame gets one whole push, as it always did.
; Without this traffic drives twice as hard at 50 frames per second, its force sits
; below the centre of mass, and from about 45 frames per second that lifts its nose.
frame_share:
    push eax
    push ecx
    mov ecx, GAME_TIMER_OBJECT
    mov eax, GAME_TIME_STEP
    call eax
    fmul dword [ai_frame_rate]
    fld1
    fcom st1
    fnstsw ax
    sahf
    jae .use_share
    fxch st1
.use_share:
    fstp st0
    pop ecx
    pop eax
    ret

; Replaces the division that gives the mass, in both functions that drive traffic. They
; use it for every force and push they apply, so this scales all of them.
traffic_mass:
    fdivr dword [FLOAT_ONE]
    call frame_share
    fmulp st1, st0
    ret

; Jumps here from the start of the push that trailers use, which has the push on the
; stack, for the same reason.
trailer_push:
    call frame_share
    fld st0
    fmul dword [esp+4]
    fstp dword [esp+4]
    fld st0
    fmul dword [esp+8]
    fstp dword [esp+8]
    fmul dword [esp+12]
    fstp dword [esp+12]
    push esi
    mov esi, ecx
    mov eax, [esi+0x10]
    push TRAILER_PUSH_CONTINUE
    ret

; Jumps here from where the game stores the force for the driving controller of a car,
; in ecx. Add it to what is waiting instead of replacing that, so nothing gets lost
; when several frames pass between two physics steps. The x and y are on the stack.
force_add:
    mov [esp+16], eax
    fld dword [esp+12]
    fchs
    fadd dword [ecx+0x84]
    fstp dword [ecx+0x84]
    fld dword [esp+8]
    fadd dword [ecx+0x80]
    fstp dword [ecx+0x80]
    fld dword [esp+16]
    fadd dword [ecx+0x88]
    fstp dword [ecx+0x88]
    push FORCE_SET_CONTINUE
    ret

; Replaces the call in the driving controller that checks the length of the force, with
; the force in ecx. That function also normalizes the force, so a force applied at full
; strength once, on the first physics step after each frame, and then as a vector of
; length 1. That is what ties the thrust of traffic, and the turbo of the player and
; the racers, to the frame rate. Apply it once and clear it, at any frame rate.
force_take:
    push ecx
    mov eax, NORMALIZE_VECTOR
    call eax
    pop ecx
    xor eax, eax
    mov [ecx], eax
    mov [ecx+4], eax
    mov [ecx+8], eax
    ret

; Replace the conversion to a whole number in the player's gas and brake pedals, with
; the old value plus this frame's step in st0. Above 300 frames per second that step
; is below 1 and got rounded away, so the pedal did nothing. Keep what is rounded off.
pedal_gas:
    mov ecx, GAS_REST
    jmp short pedal_value
pedal_brake:
    mov ecx, BRAKE_REST
pedal_value:
    fadd dword [ecx]
    fld st0
    mov eax, FLOAT_TO_INTEGER
    call eax
    push eax
    fisub dword [esp]
    pop eax
    fstp dword [ecx]
    ret

; Replaces the call to the game timer at the start of every frame, which has the timer
; object in ecx. Forces no longer depend on the frame rate, but some whole number
; counters still do: the fade of a trailer stops moving above 128 frames per second.
frame_limit:
    cmp dword [ecx], 0
    je .go                              ; no high resolution counter to wait with
    push ecx
    sub esp, 8
.again:
    push esp
    call [QueryPerformanceCounter]
    mov ecx, [esp+8]
    fild qword [esp]
    fild qword [LAST_FRAME]
    fsubp st1, st0
    fdiv dword [ecx+TIMER_FREQUENCY]
    fcomp dword [frame_time]
    fnstsw ax
    sahf
    jae .done
    mov eax, [LAST_FRAME]
    or eax, [LAST_FRAME+4]
    jz .done
    pause
    jmp short .again
.done:
    pop eax
    mov [LAST_FRAME], eax
    pop eax
    mov [LAST_FRAME+4], eax
    pop ecx
.go:
    jmp GAME_TIMER_UPDATE

ai_frame_rate:      dd __float32__(25.0)
frame_time:         dd __float32__(0.0083333333)
user32_name:        db "USER32.DLL", 0
enum_settings_name: db "EnumDisplaySettingsA", 0
dpi_aware_name:     db "SetProcessDPIAware", 0
text_speedometer:   db "SPEEDOMETER", 0
text_communicator:  db "COMMUNICATOR", 0
text_race_time:     db "STRING_RACE_TIME_VALUE", 0
text_cur_lap:       db "STRING_CUR_LAP", 0
text_cur_pos:       db "STRING_CUR_POS", 0
text_portraits:     db "OVL_PORTRAITS_", 0
text_player:        db "PLAYER_", 0

; The current display mode, then every 16-bit entry of the game's mode tables.
align 4
mode_entries:
    dd 0x5b3798, 0x5b37ec, 0x5b3800, 0x5b3814, 0x5b3864, 0x5b3878
    dd 0x5b388c, 0x5b38a0, 0x5b38b4, 0x5b3904, 0x5b3918, 0x5b392c

; 0 follows the display. The patcher writes a fixed resolution here on request.
fixed_width:  dd 0
fixed_height: dd 0
