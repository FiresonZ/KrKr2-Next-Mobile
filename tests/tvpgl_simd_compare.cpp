/**
 * @file tvpgl_simd_compare.cpp
 * @brief SIMD (Highway) vs 标量 (`*_c`) 逐像素比对测试
 *
 * 背景（docs/dev/conventions.md §9）：tvpgl 的 SIMD 公式以 cpp/core/visual/tvpgl.cpp
 * 的 `*_c` 标量为准。SubBlend / ScreenBlend_o / AdditiveAlphaBlend / PS alpha 等公式
 * 缺陷已于 2026-09 修复，但从未做过逐像素验证。本测试在 Linux 宿主上把同一批随机像素
 * 分别用 scalar(`*_c`) 与 SIMD(`_hwy`，经 TVPGL_SIMD_Init 派发)跑一遍，逐像素比对。
 *
 * 高危函数要求位级一致（bit-exact）；发现不一致即打印首处差异并计为失败。
 * 运行方式：由 ctest 调用（engine_verify.yml 的 "Run tests" 步骤）。
 */

#include <cstdint>
#include <cstdio>
#include <vector>

#include "tvpgl.h"
#include "tvpgl_simd_init.h"

// 生产路径顺序：TVPInitTVPGL() 先调 TVPGL_C_Init()（把全部函数指针设为 *_c 标量
// 默认），再调 TVPGL_SIMD_Init()（覆盖为 _hwy）。测试必须同序——否则被回退到
// 标量的函数（TVPGL_SIMD_Init 不再赋值）其指针会保持零初始化(NULL)，调用即崩。
// TVPGL_C_Init 未在头文件声明，此处补 C++ 链接的外部声明（定义见
// cpp/core/visual/gl/blend_function.cpp）。
extern void TVPGL_C_Init();

// 确定性伪随机（xorshift32），保证可复现
static uint32_t g_rng = 0x9E37'79B9u;
static uint32_t NextRng() {
    g_rng ^= g_rng << 13;
    g_rng ^= g_rng >> 17;
    g_rng ^= g_rng << 5;
    return g_rng;
}

// 一张测试图像的长度（16 的倍数，便于 SIMD 多 lane 对齐路径覆盖）
static const tjs_int kLen = 2048;
static const tjs_int kOpa = 128; // 半透明强度，覆盖 (255-opa) 支路

static int g_failures = 0;

// 3 参普通混合（dest, src, len）
using PlainFn = void (*)(tjs_uint32 *, const tjs_uint32 *, tjs_int);
// 4 参带强度混合（dest, src, len, opa）
using OpaFn = void (*)(tjs_uint32 *, const tjs_uint32 *, tjs_int, tjs_int);

static void ComparePlain(const char *name, PlainFn scalarFn, PlainFn simdFn) {
    std::vector<tjs_uint32> src(kLen), ref(kLen), got(kLen);
    for (tjs_int i = 0; i < kLen; ++i) {
        src[i] = NextRng();
        ref[i] = NextRng();
        got[i] = ref[i];
    }
    scalarFn(ref.data(), src.data(), kLen);
    simdFn(got.data(), src.data(), kLen);
    for (tjs_int i = 0; i < kLen; ++i) {
        if (ref[i] != got[i]) {
            std::fprintf(stderr, "[MISMATCH] %s idx=%d scalar=%08X simd=%08X\n",
                         name, i, ref[i], got[i]);
            ++g_failures;
            return;
        }
    }
}

static void CompareOpa(const char *name, OpaFn scalarFn, OpaFn simdFn) {
    std::vector<tjs_uint32> src(kLen), ref(kLen), got(kLen);
    for (tjs_int i = 0; i < kLen; ++i) {
        src[i] = NextRng();
        ref[i] = NextRng();
        got[i] = ref[i];
    }
    scalarFn(ref.data(), src.data(), kLen, kOpa);
    simdFn(got.data(), src.data(), kLen, kOpa);
    for (tjs_int i = 0; i < kLen; ++i) {
        if (ref[i] != got[i]) {
            std::fprintf(stderr, "[MISMATCH] %s idx=%d scalar=%08X simd=%08X\n",
                         name, i, ref[i], got[i]);
            ++g_failures;
            return;
        }
    }
}

// ---------------------------------------------------------------------------
// “标量参照”＝生产路径真正使用的标量＝TVPGL_C_Init() 派发的函数指针。
// C_Init 用 SET_BLEND_*_FUNCTIONS 让指针指向 blend_function.cpp 的 functor，
// 并非一律等于 tvpgl.cpp 的 *_c（例：PsOverlay/HardLight → TVP_ps_overlay/hard_light，
// 与 TVPPs*Blend_c 不同）。故比较对象应为“生产标量(C_Init 后)” vs
// “SIMD(C_Init+SIMD_Init 后)”，即同一条生产路径开/关 SIMD 的输出差异。
// 捕获时机：C_Init 之后、SIMD_Init 之前。
// ---------------------------------------------------------------------------
static PlainFn s_SubBlend, s_SubBlend_HDA, s_ScreenBlend, s_ScreenBlend_HDA,
    s_AddAlpha, s_AddAlpha_HDA;
static OpaFn s_SubBlend_o, s_SubBlend_HDA_o, s_ScreenBlend_o, s_ScreenBlend_HDA_o,
    s_AddAlpha_o, s_AddAlpha_HDA_o;
static PlainFn s_PsAlpha, s_PsAdd, s_PsSub, s_PsMul, s_PsScreen, s_PsOverlay,
    s_PsHardLight, s_PsLighten, s_PsDarken, s_PsDiff, s_PsExclusion;
static OpaFn s_PsAlpha_o, s_PsAdd_o, s_PsSub_o, s_PsMul_o, s_PsScreen_o,
    s_PsOverlay_o, s_PsHardLight_o, s_PsLighten_o, s_PsDarken_o, s_PsDiff_o,
    s_PsExclusion_o;

// 覆盖 conventions §9 高危/中危类别；scalar 参照一律用捕获的生产标量
static void RunSubBlendFamily() {
    ComparePlain("SubBlend", s_SubBlend, TVPSubBlend);
    ComparePlain("SubBlend_HDA", s_SubBlend_HDA, TVPSubBlend_HDA);
    CompareOpa("SubBlend_o", s_SubBlend_o, TVPSubBlend_o);
    CompareOpa("SubBlend_HDA_o", s_SubBlend_HDA_o, TVPSubBlend_HDA_o);
}

static void RunScreenBlendFamily() {
    ComparePlain("ScreenBlend", s_ScreenBlend, TVPScreenBlend);
    ComparePlain("ScreenBlend_HDA", s_ScreenBlend_HDA, TVPScreenBlend_HDA);
    CompareOpa("ScreenBlend_o", s_ScreenBlend_o, TVPScreenBlend_o);
    CompareOpa("ScreenBlend_HDA_o", s_ScreenBlend_HDA_o, TVPScreenBlend_HDA_o);
}

static void RunAdditiveAlphaBlendFamily() {
    ComparePlain("AdditiveAlphaBlend", s_AddAlpha, TVPAdditiveAlphaBlend);
    ComparePlain("AdditiveAlphaBlend_HDA", s_AddAlpha_HDA, TVPAdditiveAlphaBlend_HDA);
    CompareOpa("AdditiveAlphaBlend_o", s_AddAlpha_o, TVPAdditiveAlphaBlend_o);
    CompareOpa("AdditiveAlphaBlend_HDA_o", s_AddAlpha_HDA_o, TVPAdditiveAlphaBlend_HDA_o);
}

// PS 混合：NORM 与 _o 两类
#define PS_COMPARE(NAME)                                                       \
    do {                                                                       \
        ComparePlain("Ps" #NAME "Blend", s_Ps##NAME, TVPPs##NAME##Blend);      \
        CompareOpa("Ps" #NAME "Blend_o", s_Ps##NAME##_o,                       \
                   TVPPs##NAME##Blend_o);                                      \
    } while (false)

static void RunPsBlendFamilies() {
    PS_COMPARE(Alpha);
    PS_COMPARE(Add);
    PS_COMPARE(Sub);
    PS_COMPARE(Mul);
    PS_COMPARE(Screen);
    PS_COMPARE(Overlay);
    PS_COMPARE(HardLight);
    PS_COMPARE(Lighten);
    PS_COMPARE(Darken);
    PS_COMPARE(Diff);
    PS_COMPARE(Exclusion);
}

int main() {
    // 生产顺序：先 C_Init（全部标量默认）→ 立刻捕获“生产标量”参照 → 再 SIMD_Init。
    TVPGL_C_Init();
    s_SubBlend = TVPSubBlend;       s_SubBlend_HDA = TVPSubBlend_HDA;
    s_SubBlend_o = TVPSubBlend_o;   s_SubBlend_HDA_o = TVPSubBlend_HDA_o;
    s_ScreenBlend = TVPScreenBlend; s_ScreenBlend_HDA = TVPScreenBlend_HDA;
    s_ScreenBlend_o = TVPScreenBlend_o; s_ScreenBlend_HDA_o = TVPScreenBlend_HDA_o;
    s_AddAlpha = TVPAdditiveAlphaBlend; s_AddAlpha_HDA = TVPAdditiveAlphaBlend_HDA;
    s_AddAlpha_o = TVPAdditiveAlphaBlend_o; s_AddAlpha_HDA_o = TVPAdditiveAlphaBlend_HDA_o;
#define CAP_PS(NAME)                                                            \
    do {                                                                        \
        s_Ps##NAME = TVPPs##NAME##Blend;                                        \
        s_Ps##NAME##_o = TVPPs##NAME##Blend_o;                                  \
    } while (false)
    CAP_PS(Alpha); CAP_PS(Add); CAP_PS(Sub); CAP_PS(Mul); CAP_PS(Screen);
    CAP_PS(Overlay); CAP_PS(HardLight); CAP_PS(Lighten); CAP_PS(Darken);
    CAP_PS(Diff); CAP_PS(Exclusion);
#undef CAP_PS
    TVPGL_SIMD_Init();

    RunSubBlendFamily();
    RunScreenBlendFamily();
    RunAdditiveAlphaBlendFamily();
    RunPsBlendFamilies();

    if (g_failures == 0) {
        std::printf("tvpgl_simd_compare: ALL PASS (production-scalar == SIMD, bit-exact)\n");
        return 0;
    }
    std::printf("tvpgl_simd_compare: %d mismatches found\n", g_failures);
    return 1;
}