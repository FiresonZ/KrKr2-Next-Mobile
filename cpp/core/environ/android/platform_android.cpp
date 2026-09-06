/**
 * @file platform_android.cpp
 * @brief Android host platform implementation for the KrKr2 engine.
 *
 * KrKr2 的目标平台是 iOS / Android / macOS。Apple 平台实现在 apple/{ios,macos}/
 * platform.mm，Linux 在 stubs/platform_linux.cpp。此前 **Android 一直缺平台实现**
 * （environ/android 目录为空），导致 libengine_api.so 链接时大量 undefined symbol：
 *   TVPDeleteFile / TVPGetAppStoragePath / TVPGetCurrentLanguage / Android_Get*
 * 本文件补齐 Android 所需的平台符号，与上游(reAAAq/KrKr2-Next)的 AndroidUtils.cpp
 * 职责等价，但采用**本项目的自研轻量化实现**（不引入上游 KR2Activity JNI 体系）。
 *
 * 实现策略（与 stubs/platform_linux.cpp 一致）：Android 同为 POSIX/Linux 内核，
 * 文件操作/时钟/内存(/proc)/生命周期等可直接复用 Linux 的通用实现；UI 由 Flutter
 * 接管，MessageBox/IME/SendToOtherApp 等给空实现（如 Linux stub 一样仅打日志）。
 * 存储路径用平台无关的 TVPGetAppPath()（来自 TVPProjectDir，已在 StorageImpl.cpp
 * 定义），因此本文件不依赖 Android applicationContext JNI。
 *
 * 文件体用 `#if defined(__ANDROID__)` 守卫，在 Apple/Linux 上为空翻译单元。
 */

#if defined(__ANDROID__)

#include <spdlog/spdlog.h>

#include <ctype.h>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <ctime>
#include <unistd.h>
#include <sched.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <fcntl.h>

#include "tjsCommHead.h"
#include "tjsString.h"
#include "Platform.h"
#include "SysInitImpl.h"
#include "StorageImpl.h"
#include "StorageIntf.h" // TVPGetAppPath
#include "EventIntf.h"

// ---------------------------------------------------------------------------
// 文件操作
// ---------------------------------------------------------------------------

bool TVPDeleteFile(const std::string &filename) {
    return ::unlink(filename.c_str()) == 0;
}

bool TVPRenameFile(const std::string &from, const std::string &to) {
    return ::rename(from.c_str(), to.c_str()) == 0;
}

bool TVPCopyFile(const std::string &from, const std::string &to) {
    std::ifstream in(from, std::ios::binary);
    if(!in)
        return false;
    std::ofstream out(to, std::ios::binary | std::ios::trunc);
    if(!out)
        return false;
    out << in.rdbuf();
    return out.good();
}

bool TVPCreateFolders(const ttstr &folder) {
    if(folder.IsEmpty())
        return true;
    std::error_code ec;
    std::filesystem::create_directories(folder.AsStdString(), ec);
    return !ec;
}

bool TVPWriteDataToFile(const ttstr &filepath, const void *data,
                        unsigned int len) {
    FILE *handle = fopen(filepath.AsStdString().c_str(), "wb");
    if(handle) {
        bool ret = fwrite(data, 1, len, handle) == len;
        fclose(handle);
        return ret;
    }
    return false;
}

bool TVP_stat(const char *name, tTVP_stat &s) {
    struct stat t{}; // NOLINT
    if(stat(name, &t) != 0) {
        return false;
    }
    s.st_mode = t.st_mode;
    s.st_size = t.st_size;
    // Platform.h 会 #undef st_atime/st_mtime/st_ctime，故只能用 timespec 字段。
    s.st_atime = t.st_atim.tv_sec;
    s.st_mtime = t.st_mtim.tv_sec;
    s.st_ctime = t.st_ctim.tv_sec;
    return true;
}

bool TVP_stat(const tjs_char *name, tTVP_stat &s) {
    return TVP_stat(ttstr{name}.AsStdString().c_str(), s);
}

bool TVP_utime(const char *name, time_t modtime) {
    timeval mt[2] = {};
    mt[0].tv_sec = modtime;
    mt[1].tv_sec = modtime;
    return utimes(name, mt) == 0;
}

// ---------------------------------------------------------------------------
// 路径
// ---------------------------------------------------------------------------

// 平台无关的 app 根路径（来自 TVPProjectDir，见 StorageImpl.cpp）
std::string TVPGetDefaultFileDir() {
    return TVPGetAppPath().AsStdString();
}

std::vector<std::string> TVPGetDriverPath() {
    return {}; // Flutter 接管 UI，无驱动器目录
}

std::vector<std::string> TVPGetAppStoragePath() {
    // 应用可写目录：与 iOS/Linux 一致，落在 TVPGetAppPath()（原生数据/存档根）。
    return {TVPGetAppPath().AsStdString()};
}

// ---------------------------------------------------------------------------
// 时钟 / 内存（/proc，Android 亦存在 procfs）
// ---------------------------------------------------------------------------

tjs_uint32 TVPGetRoughTickCount32() {
    tjs_uint32 uptime = 0;
    timespec on{};
    if(clock_gettime(CLOCK_MONOTONIC, &on) == 0)
        uptime = static_cast<tjs_uint32>(on.tv_sec * 1000 +
                                         on.tv_nsec / 1000000);
    return uptime;
}

static unsigned long _meminfo_value(const char *key) {
    std::ifstream f("/proc/meminfo");
    std::string line, k;
    unsigned long v = 0;
    while(std::getline(f, line)) {
        std::istringstream is(line);
        is >> k >> v;
        if(k == key)
            return v;
    }
    return 0;
}

static tjs_int _proc_self_mem(const char *key) {
    std::ifstream f("/proc/self/status");
    std::string line, k;
    long v = 0, unit = 1;
    while(std::getline(f, line)) {
        std::istringstream is(line);
        is >> k >> v >> unit;
        if(k == key)
            break;
    }
    return static_cast<tjs_int>(v);
}

void TVPGetMemoryInfo(TVPMemoryInfo &m) {
    m.MemTotal = _meminfo_value("MemTotal:");
    m.MemFree = _meminfo_value("MemFree:");
    m.SwapTotal = _meminfo_value("SwapTotal:");
    m.SwapFree = _meminfo_value("SwapFree:");
    m.VirtualTotal = m.MemTotal; // 近似：物理内存总量
    m.VirtualUsed = static_cast<unsigned long>(_proc_self_mem("VmRSS:"));
}

tjs_int TVPGetSelfUsedMemory() { // in MB
    return _proc_self_mem("VmRSS:") / 1024;
}

tjs_int TVPGetSystemFreeMemory() { // in MB
    return static_cast<tjs_int>(_meminfo_value("MemAvailable:") / 1024);
}

// ---------------------------------------------------------------------------
// 应用生命周期
// ---------------------------------------------------------------------------

void TVPForceSwapBuffer() { /* pass */ }

bool TVPCheckStartupPath(const std::string &) { return true; }

bool TVPCheckStartupArg() { return false; }

void TVPExitApplication(int code) {
    TVPDeliverCompactEvent(TVP_COMPACT_LEVEL_MAX);
    TVPTerminated = true;
    TVPTerminateCode = code;
    if(TVPHostSuppressProcessExit) {
        return;
    }
    exit(code);
}

void TVPRelinquishCPU() { sched_yield(); }

void TVPProcessInputEvents() { /* pass */ }

void TVPControlAdDialog(int, int, int) { /* pass */ }

std::string TVPGetPackageVersionString() { return "android"; }

std::string TVPGetCurrentLanguage() {
    // 本地化按需接入真实系统语言（后续可通过 JNI 读 Locale）。先给默认 en。
    return "en";
}

// ---------------------------------------------------------------------------
// IME / 发送：Flutter 接管 UI，空实现
// ---------------------------------------------------------------------------

void TVPShowIME(int, int, int, int) { /* Flutter handles IME */ }

void TVPHideIME() { /* Flutter handles IME */ }

void TVPSendToOtherApp(const std::string &) { /* pass */ }

// ---------------------------------------------------------------------------
// UI 桩（Flutter 接管 UI，仅打日志）
// ---------------------------------------------------------------------------

extern "C" int TVPShowSimpleMessageBox(const char *pszText, const char *pszTitle,
                                       unsigned int nButton,
                                       const char **btnText) {
    spdlog::warn("[platform_android] TVPShowSimpleMessageBox stub: {} ({})",
                 pszText ? pszText : "", pszTitle ? pszTitle : "");
    (void)nButton;
    (void)btnText;
    return 0;
}

int TVPShowSimpleMessageBox(const ttstr &text, const ttstr &caption,
                            const std::vector<ttstr> &vecButtons) {
    spdlog::warn("[platform_android] TVPShowSimpleMessageBox stub: {} ({}, {} btns)",
                 text.AsStdString(), caption.AsStdString(), vecButtons.size());
    return 0;
}

int TVPShowSimpleMessageBox(const ttstr &text, const ttstr &caption) {
    return TVPShowSimpleMessageBox(text, caption, std::vector<ttstr>{});
}

int TVPShowSimpleMessageBoxYesNo(const ttstr &text, const ttstr &caption) {
    spdlog::warn("[platform_android] TVPShowSimpleMessageBoxYesNo stub");
    return 0;
}

int TVPShowSimpleInputBox(ttstr &text, const ttstr &caption, const ttstr &prompt,
                          const std::vector<ttstr> &vecButtons) {
    spdlog::warn("[platform_android] TVPShowSimpleInputBox stub");
    (void)caption;
    (void)prompt;
    (void)vecButtons;
    text = ttstr();
    return 0;
}

// ---------------------------------------------------------------------------
// Android 特有：系统字体/存储探测（FontImpl 引用）。移动端以系统内置字体回退，
// 空列表即可（FontImpl 安卓分支会继续试 /system/fonts）。
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