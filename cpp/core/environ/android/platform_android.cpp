/**
 * @file platform_android.cpp
 * @brief Android 平台实现的补充项。
 *
 * 说明：Android NDK 的 clang 在编译时**同时定义 `__linux__` 与 `__ANDROID__`**，
 * 因此 `stubs/platform_linux.cpp`（守卫 `#if defined(__linux__)`）在 Android 上也会
 * 全量编译，已经提供了绝大多数通用的平台函数（TVP_stat/TVP_utime/TVPCreateFolders/
 * TVPWriteDataToFile/TVPGetMemoryInfo/TVPGetRoughTickCount32/TVPShow* /文件操作/
 * 内存/时钟/生命周期/UI 桩等）。
 *
 * 本文件只补 platform_linux.cpp 未覆盖、且 Android 引擎确实需要/引用的**缺失项**：
 *   - TVPDeleteFile / TVPGetAppStoragePath（Platform.h 声明，linux stub 无定义）
 *   - TVPGetCurrentLanguage（EngineBootstrap.cpp extern 引用）
 *   - Android_GetExternalStoragePath / Android_GetInternalStoragePath /
 *     Android_GetApkStoragePath（FontImpl.cpp 在 __ANDROID__ 下引用）
 *
 * 存储路径用平台无关的 TVPGetAppPath()（来自 TVPProjectDir，见 StorageImpl.cpp），
 * 因此不依赖 Android applicationContext JNI。文件体用 `#if defined(__ANDROID__)`
 * 守卫，Apple/Linux 上为空翻译单元。
 */

#if defined(__ANDROID__)

#include <stdint.h>
#include <string>
#include <vector>
#include <unistd.h>

#include "tjsCommHead.h"
#include "tjsString.h"
#include "Platform.h"
#include "StorageIntf.h" // TVPGetAppPath

// ---------------------------------------------------------------------------
// 文件操作
// ---------------------------------------------------------------------------

bool TVPDeleteFile(const std::string &filename) {
    return ::unlink(filename.c_str()) == 0;
}

// ---------------------------------------------------------------------------
// 路径
// ---------------------------------------------------------------------------

std::vector<std::string> TVPGetAppStoragePath() {
    // 应用可写目录：与 iOS/Linux 一致，落在 TVPGetAppPath()（原生数据/存档根）。
    return {TVPGetAppPath().AsStdString()};
}

// ---------------------------------------------------------------------------
// 语言 / 未实现项（Flutter 接管 UI）
// ---------------------------------------------------------------------------

std::string TVPGetCurrentLanguage() {
    // 本地化按需接入真实系统语言（后续可通过 JNI 读 Locale）。先给默认 en。
    return "en";
}

// ---------------------------------------------------------------------------
// Android 特有：系统字体/存储探测（FontImpl 引用）。移动端以系统内置字体回退，
// 空列表/空串即可（FontImpl 安卓分支会继续试 /system/fonts）。
// ---------------------------------------------------------------------------

std::vector<ttstr> Android_GetExternalStoragePath() {
    return {};
}

ttstr Android_GetInternalStoragePath() {
    return ttstr();
}

ttstr Android_GetApkStoragePath() {
    return ttstr();
}

#endif // defined(__ANDROID__)