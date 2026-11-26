#ifdef GBAR3_HICODE_CACHE_MAPPING

#include "common.h"
#include "cp15.h"
#include "Cpsr.h"
#include "SdCache/SdCache.h"
#include "HiCodeCacheMapping.h"

[[gnu::section(".dtcm")]]
struct
{
    u32 lastHicodeBlock;
    u32 hicodeBlockMask;
} gHicodeState;

static inline u32 mpu_getRegion4(void)
{
    u32 config;
    asm volatile("mrc p15, 0, %0, c6, c4, 0\n" : "=r" (config));
    return config;
}

static inline void mpu_setRegion4(u32 config)
{
    asm volatile("mcr p15, 0, %0, c6, c4, 0\n" :: "r"(config));
}

// A/B test: map the complete 4 KiB SD-cache page into both locked
// instruction-cache segments, matching the upstream whole-page strategy.
// Keep the current SD loader and exception handling unchanged.
ITCM_CODE void hic_mapRomBlock(u32 gbaAddress)
{
    const u32 page = (gbaAddress & ~0x06000000) & ~0xFFFu;
    const u8* data = sdc_getRomBlockWithoutIrqYielding(page);
    mpu_setRegion4(page | 0x17);
    gHicodeState.lastHicodeBlock = page;
    gHicodeState.hicodeBlockMask = 0xFFFFFFFFu;

    for (u32 segment = 0; segment < 2; ++segment)
    {
        ic_setLockdown(segment, false);
        ic_setLockdown(segment, true);
        for (u32 offset = 0; offset < 2048; offset += 32)
        {
            ic_prefetch(data + segment * 2048 + offset);
        }
        for (u32 offset = 0; offset < 2048; offset += 32)
        {
            const u32 address = page + segment * 2048 + offset;
            cache_setIndex(address | (segment << 30));
            ic_setTag(address | (1 << 4));
        }
    }
    ic_setLockdown(2, false);
}

[[gnu::noinline]]
static ITCM_CODE void initializeItcm(void)
{
    ic_setLockdown(0, true);

    for (u32 i = 0; i < 2048; i += 32)
    {
        ic_prefetch((const u8*)gHicodeUndefinedData + i);
        cache_setIndex(i);
        ic_setTag(0);
    }

    ic_setLockdown(1, true);

    for (u32 i = 0; i < 2048; i += 32)
    {
        ic_prefetch((const u8*)gHicodeUndefinedData + i);
        cache_setIndex(i | (1 << 30));
        ic_setTag(0);
    }

    ic_setLockdown(2, false);
}

void hic_initialize(void)
{
    for (u32 i = 0; i < 2048 / 4; i++)
    {
        gHicodeUndefinedData[i] = HICODE_UNDEFINED_INSTRUCTION;
    }

    u32 irqs = arm_disableIrqs();
    {
        initializeItcm();
    }
    arm_restoreIrqs(irqs);
}

#endif