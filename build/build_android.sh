#!/usr/bin/env bash
#
# build_android.sh — One-step build script for krkr2 Android (Flutter)
#
# Usage:
#   ./build_android.sh [debug|release]
#
# Output: Flutter Android APK (debug/release)
#
# Prerequisites:
#   - Android NDK installed, ANDROID_NDK_HOME set (or ANDROID_HOME/ndk/<ver>)
#   - Flutter SDK (found via PATH or .devtools/flutter)
#   - vcpkg (auto-setup in .devtools/vcpkg on first run)
#
# This script will:
#   1. Build the C++ engine shared library (libengine_api.so) via CMake/Ninja
#   2. Copy the .so into the Flutter app's jniLibs/arm64-v8a/
#   3. Build the Flutter Android application (APK)
#

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_TYPE="${1:-debug}"
BUILD_TYPE_LOWER="$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')"

if [[ "$BUILD_TYPE_LOWER" != "debug" && "$BUILD_TYPE_LOWER" != "release" ]]; then
    echo "Error: Invalid build type '$BUILD_TYPE'. Use 'debug' or 'release'."
    exit 1
fi

# Capitalize for CMake preset names
BUILD_TYPE_CAP="$(echo "${BUILD_TYPE_LOWER:0:1}" | tr '[:lower:]' '[:upper:]')${BUILD_TYPE_LOWER:1}"

CMAKE_CONFIG_PRESET="Android ${BUILD_TYPE_CAP} Config"
CMAKE_BUILD_PRESET="Android ${BUILD_TYPE_CAP} Build"
CMAKE_BUILD_DIR="$PROJECT_ROOT/out/android/$BUILD_TYPE_LOWER"

# ABI — only arm64 is built for now (matches arm64-ios).
ANDROID_ABI="arm64-v8a"

# --- Locate Android NDK -----------------------------------------------------
if [[ -n "${ANDROID_NDK_HOME:-}" && -d "$ANDROID_NDK_HOME" ]]; then
    NDK_ROOT="$ANDROID_NDK_HOME"
elif [[ -n "${ANDROID_NDK_ROOT:-}" && -d "$ANDROID_NDK_ROOT" ]]; then
    NDK_ROOT="$ANDROID_NDK_ROOT"
elif [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME/ndk" ]]; then
    # Pick the newest installed NDK version
    NDK_ROOT="$(ls -1d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -n 1 || true)"
    if [[ -z "$NDK_ROOT" ]]; then
        echo "Error: No NDK found under \$ANDROID_HOME/ndk. Install via Android Studio SDK Manager."
        exit 1
    fi
else
    echo "Error: Android NDK not found."
    echo "  Set ANDROID_NDK_HOME (or ANDROID_HOME with an ndk/ subdirectory)."
    echo "  Example: export ANDROID_NDK_HOME=\"\$ANDROID_HOME/ndk/27.0.12077973\""
    exit 1
fi

export ANDROID_NDK_HOME="$NDK_ROOT"
echo "[INFO] Using Android NDK: $NDK_ROOT"

# --- Locate Flutter SDK -----------------------------------------------------
if [[ -d "$PROJECT_ROOT/.devtools/flutter" ]]; then
    FLUTTER_SDK="$PROJECT_ROOT/.devtools/flutter"
    FLUTTER_BIN="$FLUTTER_SDK/bin/flutter"
elif command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
    if command -v realpath >/dev/null 2>&1; then
        RESOLVED_BIN="$(realpath "$FLUTTER_BIN")"
    elif command -v python3 >/dev/null 2>&1; then
        RESOLVED_BIN="$(python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$FLUTTER_BIN")"
    else
        RESOLVED_BIN="$FLUTTER_BIN"
    fi
    FLUTTER_SDK="$(dirname "$(dirname "$RESOLVED_BIN")")"
else
    echo "Error: Flutter SDK not found in .devtools and not in PATH."
    exit 1
fi

FLUTTER_APP_DIR="$PROJECT_ROOT/apps/flutter_app"

# --- Locate vcpkg -----------------------------------------------------------
if [[ -d "$PROJECT_ROOT/.devtools/vcpkg/.git" ]]; then
    VCPKG_ROOT="$PROJECT_ROOT/.devtools/vcpkg"
elif [[ -n "${VCPKG_ROOT:-}" && -f "$VCPKG_ROOT/.vcpkg-root" ]]; then
    : # Keep the environment VCPKG_ROOT if set
else
    echo "[INFO] vcpkg not found. Automatically setting up vcpkg in .devtools/vcpkg..."
    mkdir -p "$PROJECT_ROOT/.devtools"
    git clone https://github.com/microsoft/vcpkg.git "$PROJECT_ROOT/.devtools/vcpkg"
    (cd "$PROJECT_ROOT/.devtools/vcpkg" && ./bootstrap-vcpkg.sh -disableMetrics)
    VCPKG_ROOT="$PROJECT_ROOT/.devtools/vcpkg"
fi

PARALLEL_JOBS="${JOBS:-8}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================
# Helper functions
# ============================================================
log_step() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "'$1' is not installed or not in PATH."
        exit 1
    fi
}

# ============================================================
# Pre-flight checks
# ============================================================
log_step "Pre-flight checks"

check_command cmake
check_command ninja

if [[ ! -x "$FLUTTER_BIN" ]]; then
    log_error "Flutter SDK not found at: $FLUTTER_SDK"
    log_info "Expected path: $FLUTTER_BIN"
    exit 1
fi

if [[ ! -d "$VCPKG_ROOT" ]]; then
    log_error "vcpkg not found at: $VCPKG_ROOT"
    exit 1
fi

if [[ ! -d "$FLUTTER_APP_DIR/android" ]]; then
    log_error "Flutter Android shell missing: $FLUTTER_APP_DIR/android"
    log_info "Regenerate it with:"
    echo "  cd \"$FLUTTER_APP_DIR\" && flutter create --platforms=android ."
    exit 1
fi

log_info "Build type:    $BUILD_TYPE_CAP"
log_info "Project root:  $PROJECT_ROOT"
log_info "CMake preset:  $CMAKE_BUILD_PRESET"
log_info "Flutter SDK:   $FLUTTER_SDK"
log_info "Android NDK:   $NDK_ROOT"
log_info "Parallel jobs: $PARALLEL_JOBS"

# ============================================================
# Step 1: Build C++ engine (shared library for Android)
# ============================================================
log_step "Step 1/3: Building C++ engine (libengine_api.so)"

export VCPKG_ROOT

# 渲染诊断探针 + 日志级别：由 workflow / 环境传入（ENABLE_RENDER_PROBE、
# KRKR_LOG_LEVEL），透传为 CMake 缓存变量。为空表示沿用 CMake 默认
#（探针 OFF；日志级别按构建类型自动）。
RENDER_PROBE_OPT=""
if [[ -n "${ENABLE_RENDER_PROBE:-}" ]]; then
    # workflow 布尔输入恒为小写 true/false，直接匹配即可
    case "$ENABLE_RENDER_PROBE" in
        true|on|1) RENDER_PROBE_OPT="-DENABLE_RENDER_PROBE=ON" ;;
    esac
fi
LOG_LEVEL_OPT=""
if [[ -n "${KRKR_LOG_LEVEL:-}" && "${KRKR_LOG_LEVEL}" != "auto" ]]; then
    LOG_LEVEL_OPT="-DKRKR_LOG_LEVEL=$KRKR_LOG_LEVEL"
fi

# Configure（首次构建 或 显式切换了探针/日志开关 时执行；
# 开关变更即使已有 build.ninja 也会强制重新 configure 以生效）
NEED_CFG=0
if [[ ! -f "$CMAKE_BUILD_DIR/build.ninja" ]]; then
    NEED_CFG=1
elif [[ -n "${RENDER_PROBE_OPT}${LOG_LEVEL_OPT}" ]]; then
    NEED_CFG=1
fi

if [[ "$NEED_CFG" == 1 ]]; then
    log_info "Running CMake configure... (probe='${ENABLE_RENDER_PROBE:-<default>}', log_level='${KRKR_LOG_LEVEL:-<auto>}')"
    cmake --preset "$CMAKE_CONFIG_PRESET" ${RENDER_PROBE_OPT} ${LOG_LEVEL_OPT}
else
    log_info "Build directory already configured, skipping configure."
fi

# Build
log_info "Building C++ engine with $PARALLEL_JOBS parallel jobs..."
cmake --build --preset "$CMAKE_BUILD_PRESET" -- -j"$PARALLEL_JOBS"

# Verify the shared library was built
ENGINE_LIB="$CMAKE_BUILD_DIR/bridge/engine_api/libengine_api.so"
if [[ ! -f "$ENGINE_LIB" ]]; then
    log_error "Engine shared library not found at: $ENGINE_LIB"
    log_error "C++ engine build may have failed."
    exit 1
fi

log_info "Engine shared library built: $ENGINE_LIB"

# ============================================================
# Step 2: Copy .so into the Flutter app's jniLibs
# ============================================================
log_step "Step 2/3: Copying libengine_api.so to jniLibs"

JNI_LIBS_DIR="$FLUTTER_APP_DIR/android/app/src/main/jniLibs/$ANDROID_ABI"
mkdir -p "$JNI_LIBS_DIR"
cp -f "$ENGINE_LIB" "$JNI_LIBS_DIR/libengine_api.so"
log_info "Copied -> $JNI_LIBS_DIR/libengine_api.so"

# ============================================================
# Step 3: Build Flutter Android app
# ============================================================
log_step "Step 3/3: Building Flutter Android app"

export PATH="$FLUTTER_SDK/bin:$PATH"

log_info "Running flutter pub get..."
(cd "$FLUTTER_APP_DIR" && "$FLUTTER_BIN" pub get)

FLUTTER_BUILD_MODE="$BUILD_TYPE_LOWER"
log_info "Building Flutter Android app ($FLUTTER_BUILD_MODE)..."

# 版本号：优先 RELEASE_VERSION（工作流填写的发布版本号，X.Y.Z）；未填则回退读取
# pubspec.yaml 的 version 字段。versionCode 要求整数，取 major*10000+minor*100+patch；
# 版本号经 --dart-define=APP_VERSION 注入，供 settings 页展示实际版本号。
VERSION_ARGS=()
APP_VERSION="${RELEASE_VERSION:-}"
if [[ -z "$APP_VERSION" ]]; then
    APP_VERSION="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\)[+0-9]*[[:space:]]*$/\1/p' \
        "$FLUTTER_APP_DIR/pubspec.yaml" | head -n1)"
fi
if [[ -n "$APP_VERSION" ]]; then
    IFS=. read -r v_major v_minor v_patch <<< "$APP_VERSION"
    v_major=${v_major:-0}; v_minor=${v_minor:-0}; v_patch=${v_patch:-0}
    BUILDNUM=$(( v_major*10000 + v_minor*100 + v_patch ))
    VERSION_ARGS=(--build-name="$APP_VERSION" --build-number="$BUILDNUM" \
        --dart-define=APP_VERSION="$APP_VERSION")
    log_info "App version: $APP_VERSION (build $BUILDNUM)"
fi

if [[ "$FLUTTER_BUILD_MODE" == "release" ]]; then
    (cd "$FLUTTER_APP_DIR" && "$FLUTTER_BIN" build apk --release "${VERSION_ARGS[@]}")
else
    (cd "$FLUTTER_APP_DIR" && "$FLUTTER_BIN" build apk --debug "${VERSION_ARGS[@]}")
fi

# ============================================================
# Done
# ============================================================
log_step "Build complete!"

log_info "Engine shared library: $JNI_LIBS_DIR/libengine_api.so"
log_info "Flutter Android APK output: $FLUTTER_APP_DIR/build/app/outputs/flutter-apk/"
echo ""
log_info "To deploy to a device:"
echo "  cd \"$FLUTTER_APP_DIR\" && flutter run -d <device_id>"
echo ""
