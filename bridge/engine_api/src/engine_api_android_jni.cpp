/*
 * KrKr2 Engine - Android JNI glue for the engine_api shared library.
 *
 * Bridges the ANativeWindow (SurfaceTexture) from the Flutter plugin's
 * Kotlin code into the engine runtime, which renders into it via an
 * EGL WindowSurface (ANGLE) and eglSwapBuffers.
 *
 * Symbols provided:
 *   - krkr_GetNativeWindow() / krkr_GetSurfaceDimensions(): consumed by
 *     engine_api.cpp (Android) for auto-attaching the Surface render target.
 *   - JNI entry points called by FlutterEngineBridgePlugin (Kotlin):
 *     nativeSetSurface(window, width, height) / nativeDetachSurface().
 *
 * Thread-safety: the stored window is guarded by a mutex. krkr_GetNativeWindow
 * returns an ADDITIONAL reference that the caller must release with
 * ANativeWindow_release() — matching the contract in engine_api.cpp.
 */

#if defined(__ANDROID__)

#include <jni.h>

#include <android/native_window.h>
#include <android/native_window_jni.h>

#include <mutex>

namespace {

std::mutex g_window_mutex;
ANativeWindow* g_native_window = nullptr;  // retained reference
uint32_t g_surface_width = 0;
uint32_t g_surface_height = 0;

}  // namespace

extern "C" {

ANativeWindow* krkr_GetNativeWindow() {
  std::lock_guard<std::mutex> lock(g_window_mutex);
  if (!g_native_window) {
    return nullptr;
  }
  ANativeWindow_acquire(g_native_window);
  return g_native_window;
}

void krkr_GetSurfaceDimensions(uint32_t* out_width, uint32_t* out_height) {
  std::lock_guard<std::mutex> lock(g_window_mutex);
  if (out_width) {
    *out_width = g_surface_width;
  }
  if (out_height) {
    *out_height = g_surface_height;
  }
}

/*
 * Java package: dev.krkr2.flutter_engine_bridge
 * JNI symbol:   Java_dev_krkr2_flutter_1engine_1bridge_FlutterEngineBridgePlugin_nativeSetSurface
 * Pass null surface to detach.
 */
JNIEXPORT void JNICALL
Java_dev_krkr2_flutter_1engine_1bridge_FlutterEngineBridgePlugin_nativeSetSurface(
    JNIEnv* env, jobject /*thiz*/, jobject surface, jint width, jint height) {
  ANativeWindow* window =
      surface != nullptr ? ANativeWindow_fromSurface(env, surface) : nullptr;

  std::lock_guard<std::mutex> lock(g_window_mutex);
  if (g_native_window) {
    ANativeWindow_release(g_native_window);
  }
  g_native_window = window;
  g_surface_width = width > 0 ? static_cast<uint32_t>(width) : 0;
  g_surface_height = height > 0 ? static_cast<uint32_t>(height) : 0;
}

JNIEXPORT void JNICALL
Java_dev_krkr2_flutter_1engine_1bridge_FlutterEngineBridgePlugin_nativeDetachSurface(
    JNIEnv* /*env*/, jobject /*thiz*/) {
  std::lock_guard<std::mutex> lock(g_window_mutex);
  if (g_native_window) {
    ANativeWindow_release(g_native_window);
    g_native_window = nullptr;
  }
  g_surface_width = 0;
  g_surface_height = 0;
}

}  // extern "C"

#endif  // __ANDROID__
