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

// 覆盖 conventions §9 高危/中危类别
static void RunSubBlendFamily() {
    ComparePlain("SubBlend", &TVPSubBlend_c, TVPSubBlend);
    ComparePlain("SubBlend_HDA", &TVPSubBlend_HDA_c, TVPSubBlend_HDA);
    CompareOpa("SubBlend_o", &TVPSubBlend_o_c, TVPSubBlend_o);
    CompareOpa("SubBlend_HDA_o", &TVPSubBlend_HDA_o_c, TVPSubBlend_HDA_o);
}

static void RunScreenBlendFamily() {
    ComparePlain("ScreenBlend", &TVPScreenBlend_c, TVPScreenBlend);
    ComparePlain("ScreenBlend_HDA", &TVPScreenBlend_HDA_c, TVPScreenBlend_HDA);
    CompareOpa("ScreenBlend_o", &TVPScreenBlend_o_c, TVPScreenBlend_o);
    CompareOpa("ScreenBlend_HDA_o", &TVPScreenBlend_HDA_o_c, TVPScreenBlend_HDA_o);
}

static void RunAdditiveAlphaBlendFamily() {
    ComparePlain("AdditiveAlphaBlend", &TVPAdditiveAlphaBlend_c, TVPAdditiveAlphaBlend);
    ComparePlain("AdditiveAlphaBlend_HDA", &TVPAdditiveAlphaBlend_HDA_c, TVPAdditiveAlphaBlend_HDA);
    CompareOpa("AdditiveAlphaBlend_o", &TVPAdditiveAlphaBlend_o_c, TVPAdditiveAlphaBlend_o);
    CompareOpa("AdditiveAlphaBlend_HDA_o", &TVPAdditiveAlphaBlend_HDA_o_c, TVPAdditiveAlphaBlend_HDA_o);
}

// PS 混合：NORM 与 _o 两类（conventions §9 指出 NORM/_o 的 alpha 通道可能不一致）
#define PS_COMPARE(NAME)                                                       \
    do {                                                                       \
        ComparePlain("Ps" #NAME "Blend", &TVPPs##NAME##Blend_c,                \
                     TVPPs##NAME##Blend);                                      \
        CompareOpa("Ps" #NAME "Blend_o", &TVPPs##NAME##Blend_o_c,              \
                   TVPPs##NAME##Blend_o);                                      \
    } while (false)

static void RunPsBlendFamilies() {
    // 仅覆盖 TVPGL_SIMD_Init 真正注册了 SIMD 实现、且 conventions 归为 NORM/_o alpha 风险的模式
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
    // 先按标量初始化，再把函数指针切到 SIMD（生产路径顺序：C_Init -> SIMD_Init）
    TVPGL_SIMD_Init();

    RunSubBlendFamily();
    RunScreenBlendFamily();
    RunAdditiveAlphaBlendFamily();
    RunPsBlendFamilies();

    if (g_failures == 0) {
        std::printf("tvpgl_simd_compare: ALL PASS (bit-exact scalar==simd)\n");
        return 0;
    }
    std::printf("tvpgl_simd_compare: %d mismatches found\n", g_failures);
    return 1;
}