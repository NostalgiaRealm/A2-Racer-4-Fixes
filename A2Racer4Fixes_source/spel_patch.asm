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
;
; Frame rate:
; The AI, the camera and many effects also count per frame what they mean per second.
; From 25 frames per second up they now do what they did at 25.

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
%define screen_depth  dword [0x5b37a0]
%define reference_width dword [REFERENCE_WIDTH]

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
CONVERT_COLOR     equ 0x4c81b0          ; color, its depth; returns the pixel in 16 bits
CONVERT_COLOR_FULL equ 0x4c7ee0         ; 24-bit color; returns the whole pixel
STEP_WORLD_UNTIL  equ 0x4f8380          ; ecx = world, double on the stack
NORMALIZE_VECTOR  equ 0x4f9680          ; ecx = vector, returns its old length in st0
FLOAT_ONE         equ 0x576318
FORCE_SET_CONTINUE equ 0x4a5cbe
TRAILER_PUSH_CONTINUE equ 0x4a97f6
IMAGE_FORMAT      equ 0x5c                ; pixel format, on the stack in image_pixel
FORMAT_BITS       equ 12                ; depth, in the pixel format
WHEEL_TIMER       equ 0x403170          ; ecx = controls, physics object on the stack
RESET_CAR         equ 0x40e5a0          ; car, its place on the road, 0
RACER_CONTROLS    equ 0x5cea7c          ; the controls of the first racer
RACER_CONTROLS_SIZE equ 0x294
CAR_TABLE         equ 0x715e50
OBJECT_TABLE      equ 0x73b0d0
CONTACT_RECHECK   equ 0x60              ; byte in a contact: is it still over its triangle?
CONTACT_STATE_CONTINUE equ 0x505ccc
REMOVE_CONTACTS   equ 0x4f2910          ; ecx = object, 1 on the stack
MOVE_OBJECT_CONTINUE equ 0x4f3136
WAYPOINT_UNLINK   equ 0x4a7020          ; car; takes it off the list of the waypoint it is on
WAYPOINT_TABLE    equ 0x715eb8
WAYPOINT_COUNT    equ 0x715ebc
RESET_HEIGHT      equ 0x576310          ; float 20, how high above the road the reset puts a car
SECTION_COUNT     equ 0x715f04
RESET_STAMP       equ 0x5d1b00          ; float, when the last reset took place
ENTER_RESET_RETURN equ 0x44d70a         ; where the Enter key's call of the reset returns
FLOAT_FIVE        equ 0x576308
FLOAT_TEN         equ 0x576358
SKID_ADD_SECTION  equ 0x444d20
SKID_FADE         equ 0x444f80
TYRE_SMOKE_FADE   equ 0x446730
DAMAGE_SMOKE_FADE equ 0x43d8f0
MUD_SPRAY         equ 0x45b670
WATER_SPRAY       equ 0x45b9d0
ANIMATION_STEP    equ 0x469c60
PICKUP_FADE       equ 0x478010
PARTICLE_RANDOM   equ 0x4602e0
ADD_BRAKE         equ 0x402e80
TURBO_STAMP       equ 0x6fba40          ; GetTickCount, when the tank last lost a unit

; Free memory after the game's data, in the last page of its data section.
LAST_FRAME   equ 0x751f00               ; counter at the start of the last frame
QPC_START    equ 0x751f10               ; counter when the game started
TICKS_START  equ 0x751f18               ; the same for timeGetTime
LAST_COUNT   equ 0x751f20               ; double, counter at the last timer update
WORLD_TIME   equ 0x751f28               ; double, seconds simulated
GAS_REST     equ 0x751f30               ; float, what the gas pedal value lost to rounding
BRAKE_REST   equ 0x751f34               ; float, the same for the brake
REFERENCE_WIDTH equ 0x751f38            ; 4:3 width for this height
FADE_REST    equ 0x751f3c               ; float, what the fade of a trailer lost to rounding
HUNG_TIMES   equ 0x751f40               ; floats, how long each car has hung, 20 in all
HUNG_TIME_COUNT equ 20
TICK         equ 0x751f90               ; byte, 1 in a frame where a tick of 25 Hz falls
TICK_REST    equ 0x751f94               ; float, time since the last tick
CAMERA_K     equ 0x751f98               ; floats, how far the camera moves this frame, 3 in all
COLOR_SEQUENCE equ 0x751fa4             ; steps through the values of color_round
FLASH_TIME   equ 0x751fa8               ; float, how long the flash of a speed camera has lasted

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
; Keeps all registers.
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

; The same for the fade of a trailer, which stopped moving above 128 frames per second.
trailer_fade:
    push ecx
    mov ecx, FADE_REST
    call pedal_value
    pop ecx
    ret

; Replaces reading the depth for the call that sets the display mode. Windows 8 and newer
; have no real 16-bit modes and convert every frame on its way to the screen, and that
; cost grows with the resolution. From Windows Vista on, as for the deeper Z-buffer, ask
; for 32 bits. The game keeps its own depth of 16, and its textures stay 16-bit.
display_depth:
    call [GetVersion]
    mov edx, screen_depth
    cmp edx, 16
    jne .done
    cmp al, 6
    jb .done
    mov edx, 32
.done:
    ret

; Replaces the conversion and store of one pixel in the game's image loader, with the
; color and its depth on the stack, and the place to write in edi. The loading picture
; is the one image it loads in the format of the screen, and it only knew 16 bits.
image_pixel:
    mov eax, [esp+IMAGE_FORMAT]
    cmp dword [eax+FORMAT_BITS], 32
    je .whole
    push dword [esp+8]
    push dword [esp+8]
    call CONVERT_COLOR
    add esp, 8
    mov [edi], ax
    add edi, 2
    ret 8
.whole:
    push dword [esp+4]
    call CONVERT_COLOR_FULL
    add esp, 4
    mov [edi], eax
    add edi, 4
    ret 8

; Replaces the call that counts how long no wheel has touched anything, in the function that
; drives the player and the racers, with the car's controls in ebp and ecx, its physics object
; on the stack and its offset in the car table in ebx. These cars have their centre of mass at
; the bottom of the body, so a body that lands on an edge, such as the side of a jump ramp, does
; not tip off it. The car then hangs there with its wheels spinning in the air and the game has
; no way out, as the only correction it knows is for a car that spins. Put a car back on the road
; when it stands still for HUNG_TIME seconds, with an axle in the air or tipped over.
hung_check:
    push dword [esp+4]
    mov eax, WHEEL_TIMER
    call eax
    pushad
    mov esi, [esp+36]                   ; the physics object
    xor edx, edx                        ; 1: a front wheel touches, 2: a rear wheel touches
    xor ecx, ecx
.wheel:
    mov eax, [esi+0x34+ecx*4]
    mov eax, [eax+8]
    cmp dword [eax+0x28], 0             ; friction contacts of this wheel
    je .next_wheel
    mov eax, ecx
    shr eax, 1
    inc eax
    or edx, eax
.next_wheel:
    inc ecx
    cmp ecx, 4
    jb .wheel
    mov edi, edx
    mov eax, ebp                        ; a time for each racer, the last one for the player
    sub eax, RACER_CONTROLS
    xor edx, edx
    mov ecx, RACER_CONTROLS_SIZE
    div ecx
    cmp eax, HUNG_TIME_COUNT - 1
    jb .have_slot
    mov eax, HUNG_TIME_COUNT - 1
.have_slot:
    lea esi, [HUNG_TIMES+eax*4]
    mov ecx, [CAR_TABLE]
    add ecx, ebx
    fld dword [ecx+0xbc]                ; speed squared
    fmul st0, st0
    fld dword [ecx+0xc0]
    fmul st0, st0
    faddp st1, st0
    fld dword [ecx+0xc4]
    fmul st0, st0
    faddp st1, st0
    fcomp dword [hung_speed]
    fnstsw ax
    sahf
    jae .clear
    cmp edi, 3
    jne .hung
    mov eax, [ecx+0x24]
    imul eax, eax, 0xa9
    add eax, [OBJECT_TABLE]
    fld dword [eax+0x24]                ; y of the car's up vector
    fcomp dword [hung_up]
    fnstsw ax
    sahf
    jae .clear
.hung:
    mov ecx, GAME_TIMER_OBJECT
    mov eax, GAME_TIME_STEP
    call eax
    fadd dword [esi]
    fst dword [esi]
    fcomp dword [hung_time]
    fnstsw ax
    sahf
    jb .done
    push 0
    mov ecx, [CAR_TABLE]
    push dword [ecx+ebx+0x34]           ; its place on the road
    mov eax, ebx
    xor edx, edx
    mov ecx, 0xf0
    div ecx
    push eax                            ; the car
    mov eax, RESET_CAR
    call eax
    add esp, 12
.clear:
    mov dword [esi], 0
.done:
    popad
    ret 4

; Jumps here from the start of FUN_00505CC0, with the contact in ecx. That function works out the
; state of a contact on each physics step. For a corner of a body on a triangle the gap it uses is the
; distance to the plane of that triangle, which has no edges, and whether the corner is still over the
; triangle only gets checked when a byte in the contact asks for it. Friction sets that byte when a
; contact slips. But the driving code calls FUN_004F3810 once per frame for the body of the player and
; the racers, which runs this function, uses up the byte and ignores the answer. So with a frame
; between every two physics steps, from 66 frames per second on, no check ever counted. A body that
; had moved past a triangle kept pressing against its plane, as if on an invisible ramp. It lets go
; when it moves away from the plane, so the ones that last are the planes that rise in front of the
; car: it climbs them nose first until its front wheels are off the road. A slow creep under load
; doesn't set the byte either, at any frame rate. Ask for the check every time, as for the wheels.
contact_check:
    mov byte [ecx+CONTACT_RECHECK], 1
    sub esp, 0xb0
    jmp CONTACT_STATE_CONTINUE

; Jumps here from the start of FUN_004F3130, which moves an object to another place, with the object
; in ecx. It left the contacts of the object as they were, and a move doesn't count as slipping, so
; nothing checked them. A car put back on the road could end up under the plane of a triangle it
; touched before, with a gap of 0, and hang from it with the rest of the car on the road.
move_object:
    push ecx
    push 1
    mov eax, REMOVE_CONTACTS
    call eax
    pop ecx
    sub esp, 0xd8
    jmp MOVE_OBJECT_CONTINUE

; Replaces adding 20 to the height of the ground in the reset, FUN_0040E5A0, with that height in st0,
; the height of the lane at [esp+0x40] and its waypoint at [esp+0x6c]. The ground comes from the first
; surface found under the lane, with no look at how high that is. On a road high above the ground, as
; at sections 296 and 305 of the sixth stage, that put a car under the road. Believe the lane when the
; two are far apart, unless the lane is marked as not for placing cars, as the lanes that run far under
; a bridge are. For those the game's own respawn doesn't use the lane at all. If nothing was found the
; height is 0, and the lane is all there is.
reset_height:
    fld st0
    fsub dword [esp+0x40]
    fabs
    fcomp dword [reset_height_limit]
    fnstsw ax
    sahf
    jbe .done
    fldz
    fcomp st1
    fnstsw ax
    sahf
    je .use_lane
    mov eax, [esp+0x6c]
    imul eax, eax, 0x50
    add eax, [WAYPOINT_TABLE]
    test byte [eax], 4
    jnz .done
.use_lane:
    fstp st0
    fld dword [esp+0x40]
.done:
    fadd dword [RESET_HEIGHT]
    ret

; Replaces the two instructions before the move in the reset, with the car's offset in
; the car table in edi and the table in edx. The reset changes the waypoint of the car without taking
; the car off the list of the old one, so that one kept counting it forever. Lanes looked taken, for
; other cars and for the next reset. The game's own respawn, FUN_0041CAE0, does this before it moves.
reset_unlink:
    push edx
    mov eax, [edx+edi+0x3c]
    test eax, eax
    js .done
    cmp eax, [WAYPOINT_COUNT]
    jg .done
    mov eax, edi
    xor edx, edx
    mov ecx, 0xf0
    div ecx
    push eax
    mov eax, WAYPOINT_UNLINK
    call eax
    add esp, 4
.done:
    pop edx
    mov ecx, [edx+edi+0x10]
    lea edx, [esp+0x48]
    ret

; Replaces storing the time of this reset, which is in st0, right after the move. Only the Enter key
; looks at that time, for its wait of 5 seconds, so only Enter should set it: a racer that gets reset
; every 3 seconds kept the Enter key from working at all. The move also only stops the car, not its
; rotation, and the game's correction for a spinning car goes on until the spin stops, so a car could
; get reset again on every frame. Stop the rotation of the body. The wheels keep theirs, as they did.
reset_done:
    mov eax, [CAR_TABLE]
    mov eax, [eax+edi+0x10]
    mov eax, [eax+8]
    mov eax, [eax+0xa4]
    xor edx, edx
    mov [eax+0x94], edx                 ; rotation
    mov [eax+0x98], edx
    mov [eax+0x9c], edx
    mov [eax+0x74], edx                 ; what is waiting to be added to the rotation
    mov [eax+0x78], edx
    mov [eax+0x7c], edx
    mov [eax+0x84], edx                 ; the same for the speed
    mov [eax+0x88], edx
    mov [eax+0x8c], edx
    cmp dword [esp+4+0x5c], ENTER_RESET_RETURN
    jne .other
    fstp dword [RESET_STAMP]
    ret
.other:
    fstp st0
    ret

; Replaces stepping to the next section in the reset, when the lanes of this one look taken, with the
; section in esi and its offset in the section table in ebp. The game's other placement code wraps
; around after the last section. This didn't, and read past the tables.
reset_next_section:
    inc esi
    add ebp, 0x994
    cmp esi, [SECTION_COUNT]
    jl .done
    xor esi, esi
    xor ebp, ebp
.done:
    ret

; The same for stepping back, on a track driven in reverse.
reset_previous_section:
    dec esi
    sub ebp, 0x994
    jns .done
    mov esi, [SECTION_COUNT]
    dec esi
    imul ebp, esi, 0x994
.done:
    ret

; Replaces the debug print at the start of the camera's damping, which has the camera in ebp. Each
; frame the game moves the camera a fixed part k of the way to where it should be, in each direction
; of the car, with no look at the time: at 165 frames per second it follows five times as tightly as
; at 30, sits closer at speed and takes every bump. Work out the part for this frame that keeps the
; distance it lags behind a moving car the same as at AI_FRAME_RATE. With s the share of this frame
; that is k*s/(1-k+k*s), which is k at that rate and below. The FMULs now read these.
camera_damping:
    call frame_share
    xor ecx, ecx
.next:
    fld1
    fsub dword [ebp+0x88+ecx*4]
    fld dword [ebp+0x88+ecx*4]
    fmul st0, st2
    fadd st1, st0
    fdivrp st1, st0
    fstp dword [CAMERA_K+ecx*4]
    inc ecx
    cmp ecx, 3
    jb .next
    fstp st0
    ret

; Replaces the conversion to a whole number when the light of a car follows the road, and of the pulse
; around a portrait. Rounding toward zero always gives away what doesn't make a whole level. A step of
; less than a level then does nothing going up, but a whole level going down. The higher the frame rate
; the smaller the steps, so at 165 frames per second cars stayed dark after a shadow, up to 165 levels
; when standing still, and above 212 the pulse stopped. There's no room per car to keep the rest. Add a
; different part of a level each time instead, so that a step of 0.3 goes through 3 times out of 10.
; It can't go past the target, as the steps are never more than the way to go.
color_round:
    mov eax, [COLOR_SEQUENCE]
    add eax, 0x9e3779b9
    mov [COLOR_SEQUENCE], eax
    shr eax, 16
    push eax
    fild dword [esp]
    pop eax
    fmul dword [one_65536]
    faddp st1, st0
    jmp FLOAT_TO_INTEGER

; These replace calls in the game that add or take away a fixed amount per frame, to run them only when
; a tick of 25 Hz falls in this frame, and in every frame below that rate:
; a skid mark takes one section per frame up to its limit, so at 165 frames per second a slide leaves
; a mark of 0.3 seconds, and it fades by one level per frame, so it's gone within a second;
; smoke fades by one level per frame while it grows by time, so it dies small and early;
; mud and water start 4 clouds of particles per frame for as long as you are in them, which fills
; the room for all particles in 0.15 seconds.
skid_section:
    mov eax, SKID_ADD_SECTION
    jmp short tick_gate
skid_fade:
    mov eax, SKID_FADE
    jmp short tick_gate
tyre_smoke_fade:
    mov eax, TYRE_SMOKE_FADE
    jmp short tick_gate
damage_smoke_fade:
    mov eax, DAMAGE_SMOKE_FADE
    jmp short tick_gate
mud_spray:
    mov eax, MUD_SPRAY
    jmp short tick_gate
water_spray:
    mov eax, WATER_SPRAY
tick_gate:
    cmp byte [TICK], 0
    je .skip
    jmp eax
.skip:
    ret

; The same for the shrinking of a pickup that was taken, a script that multiplies its size by 0.6 per frame.
pickup_fade:
    cmp byte [TICK], 0
    jne PICKUP_FADE
    ret 8

; The same for the animated objects. A step takes a frame more than its time, and loses what its last
; frame went over, so they ran up to 3 times as fast at high frame rates. Returns that it isn't done.
animation_step:
    cmp byte [TICK], 0
    jne ANIMATION_STEP
    xor eax, eax
    ret 4

; Replaces reading the time step, with the timer object in ecx, in code that runs on a tick, and where the
; game takes a value from one frame's time and doesn't add it up:
; the pedal of a Supercop that is trying to get free, 800 times the time step, which leaves it with
; 4.8 percent at 165 frames per second instead of 26.7 at 30;
; how fast smoke rises.
long_step:
    call GAME_TIME_STEP
    fcom dword [tick_time]
    fnstsw ax
    sahf
    jae .done
    fstp st0
    fld dword [tick_time]
.done:
    ret

; Replace the time step and the factor in the slowing down of smoke. The game multiplies its speed
; per frame by 15 or 20 times the time step, which is the wrong way around: the shorter the frame, the
; harder it stops, so at high frame rates smoke stays where it starts. Below 15 frames per second it hit
; a limit of 0.99 and shot away. Multiply by 1 - 10 or 1 - 5 times the time step, the same at 25 frames
; per second, so smoke goes as far at any frame rate.
smoke_drift_tyre:
    call GAME_TIME_STEP
    fmul dword [FLOAT_TEN]
    jmp short smoke_drift
smoke_drift_damage:
    call GAME_TIME_STEP
    fmul dword [FLOAT_FIVE]
smoke_drift:
    fld1
    fsubrp st1, st0
    ret

; Replaces the call that adds to the brake of a police car that is driving faster than the one it is
; after, with this amount on the stack and the controls in ecx. Most of the time the code before it
; has just set that brake to 0, so the brake is one frame's amount, and that gets smaller at higher frame
; rates: 13 percent at 30 frames per second, 2 at 165. Such a car hardly slowed down any more and ran into
; or past its target. Brake at least as hard as a frame at AI_FRAME_RATE would.
police_brake:
    call frame_share
    fdivr dword [esp+4]
    fsub dword [ecx+4]
    fcom dword [esp+4]
    fnstsw ax
    sahf
    jbe .keep
    fst dword [esp+4]
.keep:
    fstp st0
    jmp ADD_BRAKE

; Replaces loading the step for the gas of a Supercop that keeps to its patrol speed, 1 percent
; per frame, with its settings in ebx. Give each frame its share.
patrol_step:
    call frame_share
    fmul dword [ebx+0x30]
    push ecx
    fstp dword [esp]
    pop ecx
    mov edx, [ebx+0x28]
    ret

; Replaces adding the turn of a pickup per frame, in ecx, with its angle in st0. The script asks for an
; amount per second, but gets it while loading, when the time step is still a default of 0.1.
pickup_spin:
    fld dword [ecx+0xcc]
    call frame_share
    fmulp st1, st0
    faddp st1, st0
    ret

; Replaces one of three random numbers that turn a piece of debris per frame, with no look at the time.
particle_spin:
    push dword [esp+8]
    push dword [esp+8]
    call PARTICLE_RANDOM
    add esp, 8
    call frame_share
    fmulp st1, st0
    ret

; Replaces multiplying the speed of a cloud of letters by 0.99 per frame, with that speed in st0.
mail_drift:
    call frame_share
    fmul dword [one_100]
    fld1
    fsubrp st1, st0
    fmulp st1, st0
    ret

; Replaces storing the time when the tank of the turbo last lost a unit, with now in eax, now minus the
; stored time in ecx and the stored time in edx. A unit takes at least 100 ms and then the rest of a
; frame, so how long a tank lasts depended on the frame rate. Keep what it went over, unless the key
; has been up.
turbo_stamp:
    cmp ecx, 200
    jae .store
    lea eax, [edx+100]
.store:
    mov [TURBO_STAMP], eax
    ret

; Replaces saying that the flash of a speed camera is done, which it was after one frame: 33 ms at 30 frames
; per second, 4 at 240, which a screen may not even show. Returns 1 when it has lasted a tick.
flash_done:
    mov ecx, GAME_TIMER_OBJECT
    call GAME_TIME_STEP
    fadd dword [FLASH_TIME]
    fst dword [FLASH_TIME]
    fcomp dword [tick_time]
    fnstsw ax
    sahf
    setae al
    movzx eax, al
    jb .done
    and dword [FLASH_TIME], 0
.done:
    ret

; Replaces the call to the game timer at the start of every frame, which has the timer
; object in ecx. Nothing that was checked needs a limit here any more. This keeps the
; frame rate inside the range the physics were measured in, about 440 at most, and far
; from where the game's whole milliseconds per frame round to nothing, at 1000.
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
    call GAME_TIMER_UPDATE
    ; Then see if a tick falls in this frame. Below 25 frames per second every frame has one.
    mov ecx, GAME_TIMER_OBJECT
    call GAME_TIME_STEP
    fadd dword [TICK_REST]
    fcom dword [tick_time]
    fnstsw ax
    sahf
    setae byte [TICK]
    jb .store_rest
    fsub dword [tick_time]
    fcom dword [tick_time]
    fnstsw ax
    sahf
    jb .store_rest
    fstp st0
    fldz
.store_rest:
    fstp dword [TICK_REST]
    ret

ai_frame_rate:      dd __float32__(25.0)
tick_time:          dd __float32__(0.04)
one_65536:          dd __float32__(0.0000152587890625)
one_100:            dd __float32__(0.01)
frame_time:         dd __float32__(0.0041666667)
hung_speed:         dd __float32__(2.25)    ; 1.5 units per second, squared
hung_up:            dd __float32__(0.5)
hung_time:          dd __float32__(3.0)
reset_height_limit: dd __float32__(25.0)
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
