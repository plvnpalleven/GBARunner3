.text
.altmacro

#include "AsmMacros.inc"

arm_func sav_swiHandler
    cmp r13, #0x9A
        beq soulGoldTracePalette
    cmp r13, #0x9B
        beq soulGoldTraceReset
    cmp r13, #0x9C
        beq soulGoldTraceResource1
    cmp r13, #0x9D
        beq soulGoldTraceResource2
    cmp r13, #0x9E
        beq soulGoldTraceAfterResources
    cmp r13, #0x9F
        beq soulGoldTraceGraphicsDone
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

soulGoldTraceRead:
    sg_trace_mark 6, 0x7C00
    mov r13, #0x81 // proceed with original readFlash SWI dispatch
    b sav_swiHandler

// Reproduce original literal loads, preserving guest flags and registers.
soulGoldTracePalette:
    ldr r1, =0x05000002
    sg_trace_mark 7, 0x7FE0
    movs pc, lr

soulGoldTraceReset:
    ldr r3, =0x02038318
    // This helper may be used elsewhere; only record after slot 7.
    str r0, sgTraceSavedR0
    ldr r13, =0x0500040E
    ldrh r0, [r13]
    ldr r13, =0x7FE0
    cmp r0, r13
    ldr r0, sgTraceSavedR0
    bne 1f
    sg_trace_mark 8, 0x03FF
1:
    movs pc, lr

soulGoldTraceResource1:
    ldr r0, =0x0868028C
    sg_trace_mark 9, 0x03E0
    movs pc, lr

soulGoldTraceResource2:
    ldr r0, =0x086801C4
    sg_trace_mark 10, 0x7C1F
    movs pc, lr

soulGoldTraceAfterResources:
    ldr r0, =0x0868054C
    sg_trace_mark 11, 0x01FF
    movs pc, lr

soulGoldTraceGraphicsDone:
    ldr r3, =0x0000FFFF
    sg_trace_mark 12, 0x7C00
    movs pc, lr

.balign 4
sgTraceSavedR0:
    .word 0
.pool
