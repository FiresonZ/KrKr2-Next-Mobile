/**
 * @file platform_linux.cpp
 * @brief Linux host platform implementation for the KrKr2 engine.
 *
 * KrKr2 的主要目标平台是 iOS / Android / macOS（Apple 实现在 apple/{ios,macos}/
 * platform.mm）。Linux 仅作为 CI 宿主做引擎核心验证，且 Linux 从未有过平台层——
 * 此前这些平台函数在 Linux 上没有任何定义，导致 libengine_api.so / tools/xp3 链接失败
 * （undefined reference）。
 *
 * 本文件为 Linux 提供这些平台函数的实现：
 *  - 文件操作（TVP_stat/TVP_utime/TVPCreateFolders/TVPWriteDataToFile）
 *  - 时钟（TVPGetRoughTickCount32）
 *  - 内存信息（用 /proc 解析）
 *  - 应用生命周期（TVPExitApplication 等）
 *  - UI 桩（无头环境，TVPShow* 仅打日志并返回默认值）
 *
 * 文件体用 `#if defined(__linux__)` 守卫，在 Apple/Android 上为等价空翻译单元，
 * 不会与各平台的原生实现产生重复符号。
 */

#if defined(__linux__)

#include <spdlog/spdlog.h>

#include <ctype.h>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <filesystem>
#include <cstdlib>
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

// ---------------------------------------------------------------------------
// 文件操作
// ---------------------------------------------------------------------------

bool TVPCreateFolders(const ttstr &folder);

static bool _TVPCreateFolders(const ttstr &folder) {
    if(folder.IsEmpty())
        return true;

    if(TVPCheckExistentLocalFolder(folder))
        return true; // already created

    const tjs_char *p = folder.c_str();
    tjs_int i = folder.GetLen() - 1;

    if(p[i] == TJS_W(':'))
        return true;

    while(i >= 0 && (p[i] == TJS_W('/') || p[i] == TJS_W('\\')))
        i--;

    if(i >= 0 && p[i] == TJS_W(':'))
        return true;

    for(; i >= 0; i--) {
        if(p[i] == TJS_W(':') || p[i] == TJS_W('/') || p[i] == TJS_W('\\'))
            break;
    }

    ttstr parent(p, i + 1);
    if(!TVPCreateFolders(parent))
        return false;

    return !std::filesystem::create_directory(folder.AsStdString().c_str());
}

bool TVPCreateFolders(const ttstr &folder) {
    if(folder.IsEmpty())
        return true;

    const tjs_char *p = folder.c_str();
    tjs_int i = folder.GetLen() - 1;

    if(p[i] == TJS_W(':'))
        return true;

    if(p[i] == TJS_W('/') || p[i] == TJS_W('\\'))
        i--;

    return _TVPCreateFolders(ttstr(p, i + 1));
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
    // Platform.h 会 #undef st_atime/st_mtime/st_ctime，故 Linux 上只能用
    // st_atim/st_mtim/st_ctim（timespec）字段。
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
// 时钟
// ---------------------------------------------------------------------------

tjs_uint32 TVPGetRoughTickCount32() {
    tjs_uint32 uptime = 0;
    timespec on{};
    if(clock_gettime(CLOCK_MONOTONIC, &on) == 0)
        uptime = static_cast<tjs_uint32>(on.tv_sec * 1000 +
                                         on.tv_nsec / 1000000);
    return uptime;
}

// ---------------------------------------------------------------------------
// 内存信息（/proc）
// ---------------------------------------------------------------------------

static unsigned long _meminfo_value(const char *key) {
    std::ifstream f("/proc/meminfo");
    std::string line, k;
    unsigned long v = 0;
    while(std::getline(f, line)) {
        std::istringstream is(line);
        is >> k >> v; // 值单位为 kB
        if(k == key)
            return v;
    }
    return 0;
}

// /proc/self/status 中的 VmRSS/VmSize（单位 kB）
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

std::string TVPGetPackageVersionString() { return "linux"; }

// ---------------------------------------------------------------------------
// UI 桩（无头 CI 环境，仅打日志）
// ---------------------------------------------------------------------------

extern "C" int TVPShowSimpleMessageBox(const char *pszText, const char *pszTitle,
                                       unsigned int nButton,
                                       const char **btnText) {
    spdlog::warn("[platform_linux] TVPShowSimpleMessageBox stub: {} ({})", pszText,
                 pszTitle);
    (void)nButton;
    (void)btnText;
    return 0;
}

int TVPShowSimpleMessageBox(const ttstr &text, const ttstr &caption,
                            const std::vector<ttstr> &vecButtons) {
    spdlog::warn("[platform_linux] TVPShowSimpleMessageBox stub: {} ({}, {} btns)",
                 text.AsStdString(), caption.AsStdString(), vecButtons.size());
    return 0;
}

int TVPShowSimpleInputBox(ttstr &text, const ttstr &caption, const ttstr &prompt,
                          const std::vector<ttstr> &vecButtons) {
    spdlog::warn("[platform_linux] TVPShowSimpleInputBox stub");
    (void)caption;
    (void)prompt;
    (void)vecButtons;
    text = ttstr();
    return 0;
}

#endif // defined(__linux__)