.text
.altmacro

#include "AsmMacros.inc"

arm_func sav_swiHandler
    cmp r13, #0x9A
        beq soulGoldTraceResourceOne
    cmp r13, #0x9B
        beq soulGoldTraceResourceTwo
    cmp r13, #0x9C
        beq soulGoldTraceGraphicsSetup
    cmp r13, #0x9D
        beq soulGoldTraceSecondCall
    cmp r13, #0x9E
        beq soulGoldTraceSecondReturn
    cmp r13, #0x9F
        beq sgVerifyMixerCopy
    cmp r13, #0x95
        beq soulGoldTraceId
    cmp r13, #0x96
        beq soulGoldTracePointers
    cmp r13, #0x97
        beq soulGoldTraceReturn
    cmp r13, #0x98
        beq soulGoldTraceTimer
    cmp r13, #0x99
        beq soulGoldTraceRead
    cmp r13, #0x90
        beq sav_swiReadSaveByte
    cmp r13, #0x91
        beq sav_swiWriteSaveByte
    cmp r13, #0x92
        beq sav_swiReadSaveByteFromFile
    cmp r13, #0x93
        beq sav_swiWriteSaveByteToFile
    cmp r13, #0x94
        beq sav_swiFlushSaveFile
    adr r12, (sav_swiTable - (0x80 * 4))
    ldr r12, [r12, r13, lsl #2]
    msr cpsr_c, #0x9F
    push {r0-r3,r12,lr}
    mov r0, lr
#ifndef GBAR3_TEST
    bl jit_ensureBlockJitted
#endif
    pop {r0-r3,r12}
    msr cpsr_c, #0x10
    blx r12
    pop {lr}
    bx lr

.global sav_swiTable
sav_swiTable:
    .space 16 * 4

arm_func sav_swiReadSaveByte
    ldr r1,= gSaveData
    ldrb r0, [r1, r0]
    movs pc, lr

arm_func sav_swiWriteSaveByte
    ldr r2,= gSaveData
    strb r1, [r2, r0]
    movs pc, lr

arm_func sav_swiReadSaveByteFromFile
    msr cpsr_c, #0x9F
    push {lr}
    adr lr, returnFromSwi
    b sav_readSaveByteFromFile

arm_func sav_swiWriteSaveByteToFile
    msr cpsr_c, #0x9F
    push {lr}
    adr lr, returnFromSwi
    b sav_writeSaveByteToFile

arm_func sav_swiFlushSaveFile
    msr cpsr_c, #0x9F
    push {lr}
    adr lr, returnFromSwi
    b sav_flushSaveFile

returnFromSwi:
    pop {lr}
    msr cpsr_c, #0x93
    movs pc, lr

thumb_func sav_callSwi0
    swi 0x80
thumb_func sav_callSwi1
    swi 0x81
thumb_func sav_callSwi2
    swi 0x82
thumb_func sav_callSwi3
    swi 0x83
thumb_func sav_callSwi4
    swi 0x84
thumb_func sav_callSwi5
    swi 0x85
thumb_func sav_callSwi6
    swi 0x86
thumb_func sav_callSwi7
    swi 0x87
thumb_func sav_callSwi8
    swi 0x88
thumb_func sav_callSwi9
    swi 0x89
thumb_func sav_callSwi10
    swi 0x8A
thumb_func sav_callSwi11
    swi 0x8B
thumb_func sav_callSwi12
    swi 0x8C
thumb_func sav_callSwi13
    swi 0x8D
thumb_func sav_callSwi14
    swi 0x8E
thumb_func sav_callSwi15
    swi 0x8F

thumb_func sav_readSaveByte
    swi 0x90
    bx lr

thumb_func sav_writeSaveByte
    swi 0x91
    bx lr

thumb_func sav_readSaveByteFromFileFromUserMode
    swi 0x92
    bx lr

thumb_func sav_writeSaveByteToFileFromUserMode
    swi 0x93
    bx lr

thumb_func sav_flushSaveFileFromUserMode
    swi 0x94
    bx lr


// Privileged trace markers. SWI entry has interrupts masked. Preserve r0
// except for the chip ID return value; r13 is already the SWI scratch reg.
// movs pc,lr restores the original Thumb CPSR including condition flags.
.arm
.balign 4
.macro sg_trace_mark slot, color
    // No SUB palette writes while the SUB engine displays the captured game.
.endm

soulGoldTraceId:
    sg_trace_mark 2, 0x03FF
    ldr r0, =0x000009C2
    movs pc, lr

soulGoldTracePointers:
    str r3, [r2] // replaced 0x6013
    sg_trace_mark 3, 0x03E0
    movs pc, lr

soulGoldTraceReturn:
    ldr r3, =0x030040BC // replaced literal load at 0x081A3D42
    sg_trace_mark 4, 0x7C1F
    movs pc, lr

soulGoldTraceTimer:
    sg_trace_mark 5, 0x01FF
    sub lr, lr, #14 // replaced branch 0xE7F8 to 0x081A3D4C
    movs pc, lr

// Draw eight hex digits. Guest r0/r12 saved by caller; r13 is banked.
.macro sg_hex destination
    ldr r13, =\destination
.Lsg_hex_loop\@:
    mov r12, r0, lsr #28
    add r12, r12, #16
    strh r12, [r13], #2
    mov r0, r0, lsl #4
    and r12, r13, #0x3F
    cmp r12, #((\destination + 16) & 0x3F)
    bne .Lsg_hex_loop\@
.endm

soulGoldTraceRead:
    sg_trace_mark 6, 0x7C00 // blue: entered save read
    // Same privileged call/return convention as sav_swiReadSaveByteFromFile.
    // The next guest instruction is BX LR, so no old prologue executes.
    msr cpsr_c, #0x9F
    push {lr}
    adr lr, soulGoldReadReturn
    b sav_readSoulgoldFlashBlock
soulGoldReadReturn:
    pop {lr}
    msr cpsr_c, #0x93
    movs pc, lr

// Trace the later resource calls while preserving original literal loads.
soulGoldTraceResourceOne:
    // Guest executed the instruction after the privileged read SWI.
    sg_trace_mark 7, 0x7FE0
    movs pc, lr

// Type-8 decoder copies 0x284 and 0x118 bytes of ARM code to IWRAM.
// Only invalidate the aligned lines intersecting the verified copy.
// Uses r0 and banked r13 as scratch; guest r0 is reconstructed below.
.macro sg_type8_sync target, size, slot, color
    mov r0, \target
    tst r0, #3
    bne 8f
    mov r13, r0, lsr #24
    cmp r13, #3
    bne 8f
    ldr r13, =\size
    add r13, r0, r13
    cmp r13, #0x04000000
    bhi 8f
    bic r0, r0, #31
    mcr p15, 0, r0, c7, c10, 4
7:
    mcr p15, 0, r0, c7, c5, 1
    add r0, r0, #32
    cmp r0, r13
    blo 7b
    sg_trace_mark \slot, \color
    b 9f
8:
    sg_trace_mark \slot, 0x001F
9:
.endm

soulGoldTraceResourceTwo:
    sg_type8_sync r11, 0x284, 8, 0x03FF
    mov r0, r10 // original high-register MOV; flags unchanged
    movs pc, lr

soulGoldTraceGraphicsSetup:
    sg_type8_sync r6, 0x118, 9, 0x03E0
    mov r0, r5
    // Original 0x0028 is LSLS r0,r5,#0 (MOVS alias): update N/Z only.
    mrs r13, spsr
    bic r13, r13, #0xC0000000
    cmp r0, #0
    orreq r13, r13, #0x40000000
    orrmi r13, r13, #0x80000000
    msr spsr_f, r13
    movs pc, lr

soulGoldTraceSecondCall:
    // SoulGold copies ARM code to r4 from a ROM resource immediately
    // before this call. The copy length is stored at [r7, #0x2c].
    // Preserve guest r0 and reconstruct r1 using the replaced LDR.
    // IWRAM is not data cached, but is instruction cached on this build.
    str r0, sgTraceSavedR0
    mov r0, r4
    tst r0, #3
    bne sgSecondSyncSkipped
    mov r1, r0, lsr #24
    cmp r1, #3
    bne sgSecondSyncSkipped
    ldr r1, [r7, #0x2c]
    cmp r1, #0
    beq sgSecondSyncSkipped
    cmp r1, #0x8000
    bhi sgSecondSyncSkipped
    add r1, r0, r1
    cmp r1, #0x04000000
    bhi sgSecondSyncSkipped
    bic r0, r0, #31
    mcr p15, 0, r0, c7, c10, 4 // drain write buffer
sgSecondSyncLine:
    mcr p15, 0, r0, c7, c5, 1 // invalidate one instruction-cache line by address
    add r0, r0, #32
    cmp r0, r1
    blo sgSecondSyncLine
    ldr r0, sgTraceSavedR0
    ldr r1, [r7, #0x38]
    sg_trace_mark 10, 0x7C1F // magenta: cache sync performed
    movs pc, lr

sgSecondSyncSkipped:
    ldr r0, sgTraceSavedR0
    ldr r1, [r7, #0x38]
    sg_trace_mark 10, 0x001F // red: unexpected destination or size; no sync
    movs pc, lr

soulGoldTraceSecondReturn:
    ldr r0, [r7, #0x3c]
    sg_trace_mark 11, 0x01FF
    movs pc, lr

soulGoldTraceResourceReturn:
    and r13, lr, #0xFF
    cmp r13, #0x0A
    beq sgVblankWaitEntry
    cmp r13, #0x0E
    beq sgVblankWaitExit
    cmp r13, #0x9e
    beq sgCheckResult
    cmp r13, #0xa4
    beq sgTransitionYes
    cmp r13, #0xa8
    beq sgResetCall
    cmp r13, #0xac
    beq sgResetReturn
    cmp r13, #0xb2
    beq sgCheckAgain
    cmp r13, #0xb6
    beq sgCheckAgainReturn
    cmp r13, #0x70
    beq sgFrameCall1
    cmp r13, #0x74
    beq sgFrameCall2
    cmp r13, #0x78
    beq sgFrameCallsDone
    cmp r13, #0x7e
    beq sgFrameWait
    cmp r13, #0xe8
    beq sgWaitCall
    cmp r13, #0xec
    beq sgWaitReturn
    // Original 0x6863: LDR r3,[r4,#4]. Record only after guest epilogue.
    ldr r3, [r4, #4]
    str r0, sgTraceSavedR0
    ldr r13, =0x0500040E
    ldrh r0, [r13]
    ldr r13, =0x7FE0
    cmp r0, r13
    ldr r0, sgTraceSavedR0
    bne 1f
    sg_trace_mark 12, 0x7C00
    str r0, sgTraceHexSavedR0
    mov r0, #0
    str r0, sgFaultCallStage
    str r0, sgFaultReturnTarget
    ldr r0, sgTraceHexSavedR0
    str r0, sgTraceHexSavedR0
    str r12, sgTraceHexSavedR12
    ldr r0, sgTraceCallbackCount
    cmp r0, #0
    bne 2f
    mov r0, r3
    sg_hex 0x062042C4
2:
    mov r0, r3
    sg_hex 0x062042DC
    ldr r0, sgTraceCallbackCount
    add r0, r0, #1
    str r0, sgTraceCallbackCount
    sg_hex 0x06204544
    ldr r12, sgTraceHexSavedR12
    ldr r0, sgTraceHexSavedR0
1:
    movs pc, lr

// Banked r13 is scratch; preserve guest flags via SPSR.
.macro sg_post_stage stage
    mov r13, #\stage
    str r13, sgFaultCallStage
.endm
// Recreate ARMv4T BL prefix, leaving the original suffix untouched.
.macro sg_transition_prefix stage, magnitude, negative=0
    sg_post_stage \stage
    str r0, sgTraceSavedR0
    add r0, lr, #2
    ldr r13, =\magnitude
    .if \negative
    sub r0, r0, r13
    .else
    add r0, r0, r13
    .endif
    str r0, sgFaultGuestLink
    ldr r13, =sgFaultGuestLink
    ldmia r13, {lr}^
    nop
    ldr r0, sgTraceSavedR0
    movs pc, lr
.endm
sgCheckResult:
    mov r11, r0
    str r0, sgFaultReturnTarget // actual transition-check result
    sg_post_stage 0x10
    movs pc, lr
sgTransitionYes:
    mov r3, #0
    mrs r13, spsr
    bic r13, r13, #0x80000000
    orr r13, r13, #0x40000000
    msr spsr_f, r13
    sg_post_stage 0x11
    movs pc, lr
sgResetCall:
    sg_transition_prefix 0x12, 0xA6000
sgResetReturn:
    mov r3, #0x41
    mrs r13, spsr
    bic r13, r13, #0xC0000000
    msr spsr_f, r13
    sg_post_stage 0x13
    movs pc, lr
sgCheckAgain:
    sg_transition_prefix 0x14, 0x9000, 1
sgCheckAgainReturn:
    // Original CMP r0,#0: N/Z from r0, C=1, V=0.
    mrs r13, spsr
    bic r13, r13, #0xF0000000
    orr r13, r13, #0x20000000
    cmp r0, #0
    orreq r13, r13, #0x40000000
    orrmi r13, r13, #0x80000000
    msr spsr_f, r13
    sg_post_stage 0x15
    movs pc, lr
sgFrameCall1:
    sg_transition_prefix 0x16, 0x33000
sgFrameCall2:
    sg_transition_prefix 0x17, 0xA4000
sgFrameCallsDone:
    ldrh r3, [r4, #0x1C]
    sg_post_stage 0x18
    movs pc, lr
sgFrameWait:
    mov r3, r9
    sg_post_stage 0x19
    movs pc, lr
sgWaitCall:
    // The guarded F659 F90F pair at 081A70E6 is BL 08000308.
    // Emulate BOTH halfwords instead of executing an orphan BL suffix.
    // SWI LR points at 081A70E8; guest LR must become 081A70EB.
    sg_post_stage 0x1A
    str r0, sgTraceSavedR0
    add r0, lr, #2
    orr r0, r0, #1
    str r0, sgFaultGuestLink
    ldr r13, =sgFaultGuestLink
    ldmia r13, {lr}^
    nop
    // Compute destination relative to the actual exception return address.
    ldr r13, =0x1A6DE0
    sub lr, lr, r13
    str lr, sgFaultReturnTarget
    ldr r0, sgTraceSavedR0
    movs pc, lr
sgWaitReturn:
    sg_post_stage 0x1B
    sub lr, lr, #0xE0 // 1A70EC -> 1A700C
    movs pc, lr

// Record actual guest link register, not the exception return register.
// Only record after the main loop has selected a post-save callback.
sgVblankWaitEntry:
    mov r2, #0
    mrs r13, spsr
    bic r13, r13, #0x80000000
    orr r13, r13, #0x40000000
    msr spsr_f, r13
    str r0, sgTraceSavedR0
    ldr r0, sgTraceCallbackCount
    cmp r0, #0
    beq 1f
    mov r13, #0x1C
    str r13, sgFaultCallStage
    ldr r13, =sgWaitEntryLink
    stmia r13, {lr}^
    nop
    ldr r0, sgWaitEntryLink
    str r0, sgFaultReturnTarget
1:
    ldr r0, sgTraceSavedR0
    movs pc, lr

sgVblankWaitExit:
    str r0, sgTraceSavedR0
    ldr r13, =sgWaitExitLink
    stmia r13, {lr}^
    nop
    ldr r0, sgTraceCallbackCount
    cmp r0, #0
    beq 1f
    mov r13, #0x1D
    str r13, sgFaultCallStage
    ldr r0, sgWaitExitLink
    str r0, sgFaultReturnTarget
1:
    // Execute the original BX LR from the user register bank.
    ldr lr, sgWaitExitLink
    ldr r0, sgTraceSavedR0
    mrs r13, spsr
    bic r13, r13, #0x20
    tst lr, #1
    orrne r13, r13, #0x20
    msr spsr_c, r13
    bic lr, lr, #1
    biceq lr, lr, #2
    movs pc, lr

// IRQ-mode sampler: use only caller-saved r0-r3/r12, never banked SP.
// Starts after the first post-save callback. A sampled address is not
// necessarily the exact faulting PC, but shows what the IRQ interrupted.
.global sgTraceVblankSample
sgTraceVblankSample:
    ldr r1, sgTraceCallbackCount
    cmp r1, #0
    bxeq lr
    ldr r1, =0x0620405C
    mov r3, #8
1:
    mov r2, r0, lsr #28
    add r2, r2, #16
    strh r2, [r1], #2
    mov r0, r0, lsl #4
    subs r3, r3, #1
    bne 1b
    ldr r0, sgTraceVblankCount
    add r0, r0, #1
    str r0, sgTraceVblankCount
    ldr r1, =0x0620455C
    mov r3, #8
2:
    mov r2, r0, lsr #28
    add r2, r2, #16
    strh r2, [r1], #2
    mov r0, r0, lsl #4
    subs r3, r3, #1
    bne 2b
    bx lr

// Compare actual mixer bytes against a verified ROM copy. Correct only
// differing words, synchronize executable RAM, reconstruct the original
// literal load and return with all other guest registers/flags intact.
sgVerifyMixerCopy:
    str r1, sgMixerSavedR1
    str r2, sgMixerSavedR2
    str r3, sgMixerSavedR3
    str r12, sgTraceHexSavedR12
    mov r13, #1
    str r13, sgFaultCallStage
    ldr r1, =sgMixerReference
    ldr r2, =0x030011D8
    ldr r3, =0x03001D18
1:
    ldr r0, [r1], #4
    ldr r12, [r2]
    cmp r0, r12
    strne r0, [r2]
    movne r13, #2
    strne r13, sgFaultCallStage
    add r2, r2, #4
    cmp r2, r3
    blo 1b
    // Experiment 053: keep SoundMain's original sequencing callbacks
    // and skip only its RAM sample-mixing body. Verified original
    // epilogue at ROM 0829031E maps to Thumb 03001AEA:
    // load magic; restore lock, saved registers, stack and return.
    // r0 still contains SoundInfo when the original wrapper enters here.
    ldr r2, =0x030011D8
    ldr r0, =0x47184B00 // Thumb LDR r3,[pc,#0]; BX r3
    str r0, [r2]
    ldr r0, =0x03001AEB
    str r0, [r2, #4]
    ldr r13, sgFaultCallStage
    add r13, r13, #2 // 3: matched and bypassed; 4: repaired and bypassed
    str r13, sgFaultCallStage
    ldr r2, =0x030011C0
    ldr r3, =0x03001D20
2:
    mcr p15, 0, r2, c7, c10, 1
    add r2, r2, #32
    cmp r2, r3
    blo 2b
    mov r0, #0
    mcr p15, 0, r0, c7, c10, 4
    ldr r2, =0x030011C0
3:
    mcr p15, 0, r2, c7, c5, 1
    add r2, r2, #32
    cmp r2, r3
    blo 3b
    // Keep copy status in host memory, without touching capture VRAM.
    ldr r1, sgMixerSavedR1
    ldr r2, sgMixerSavedR2
    ldr r3, sgMixerSavedR3
    ldr r12, sgTraceHexSavedR12
    ldr r0, =0x030045C8
    movs pc, lr

// Terminal diagnostic in abort mode. IRQ/FIQ disabled; no stack needed.
// LR was adjusted by memu_prefetchAbort to the faulting fetch address.
.global sgTraceInvalidFetch
sgTraceInvalidFetch:
    msr cpsr_c, #0xD7
    // Normal capture owns SUB VRAM. Do not overwrite its contents.
    // Hardware testing of 054 is visual only; 053 retains the debug panel.
1:
    b 1b

.balign 4
sgMixerSavedR1:
    .word 0
sgMixerSavedR2:
    .word 0
sgMixerSavedR3:
    .word 0
.global sgLastHicodeMiss
sgLastHicodeMiss:
    .word 0
.global sgLastHicodeIndex
sgLastHicodeIndex:
    .word 0
.global sgLastHicodePrefetch
sgLastHicodePrefetch:
    .word 0
sgCpuSetSource:
    .word 0
sgCpuSetDestination:
    .word 0
sgCpuSetControl:
    .word 0
sgCpuSetReturn:
    .word 0
sgLastSwiOpcode:
    .word 0xFF
sgLastSwiGuestLink:
    .word 0
sgRestoredGuestLink:
    .word 0
sgLastNormalSwi:
    .word 0
sgLastExceptionTarget:
    .word 0
sgLastExceptionSource:
    .word 0
sgLastExceptionSpsr:
    .word 0
sgWaitEntryLink:
    .word 0
sgWaitExitLink:
    .word 0
sgFaultReturnTarget:
    .word 0
sgFaultCallStage:
    .word 0
sgFaultGuestLink:
    .word 0
sgTraceFaultRegs:
    .space 8
sgTraceVblankCount:
    .word 0
sgTraceSavedR0:
    .word 0
sgTraceHexSavedR0:
    .word 0
sgTraceHexSavedR12:
    .word 0
sgTraceReadCaller:
    .word 0
sgTraceCallbackCount:
    .word 0
.pool
