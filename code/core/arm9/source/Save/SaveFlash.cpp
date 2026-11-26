#include "common.h"
#include <string.h>
#include <libtwl/mem/memSwap.h>
#include <libtwl/gfx/gfxPalette.h>
#include "MemFastSearch.h"
#include "Save.h"
#include "SaveSwi.h"
#include "SaveFlashDefinitions.h"
#include "SaveTypeInfo.h"
#include "MemoryEmulator/RomDefs.h"
#include "SdCache/SdCache.h"
#include "SaveFlash.h"

#define MAKER_ID_MACRONIX           0xC2
#define DEVICE_ID_MACRONIX_512K     0x1C
#define DEVICE_ID_MACRONIX_1M       0x09

static const u32 sIdentifyFlashV120Sig[] = { 0xB082B580u, 0x480E466Fu, 0x880A490Du, 0x1C114B0Du };
static const u32 sIdentifyFlashV123Sig[] = { 0x4A07B510u, 0x49078810u, 0x21034008u, 0x80104308u };
static const u32 sIdentifyFlash1MV103Sig[] = { 0x4A07B510u, 0x49078810u, 0x21034008u, 0x80104308u };
static const u32 sVerifyFlashV126Sig[] = { 0xB0C0B570u, 0x1C161C0Du, 0x0C040400u, 0x88104A07u };
static const u32 sReadFlash512V130Sig[] = { 0xB0A0B5F0u, 0x1C161C0Du, 0x04031C1Fu, 0x4A0F0C1Cu };
static const u32 sVerifyFlash512V130Sig[] = { 0xB0C0B570u, 0x1C161C0Du, 0x0C140402u, 0x6800480Eu };
static const u32 sVerifyFlashSector512V130Sig[] = { 0xB0C0B530u, 0x04031C0Du, 0x4A0F0C1Cu, 0x490F8810u };

// FLASH1M_V103 library as compiled by modern gcc (pokeemerald-expansion based hacks)
static const u32 sIdentifyFlash1MV103GccSig[] = { 0x4A192103u, 0x430B8813u, 0x8013B510u, 0xFD7CF7FFu };
static const u32 sReadFlash1MV103GccSig[] = { 0x46C6B5F0u, 0xB5002403u, 0x04000017u, 0x46984A23u };
static const u32 sVerifyFlashSector1MV103GccSig[] = { 0x2103468Cu, 0x4A20B570u, 0x430B8813u, 0x8013B0C0u };
static const u32 sVerifyFlash1MV103GccSig[] = { 0x000FB5F0u, 0x04002180u, 0x469C0C03u, 0x681E4B1Fu };

struct flash_patchinfo_t
{
    u32* progSectorPtr;
    u32* progBytePtr;
    u32* eraseChipPtr;
    u32* eraseSectorPtr;
    u32* pollingSrPtr;
    u32* flMaxTimePtr;
    u32* flashPtr;
};

static flash_patchinfo_t sPatchInfo;
static flash_v120_type sFlashType;

// SoulGold-only runtime probe: DS bottom-screen backdrop is a debug indicator.
// RED: compatibility patch installed but IdentifyFlash has not entered.
// YELLOW: IdentifyFlash entered; GREEN: IdentifyFlash finished.
static bool sSoulgoldRuntimeProbeEnabled = false;
extern "C" { u8 gSoulgoldTraceEnabled = 0; }
static const u16 sMaxTime[] = { 0xA, 0xFFBD, 0xC2, 0xA, 0xFFBD, 0xC2, 0x28, 0xFFBD, 0xC2, 0xC8, 0xFFBD, 0xC2 };

static void readFlash(u16 secNo, u32 offset, u8* dst, u32 size)
{
    u32 saveAddress = (secNo << 12) + offset;
    for (u32 i = 0; i < size; ++i)
    {
        *dst++ = sav_readSaveByteFromFileFromUserMode(saveAddress++);
    }
}

static u32 verifyFlashSector(u16 secNo, const u8* src)
{
    u32 saveAddress = secNo << 12;
    for (u32 i = 0; i < (1 << 12); ++i)
    {
        u8 saveByte = sav_readSaveByteFromFileFromUserMode(saveAddress++);
        u8 expectedByte = *src++;
        if (saveByte != expectedByte)
            return 0x0E000000 + ((secNo & 0xF) << 12) + i;
    }
    return 0;
}

static u32 verifyFlash(u16 secNo, const u8* src, u32 size)
{
    u32 saveAddress = secNo << 12;
    for (u32 i = 0; i < size; ++i)
    {
        u8 saveByte = sav_readSaveByteFromFileFromUserMode(saveAddress++);
        u8 expectedByte = *src++;
        if (saveByte != expectedByte)
            return 0x0E000000 + ((secNo & 0xF) << 12) + i;
    }
    return 0;
}

static u16 eraseFlashChip()
{
    for (u32 i = 0; i < sizeof(gSaveData); ++i)
    {
        sav_writeSaveByteToFileFromUserMode(i, 0xFF);
    }
    sav_flushSaveFileFromUserMode();
    return 0;
}

static u16 eraseFlashSector(u16 secNo)
{
    for (u32 i = 0; i < (1 << 12); ++i)
    {
        sav_writeSaveByteToFileFromUserMode((secNo << 12) + i, 0xFF);
    }
    sav_flushSaveFileFromUserMode();
    return 0;
}

static u16 programFlashSector(u16 secNo, const u8* src)
{
    for (u32 i = 0; i < (1 << 12); ++i)
    {
        sav_writeSaveByteToFileFromUserMode((secNo << 12) + i, *src++);
    }
    sav_flushSaveFileFromUserMode();
    return 0;
}

static u16 programFlashByte1M(u16 secNo, u32 offset, u8 data)
{
    sav_writeSaveByteToFileFromUserMode((secNo << 12) + offset, data);
    sav_flushSaveFileFromUserMode();
    return 0;
}

static u16 identifyFlash512()
{
    *sPatchInfo.progSectorPtr = (u32)sav_callSwi8;
    *sPatchInfo.eraseChipPtr = (u32)sav_callSwi9;
    *sPatchInfo.eraseSectorPtr = (u32)sav_callSwi10;
    *sPatchInfo.pollingSrPtr = 0;
    *sPatchInfo.flMaxTimePtr = (u32)sMaxTime;
    *sPatchInfo.flashPtr = (u32)&sFlashType;
    return 0;
}

static void initializeFlash512()
{
    sav_swiTable[8] = (void*)programFlashSector;
    sav_swiTable[9] = (void*)eraseFlashChip;
    sav_swiTable[10] = (void*)eraseFlashSector;

    sFlashType.saveSize = 64 * 1024;
    sFlashType.sector.size = 0x1000;
    mem_swapByte(12, &sFlashType.sector.shift);
    sFlashType.sector.count = sFlashType.saveSize >> sFlashType.sector.shift;
    sFlashType.sector.top = 0;
    sFlashType.agbWait[0] = 0;
    sFlashType.agbWait[1] = 3;
    mem_swapByte(MAKER_ID_MACRONIX, &sFlashType.makerId);
    mem_swapByte(DEVICE_ID_MACRONIX_512K, &sFlashType.deviceId);
}

static u16 identifyFlash1M()
{
    if (sSoulgoldRuntimeProbeEnabled)
        GFX_PLTT_BG_SUB[0] = 0x03FF; // yellow: entered

    *sPatchInfo.progSectorPtr = (u32)sav_callSwi8;
    if (sPatchInfo.progBytePtr)
    {
        *sPatchInfo.progBytePtr = (u32)sav_callSwi9;
    }
    *sPatchInfo.eraseChipPtr = (u32)sav_callSwi10;
    *sPatchInfo.eraseSectorPtr = (u32)sav_callSwi11;
    *sPatchInfo.pollingSrPtr = 0;
    *sPatchInfo.flMaxTimePtr = (u32)sMaxTime;
    *sPatchInfo.flashPtr = (u32)&sFlashType;
    if (sSoulgoldRuntimeProbeEnabled)
        GFX_PLTT_BG_SUB[0] = 0x03E0; // green: all pointer assignments finished
    return 0;
}

static void initializeFlash1M()
{
    sav_swiTable[8] = (void*)programFlashSector;
    sav_swiTable[9] = (void*)programFlashByte1M;
    sav_swiTable[10] = (void*)eraseFlashChip;
    sav_swiTable[11] = (void*)eraseFlashSector;

    sFlashType.saveSize = 128 * 1024;
    sFlashType.sector.size = 0x1000;
    mem_swapByte(12, &sFlashType.sector.shift);
    sFlashType.sector.count = sFlashType.saveSize >> sFlashType.sector.shift;
    sFlashType.sector.top = 0;
    sFlashType.agbWait[0] = 0;
    sFlashType.agbWait[1] = 3;
    mem_swapByte(MAKER_ID_MACRONIX, &sFlashType.makerId);
    mem_swapByte(DEVICE_ID_MACRONIX_1M, &sFlashType.deviceId);
}

static bool loadDataV120(const SaveTypeInfo* saveTypeInfo, FIL* romFile, u32 tagRomAddress, u8* tempBuffer)
{
    if (f_lseek(romFile, tagRomAddress + ((saveTypeInfo->tagLength + 3) & ~3)) != FR_OK)
    {
        return false;
    }
    UINT read;
    if (f_read(romFile, tempBuffer, 0x94, &read) != FR_OK || read != 0x94)
    {
        return false;
    }

    sPatchInfo.progSectorPtr = *(u32**)(tempBuffer + FLASH_V120_OFFSET_PROG_SECTOR);
    sPatchInfo.progBytePtr = nullptr;
    sPatchInfo.eraseChipPtr = *(u32**)(tempBuffer + FLASH_V120_OFFSET_ERASE_CHIP);
    sPatchInfo.eraseSectorPtr = *(u32**)(tempBuffer + FLASH_V120_OFFSET_ERASE_SECTOR);
    sPatchInfo.pollingSrPtr = *(u32**)(tempBuffer + FLASH_V120_OFFSET_POLLING_SR);
    sPatchInfo.flMaxTimePtr = *(u32**)(tempBuffer + FLASH_V120_OFFSET_FL_MAXTIME);
    sPatchInfo.flashPtr = *(u32**)(tempBuffer + FLASH_V120_OFFSET_FLASH);
    return true;
}

bool flash_patchV120(const SaveTypeInfo* saveTypeInfo, FIL* romFile, u32 tagRomAddress, u8* tempBuffer)
{
    if (!loadDataV120(saveTypeInfo, romFile, tagRomAddress, tempBuffer))
    {
        return false;
    }

    u32* pIdentify = (u32*)mem_fastSearch16((const u32*)ROM_LINEAR_DS_ADDRESS, ROM_LINEAR_SIZE, sIdentifyFlashV120Sig);
    if (!pIdentify)
    {
        return false;
    }

    sav_swiTable[0] = (void*)identifyFlash512;
    *(u16*)pIdentify = SAVE_THUMB_SWI(0);

    sav_swiTable[1] = (void*)readFlash;
    *(u16*)((*(u32*)(tempBuffer + FLASH_V120_OFFSET_READ) & ~1) - ROM_LINEAR_GBA_ADDRESS + ROM_LINEAR_DS_ADDRESS) = SAVE_THUMB_SWI(1);

    sav_swiTable[2] = (void*)verifyFlashSector;
    *(u16*)((*(u32*)(tempBuffer + FLASH_V120_OFFSET_VERIFY_SECTOR) & ~1) - ROM_LINEAR_GBA_ADDRESS + ROM_LINEAR_DS_ADDRESS) = SAVE_THUMB_SWI(2);

    initializeFlash512();
    return true;
}

bool flash_patchV123(const SaveTypeInfo* saveTypeInfo, FIL* romFile, u32 tagRomAddress, u8* tempBuffer)
{
    if (!loadDataV120(saveTypeInfo, romFile, tagRomAddress, tempBuffer))
    {
        return false;
    }

    u32* pIdentify = (u32*)mem_fastSearch16((const u32*)ROM_LINEAR_DS_ADDRESS, ROM_LINEAR_SIZE, sIdentifyFlashV123Sig);
    if (!pIdentify)
    {
        return false;
    }

    sav_swiTable[0] = (void*)identifyFlash512;
    *(u16*)pIdentify = SAVE_THUMB_SWI(0);

    sav_swiTable[1] = (void*)readFlash;
    *(u16*)((*(u32*)(tempBuffer + FLASH_V120_OFFSET_READ) & ~1) - ROM_LINEAR_GBA_ADDRESS + ROM_LINEAR_DS_ADDRESS) = SAVE_THUMB_SWI(1);

    sav_swiTable[2] = (void*)verifyFlashSector;
    *(u16*)((*(u32*)(tempBuffer + FLASH_V120_OFFSET_VERIFY_SECTOR) & ~1) - ROM_LINEAR_GBA_ADDRESS + ROM_LINEAR_DS_ADDRESS) = SAVE_THUMB_SWI(2);

    initializeFlash512();
    return true;
}

bool flash_patchV126(const SaveTypeInfo* saveTypeInfo, FIL* romFile, u32 tagRomAddress, u8* tempBuffer)
{
    if (!loadDataV120(saveTypeInfo, romFile, tagRomAddress, tempBuffer))
    {
        return false;
    }

    u32* pIdentify = (u32*)mem_fastSearch16((const u32*)ROM_LINEAR_DS_ADDRESS, ROM_LINEAR_SIZE, sIdentifyFlashV123Sig);
    if (!pIdentify)
    {
        return false;
    }

    sav_swiTable[0] = (void*)identifyFlash512;
    *(u16*)pIdentify = SAVE_THUMB_SWI(0);

    sav_swiTable[1] = (void*)readFlash;
    *(u16*)((*(u32*)(tempBuffer + FLASH_V120_OFFSET_READ) & ~1) - ROM_LINEAR_GBA_ADDRESS + ROM_LINEAR_DS_ADDRESS) = SAVE_THUMB_SWI(1);

    sav_swiTable[2] = (void*)verifyFlashSector;
    *(u16*)((*(u32*)(tempBuffer + FLASH_V120_OFFSET_VERIFY_SECTOR) & ~1) - ROM_LINEAR_GBA_ADDRESS + ROM_LINEAR_DS_ADDRESS) = SAVE_THUMB_SWI(2);

    if (sav_tryPatchFunction(sVerifyFlashV126Sig, 3, (void*)verifyFlash))
    {
        initializeFlash512();
        return true;
    }
    return false;
}

bool flash_patch512V130(const SaveTypeInfo* saveTypeInfo, FIL* romFile, u32 tagRomAddress, u8* tempBuffer)
{
    if (f_lseek(romFile, tagRomAddress + ((saveTypeInfo->tagLength + 3) & ~3)) != FR_OK)
    {
        return false;
    }
    UINT read = 0;
    if (f_read(romFile, tempBuffer, 0x94, &read) != FR_OK || read != 0x94)
    {
        return false;
    }

    sPatchInfo.progSectorPtr = *(u32**)(tempBuffer + FLASH_512V130_OFFSET_PROG_SECTOR);
    sPatchInfo.progBytePtr = nullptr;
    sPatchInfo.eraseChipPtr = *(u32**)(tempBuffer + FLASH_512V130_OFFSET_ERASE_CHIP);
    sPatchInfo.eraseSectorPtr = *(u32**)(tempBuffer + FLASH_512V130_OFFSET_ERASE_SECTOR);
    sPatchInfo.pollingSrPtr = *(u32**)(tempBuffer + FLASH_512V130_OFFSET_POLLING_SR);
    sPatchInfo.flMaxTimePtr = *(u32**)(tempBuffer + FLASH_512V130_OFFSET_FL_MAXTIME);
    sPatchInfo.flashPtr = *(u32**)(tempBuffer + FLASH_512V130_OFFSET_FLASH);

    if (sav_tryPatchFunction(sIdentifyFlashV123Sig, 0, (void*)identifyFlash512) &&
        sav_tryPatchFunction(sReadFlash512V130Sig, 1, (void*)readFlash) &&
        sav_tryPatchFunction(sVerifyFlashSector512V130Sig, 2, (void*)verifyFlashSector) &&
        sav_tryPatchFunction(sVerifyFlash512V130Sig, 3, (void*)verifyFlash))
    {
        initializeFlash512();
        return true;
    }
    return false;
}

bool flash_patch1MV102(const SaveTypeInfo* saveTypeInfo, FIL* romFile, u32 tagRomAddress, u8* tempBuffer)
{
    if (f_lseek(romFile, tagRomAddress + ((saveTypeInfo->tagLength + 3) & ~3)) != FR_OK)
    {
        return false;
    }
    UINT read = 0;
    if (f_read(romFile, tempBuffer, 0x94, &read) != FR_OK || read != 0x94)
    {
        return false;
    }

    sPatchInfo.progSectorPtr = *(u32**)(tempBuffer + FLASH_1MV102_OFFSET_PROG_SECTOR);
    sPatchInfo.progBytePtr = nullptr;
    sPatchInfo.eraseChipPtr = *(u32**)(tempBuffer + FLASH_1MV102_OFFSET_ERASE_CHIP);
    sPatchInfo.eraseSectorPtr = *(u32**)(tempBuffer + FLASH_1MV102_OFFSET_ERASE_SECTOR);
    sPatchInfo.pollingSrPtr = *(u32**)(tempBuffer + FLASH_1MV102_OFFSET_POLLING_SR);
    sPatchInfo.flMaxTimePtr = *(u32**)(tempBuffer + FLASH_1MV102_OFFSET_FL_MAXTIME + (
        saveTypeInfo->type == SAVE_TYPE_FLASH1M_V102 ? 0 : 4));
    sPatchInfo.flashPtr = *(u32**)(tempBuffer + FLASH_1MV102_OFFSET_FLASH + (
        saveTypeInfo->type == SAVE_TYPE_FLASH1M_V102 ? 0 : 4));

    const u32* identifySignature = saveTypeInfo->type == SAVE_TYPE_FLASH1M_V102
        ? sIdentifyFlashV123Sig : sIdentifyFlash1MV103Sig;

    if (sav_tryPatchFunction(identifySignature, 0, (void*)identifyFlash1M) &&
        sav_tryPatchFunction(sReadFlash512V130Sig, 1, (void*)readFlash) &&
        sav_tryPatchFunction(sVerifyFlashSector512V130Sig, 2, (void*)verifyFlashSector) &&
        sav_tryPatchFunction(sVerifyFlash512V130Sig, 3, (void*)verifyFlash))
    {
        initializeFlash1M();
        return true;
    }
    return false;
}

static bool isIWramPointer(const u32* ptr)
{
    return (u32)ptr - 0x03000000u < 0x8000u;
}

static const u32* findInLinearRom(const u32* signature)
{
    return mem_fastSearch16((const u32*)ROM_LINEAR_DS_ADDRESS, ROM_LINEAR_SIZE, signature);
}

static bool tryPatchFlash1MV103Gcc()
{
    const u8* identify = (const u8*)findInLinearRom(sIdentifyFlash1MV103GccSig);
    if (!identify ||
        !findInLinearRom(sReadFlash1MV103GccSig) ||
        !findInLinearRom(sVerifyFlashSector1MV103GccSig) ||
        !findInLinearRom(sVerifyFlash1MV103GccSig))
    {
        return false;
    }

    // the iwram variables are not referenced after the version tag, so take them from the IdentifyFlash literal pool
    flash_patchinfo_t patchInfo;
    patchInfo.progBytePtr = *(u32**)(identify + FLASH_1MV103_GCC_OFFSET_PROG_BYTE);
    patchInfo.progSectorPtr = *(u32**)(identify + FLASH_1MV103_GCC_OFFSET_PROG_SECTOR);
    patchInfo.eraseChipPtr = *(u32**)(identify + FLASH_1MV103_GCC_OFFSET_ERASE_CHIP);
    patchInfo.eraseSectorPtr = *(u32**)(identify + FLASH_1MV103_GCC_OFFSET_ERASE_SECTOR);
    patchInfo.pollingSrPtr = *(u32**)(identify + FLASH_1MV103_GCC_OFFSET_POLLING_SR);
    patchInfo.flMaxTimePtr = *(u32**)(identify + FLASH_1MV103_GCC_OFFSET_FL_MAXTIME);
    patchInfo.flashPtr = *(u32**)(identify + FLASH_1MV103_GCC_OFFSET_FLASH);

    if (!isIWramPointer(patchInfo.progBytePtr) ||
        !isIWramPointer(patchInfo.progSectorPtr) ||
        !isIWramPointer(patchInfo.eraseChipPtr) ||
        !isIWramPointer(patchInfo.eraseSectorPtr) ||
        !isIWramPointer(patchInfo.pollingSrPtr) ||
        !isIWramPointer(patchInfo.flMaxTimePtr) ||
        !isIWramPointer(patchInfo.flashPtr))
    {
        return false;
    }

    sPatchInfo = patchInfo;
    return sav_tryPatchFunction(sIdentifyFlash1MV103GccSig, 0, (void*)identifyFlash1M) &&
        sav_tryPatchFunction(sReadFlash1MV103GccSig, 1, (void*)readFlash) &&
        sav_tryPatchFunction(sVerifyFlashSector1MV103GccSig, 2, (void*)verifyFlashSector) &&
        sav_tryPatchFunction(sVerifyFlash1MV103GccSig, 3, (void*)verifyFlash);
}

// SoulGold v1.2.1 uses different GCC-generated Thumb prologues from Emerald Rogue.
// These offsets are validated against this precise ROM layout before anything is patched.
// Never use this for another ROM version unless its binary layout has been checked.
static bool tryPatchSoulgold121()
{
    u8* const rom = (u8*)ROM_LINEAR_DS_ADDRESS;
    if (memcmp(rom + 0xA0, "Soulgold", 8) != 0 ||
        memcmp(rom + 0x204, "RHHEXP", 6) != 0 ||
        memcmp(rom + 0x2144, "FLASH1M_V103", 13) != 0)
    {
        return false;
    }

    static const u32 identifySig[] = { 0x4A192103u, 0x430B8813u, 0x8013B510u, 0xFD7AF7FFu };
    static const u32 readSig[] = { 0x2503B5F0u, 0x4C2446C6u, 0x001A4694u, 0x432B8823u };
    static const u32 verifySectorSig[] = { 0x2503B5F0u, 0x88224C21u, 0x432A0003u, 0x24808022u };
    static const u32 verifyNBytesSig[] = { 0x4C23B5F0u, 0x46AC6825u, 0x00034666u, 0x68362580u };
    static const u32 expectedPointers[] = {
        0x03002E0Cu, 0x03002E04u, 0x03002E14u, 0x03002E18u,
        0x03002E00u, 0x03002E1Cu, 0x03002E08u
    };

    // All guards are checked before overwriting even one Thumb instruction.
    if (memcmp(rom + 0x61B0, identifySig, sizeof(identifySig)) != 0 ||
        memcmp(rom + 0x5F04, readSig, sizeof(readSig)) != 0 ||
        memcmp(rom + 0x5FD8, verifySectorSig, sizeof(verifySectorSig)) != 0 ||
        memcmp(rom + 0x607C, verifyNBytesSig, sizeof(verifyNBytesSig)) != 0 ||
        memcmp(rom + 0x6224, expectedPointers, sizeof(expectedPointers)) != 0)
    {
        return false;
    }

    // IWRAM variable addresses were recovered from IdentifyFlash's literal pool.
    // They are the same categories of pointers used by the existing Flash1M patch.
    sPatchInfo.progBytePtr = (u32*)expectedPointers[0];
    sPatchInfo.progSectorPtr = (u32*)expectedPointers[1];
    sPatchInfo.eraseChipPtr = (u32*)expectedPointers[2];
    sPatchInfo.eraseSectorPtr = (u32*)expectedPointers[3];
    sPatchInfo.pollingSrPtr = (u32*)expectedPointers[4];
    sPatchInfo.flMaxTimePtr = (u32*)expectedPointers[5];
    sPatchInfo.flashPtr = (u32*)expectedPointers[6];

    // SoulGold 1.2.1: retain the original IdentifyFlash routine, including
    // its native FlashSetupInfo selection and seven IWRAM pointer writes.
    // The verified BL at 0x61BC targets ReadFlashId at 0x5CB4. Return
    // the game's own MX29L010 ID (0x09C2) from that routine instead of
    // accessing physical cartridge Flash that the DSi does not provide.
    static const u32 idSig[] = { 0xB091B530u, 0x2201466Bu, 0x4B281D5Cu, 0x601C4928u };
    // Native MX29L010 callback entrypoints from the ROM's FlashSetupInfo.
    static const u32 byteSig[] = { 0x46C6B5F0u, 0x04004E1Fu, 0xB5000C03u, 0x68334698u };
    static const u32 sectorSig[] = { 0x4657B5F0u, 0x4645464Eu, 0xB5E046DEu, 0x68234C2Eu };
    static const u32 eraseChipSig[] = { 0xB5302103u, 0x258020AAu, 0x4C134B12u, 0x8822681Bu };
    static const u32 eraseSectorSig[] = { 0x464FB5F0u, 0x464646D6u, 0x4F29B5C0u, 0x895B683Bu };
    if (memcmp(rom + 0x5CB4, idSig, sizeof(idSig)) != 0 ||
        memcmp(rom + 0x640C, byteSig, sizeof(byteSig)) != 0 ||
        memcmp(rom + 0x64A4, sectorSig, sizeof(sectorSig)) != 0 ||
        memcmp(rom + 0x62DC, eraseChipSig, sizeof(eraseChipSig)) != 0 ||
        memcmp(rom + 0x6344, eraseSectorSig, sizeof(eraseSectorSig)) != 0)
    {
        return false;
    }

    // Exact v1.2.1 callsite and epilogue guards, checked against the ROM.
    if (*(u16*)(rom + 0x620E) != 0x6013 ||
        *(u16*)(rom + 0x1A3D3E) != 0xF662 ||
        *(u16*)(rom + 0x1A3D40) != 0xFA37 ||
        *(u16*)(rom + 0x1A3D42) != 0x4B06 ||
        *(u16*)(rom + 0x1A3D44) != 0x2800 ||
        *(u16*)(rom + 0x1A3D58) != 0xE7F8 ||
        *(u32*)(rom + 0x1A3D5C) != 0x030040BC ||
        // Exact post-read callback observed on hardware (0x0814C92D).
        *(u16*)(rom + 0x14C92C) != 0xB500 ||
        *(u16*)(rom + 0x14C92E) != 0xF115 ||
        *(u16*)(rom + 0x14C930) != 0xFC77 ||
        *(u16*)(rom + 0x14C932) != 0xF100 ||
        *(u16*)(rom + 0x14C934) != 0xFBF1 ||
        *(u16*)(rom + 0x14C936) != 0xF102 ||
        *(u16*)(rom + 0x14C938) != 0xF967 ||
        *(u16*)(rom + 0x14C93A) != 0xF078 ||
        *(u16*)(rom + 0x14C93C) != 0xFE13 ||
        *(u16*)(rom + 0x14C93E) != 0xBC01 ||
        *(u16*)(rom + 0x14C940) != 0x4700 ||
        *(u16*)(rom + 0x14CA44) != 0x4C47 ||
        *(u16*)(rom + 0x11FF1A) != 0x0005 ||
        *(u16*)(rom + 0x11FF22) != 0x686B ||
        *(u16*)(rom + 0x11FF30) != 0x0005 ||
        *(u16*)(rom + 0x11FF38) != 0x0028 ||
        *(u16*)(rom + 0x14CA4C) != 0x0020 ||
        *(u16*)(rom + 0x14CA54) != 0x0020 ||
        *(u16*)(rom + 0x14CA5C) != 0x0020 ||
        *(u16*)(rom + 0x14CA64) != 0x4940 ||
        *(u32*)(rom + 0x14CB64) != 0x085B6CDC ||
        *(u32*)(rom + 0x14CB68) != 0x02038334 ||
        *(u16*)(rom + 0x1A70C2) != 0x6863 ||
        *(u16*)(rom + 0x1A710A) != 0x6863 ||
        *(u16*)(rom + 0x11F8A4) != 0x4650 ||
        *(u16*)(rom + 0x11F8D6) != 0x0028 ||
        *(u32*)(rom + 0x11F8F0) != 0x0811F624 ||
        *(u32*)(rom + 0x11F8F4) != 0x0811F3A0 ||
        *(u32*)(rom + 0x11F8F8) != 0x0811F744 ||
        *(u32*)(rom + 0x11F8FC) != 0x0811F62C ||
        *(u16*)(rom + 0x120394) != 0x4758 ||
        *(u16*)(rom + 0x120390) != 0x4730 ||
        *(u16*)(rom + 0x11FA52) != 0x6BB9 ||
        *(u16*)(rom + 0x11FA5A) != 0x6BF8 ||
        *(u16*)(rom + 0x18B60C) != 0x4838 ||
        *(u32*)(rom + 0x18B6F0) != 0x086801C4 ||
        *(u16*)(rom + 0x12038C) != 0x4720 ||
        *(u16*)(rom + 0x12038E) != 0x4728)
    {
        return false;
    }

    // The first post-read function is a task scheduler in high ROM.
    // Pin its 4 KiB block through the normal ROM patch-cache API.
    // All offsets below are within that same block. Verify before writing.
    u8* const taskCode = (u8*)sdc_loadRomBlockForPatching(0x08262220);
    if (*(u16*)(taskCode + 0x04) != 0x4B0D ||
        *(u16*)(taskCode + 0x28) != 0x592B ||
        *(u16*)(taskCode + 0x30) != 0x79A0 ||
        *(u16*)(taskCode + 0x3A) != 0x4700 ||
        *(u32*)(taskCode + 0x3C) != 0x03005B50 ||
        *(u32*)(taskCode + 0x40) != 0x03005B4C ||
        *(u16*)(taskCode + 0x168) != 0x4718)
    {
        return false;
    }
    *(u16*)(taskCode + 0x04) = 0xDF9F; // scheduler entry
    *(u16*)(taskCode + 0x28) = 0xDF9F; // load task function pointer
    *(u16*)(taskCode + 0x30) = 0xDF9F; // task returned
    *(u16*)(taskCode + 0x3A) = 0xDF9F; // scheduler exit

    // Trace SWIs execute in privileged mode and faithfully replace the
    // guarded Thumb instructions (see SaveSwi.s). Earlier lights persist.
    *(u16*)(rom + 0x5CB4) = 0xDF95; // return chip ID, mark slot 2
    *(u16*)(rom + 0x5CB6) = 0x4770; // bx lr
    *(u16*)(rom + 0x620E) = 0xDF96; // str r3,[r2], mark slot 3
    *(u16*)(rom + 0x1A3D42) = 0xDF97; // ldr r3,[pc,#24], mark slot 4
    *(u16*)(rom + 0x1A3D58) = 0xDF98; // branch after InitFlashTimer, slot 5
    // Keep the proven cache-sync hook, trace subsequent graphics operations.
    // Slot 7 now tracks the guest-side Flash-read epilogue.
    *(u16*)(rom + 0x11F8A4) = 0xDF9B; // type 8: sync first copied routine (r11)
    *(u16*)(rom + 0x11F8D6) = 0xDF9C; // type 8: sync second copied routine (r6)
    *(u16*)(rom + 0x11FA52) = 0xDF9D; // cache synchronization before copied ARM call
    *(u16*)(rom + 0x11FA5A) = 0xDF9E; // copied ARM routine returned
    *(u16*)(rom + 0x1A70C2) = 0xDF9F; // main-loop callback load after read
    *(u16*)(rom + 0x1A710A) = 0xDF9F; // alternate main-loop path
    // Trace compressed sprite sheets and palette loads.
    *(u16*)(rom + 0x14CA44) = 0xDF9F;
    *(u16*)(rom + 0x11FF1A) = 0xDF9F;
    *(u16*)(rom + 0x11FF22) = 0xDF9F;
    *(u16*)(rom + 0x11FF30) = 0xDF9F;
    *(u16*)(rom + 0x11FF38) = 0xDF9F;
    *(u16*)(rom + 0x14CA4C) = 0xDF9F;
    *(u16*)(rom + 0x14CA54) = 0xDF9F;
    *(u16*)(rom + 0x14CA5C) = 0xDF9F;
    *(u16*)(rom + 0x14CA64) = 0xDF9F;

    // The native setup table continues to point into the ROM, but the
    // actual Flash operations dispatch through GBARunner3's save hooks.
    // initializeFlash1M() populates the SWI 8..11 callbacks.
    sav_swiTable[1] = (void*)readFlash;
    sav_swiTable[2] = (void*)verifyFlashSector;
    sav_swiTable[3] = (void*)verifyFlash;
    // The guarded readSig also verifies the second Thumb halfword.
    // First return to the guest Thumb epilogue, mark it via a second SWI,
    // then execute BX LR back to the original game caller.
    *(u16*)(rom + 0x5F04) = 0xDF99;
    *(u16*)(rom + 0x5F06) = 0xDF9A;
    *(u16*)(rom + 0x5F08) = 0x4770;
    *(u16*)(rom + 0x5FD8) = SAVE_THUMB_SWI(2);
    *(u16*)(rom + 0x607C) = SAVE_THUMB_SWI(3);
    *(u16*)(rom + 0x64A4) = SAVE_THUMB_SWI(8);
    *(u16*)(rom + 0x640C) = SAVE_THUMB_SWI(9);
    *(u16*)(rom + 0x62DC) = SAVE_THUMB_SWI(10);
    *(u16*)(rom + 0x6344) = SAVE_THUMB_SWI(11);

    // No runtime writes to restricted hardware display registers.
    sSoulgoldRuntimeProbeEnabled = false;
    gSoulgoldTraceEnabled = 1;
    GFX_PLTT_BG_SUB[0] = 0x7FE0; // cyan during splash; grid after splash
    return true;
}

bool flash_patch1MV103(const SaveTypeInfo* saveTypeInfo, FIL* romFile, u32 tagRomAddress, u8* tempBuffer)
{
    if (tryPatchSoulgold121() || tryPatchFlash1MV103Gcc())
    {
        initializeFlash1M();
        return true;
    }

    if (f_lseek(romFile, tagRomAddress + ((saveTypeInfo->tagLength + 3) & ~3)) != FR_OK)
    {
        return false;
    }
    UINT read = 0;
    if (f_read(romFile, tempBuffer, 0x94, &read) != FR_OK || read != 0x94)
    {
        return false;
    }

    sPatchInfo.progSectorPtr = *(u32**)(tempBuffer + FLASH_1MV103_OFFSET_PROG_SECTOR);
    sPatchInfo.progBytePtr = *(u32**)(tempBuffer + FLASH_1MV103_OFFSET_PROG_BYTE);
    sPatchInfo.eraseChipPtr = *(u32**)(tempBuffer + FLASH_1MV103_OFFSET_ERASE_CHIP);
    sPatchInfo.eraseSectorPtr = *(u32**)(tempBuffer + FLASH_1MV103_OFFSET_ERASE_SECTOR);
    sPatchInfo.pollingSrPtr = *(u32**)(tempBuffer + FLASH_1MV103_OFFSET_POLLING_SR);
    sPatchInfo.flMaxTimePtr = *(u32**)(tempBuffer + FLASH_1MV103_OFFSET_FL_MAXTIME);
    sPatchInfo.flashPtr = *(u32**)(tempBuffer + FLASH_1MV103_OFFSET_FLASH);

    if (sav_tryPatchFunction(sIdentifyFlash1MV103Sig, 0, (void*)identifyFlash1M) &&
        sav_tryPatchFunction(sReadFlash512V130Sig, 1, (void*)readFlash) &&
        sav_tryPatchFunction(sVerifyFlashSector512V130Sig, 2, (void*)verifyFlashSector) &&
        sav_tryPatchFunction(sVerifyFlash512V130Sig, 3, (void*)verifyFlash))
    {
        initializeFlash1M();
        return true;
    }
    return false;
}
