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
        beq soulGoldTraceResourceReturn
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
    str r0, sgTraceSavedR0
    ldr r13, =0x05000400 + (2 * \slot)
    ldr r0, =\color
    strh r0, [r13]
    ldr r0, sgTraceSavedR0
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
    str r0, sgTraceHexSavedR0
    str r12, sgTraceHexSavedR12
    ldr r13, =sgTraceReadCaller
    stmia r13, {lr}^
    nop
    ldr r0, sgTraceReadCaller
    sg_hex 0x06204044
    ldr r12, sgTraceHexSavedR12
    ldr r0, sgTraceHexSavedR0
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
    cmp r13, #0x42
    beq sgPaletteCallbackExit
    cmp r13, #0x16
    beq sgPostReturn
    cmp r13, #0x9a
    beq sgPostCheckCall
    cmp r13, #0x9e
    beq sgPostCheckReturn
    cmp r13, #0xac
    beq sgPostExtraReturn
    cmp r13, #0xe
    beq sgPostLoop
    cmp r13, #0x8e
    beq sgPostAlternate
    cmp r13, #0xba
    beq sgPostCallbackOne
    cmp r13, #0xce
    beq sgPostOtherReturn
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

// Record stage with no guest register or flag changes.
.macro sg_post_stage stage
    mov r13, #\stage
    str r13, sgFaultCallStage
.endm
sgPostReturn:
    sg_post_stage 8
    // Original Thumb B at 1A7114 targets 1A7098.
    sub lr, lr, #0x7E
    movs pc, lr
sgPostCheckCall:
    sg_post_stage 9
    // Original Thumb BL prefix F01B; suffix FE1C remains native.
    str r0, sgTraceSavedR0
    add r0, lr, #2
    add r0, r0, #0x1B000
    str r0, sgFaultGuestLink
    ldr r13, =sgFaultGuestLink
    ldmia r13, {lr}^
    nop
    ldr r0, sgTraceSavedR0
    movs pc, lr
sgPostCheckReturn:
    mov r11, r0
    sg_post_stage 0xA
    movs pc, lr
sgPostExtraReturn:
    mov r3, #0x41
    // MOVS sets N/Z, preserves C/V.
    mrs r13, spsr
    bic r13, r13, #0xC0000000
    msr spsr_f, r13
    sg_post_stage 0xB
    movs pc, lr
sgPostLoop:
    mov r3, r8
    sg_post_stage 0xC
    movs pc, lr
sgPostAlternate:
    mov r2, #0
    mrs r13, spsr
    bic r13, r13, #0x80000000
    orr r13, r13, #0x40000000
    msr spsr_f, r13
    sg_post_stage 0xD
    movs pc, lr
sgPostCallbackOne:
    ldr r3, [r4]
    sg_post_stage 0xE
    movs pc, lr
sgPostOtherReturn:
    sg_post_stage 0xF
    // Original B at 1A70CC targets 1A7068.
    sub lr, lr, #0x66
    movs pc, lr

sgPaletteCallbackExit:
    str r0, sgFaultReturnTarget
    mov r13, #7
    str r13, sgFaultCallStage
    mov lr, r0
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

// Terminal diagnostic in abort mode. IRQ/FIQ disabled; no stack needed.
// LR was adjusted by memu_prefetchAbort to the faulting fetch address.
.global sgTraceInvalidFetch
sgTraceInvalidFetch:
    msr cpsr_c, #0xD7
    ldr r13, =0x05000402
    mov r0, #0x001F
    strh r0, [r13] // tile 1 red: invalid fetch captured
    mov r0, lr
    sg_hex 0x0620405C // exact faulting fetch address
    ldr r13, =sgTraceFaultRegs
    stmia r13, {sp,lr}^
    nop
    ldr r0, sgTraceFaultRegs
    sg_hex 0x062042C4 // user SP
    ldr r0, sgTraceFaultRegs+4
    sg_hex 0x062042DC // user LR
    ldr r0, sgFaultReturnTarget
    sg_hex 0x0620455C // last recorded saved return target
    ldr r0, sgFaultCallStage
    sg_hex 0x06204044 // last callback call stage, replaces save caller
1:
    b 1b

.balign 4
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
