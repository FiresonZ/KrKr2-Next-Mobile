/*
 * KrKr2 Engine Bridge — Android plugin.
 *
 * Bridges the KrKr2 C++ engine to Flutter Android:
 *   - getPlatformVersion
 *   - Surface zero-copy rendering (GPU path): the Kotlin side creates a
 *     Flutter-managed Surface (via TextureRegistry.SurfaceProducer) and hands
 *     the ANativeWindow to the engine via JNI (nativeSetSurface /
 *     nativeDetachSurface). The engine renders with EGL (ANGLE) and
 *     eglSwapBuffers delivers frames directly to Flutter, with no CPU readback.
 *
 * The native library (libengine_api.so) is built by build/build_android.sh
 * and copied into the app's jniLibs/arm64-v8a/ — it contains both the engine
 * runtime and the JNI glue (engine_api_android_jni.cpp).
 *
 * NOTE: the legacy CPU readback path (createTexture / updateTextureRgba /
 * disposeTexture / notifyFrameAvailable) relied on the
 * TextureRegistry.TextureEntry.copyPixelBuffer() API, which was removed from
 * the Flutter Android embedding. Those MethodChannel methods are still exposed
 * for Dart-side compatibility but return an explicit "not supported on Android"
 * error; the GPU path below is the canonical way to get frames from the engine.
 */

package dev.krkr2.flutter_engine_bridge

import android.os.Build
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

class FlutterEngineBridgePlugin : FlutterPlugin, MethodCallHandler {
  private var textureRegistry: TextureRegistry? = null
  private val surfaceProducers = mutableMapOf<Long, TextureRegistry.SurfaceProducer>()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    textureRegistry = flutterPluginBinding.textureRegistry
    val channel = MethodChannel(
      flutterPluginBinding.binaryMessenger,
      "flutter_engine_bridge",
    )
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    // Release any surfaces still owned by this plugin before detaching.
    for ((_, producer) in surfaceProducers) {
      producer.release()
    }
    surfaceProducers.clear()
    nativeDetachSurface()
    textureRegistry = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> result("Android ${Build.VERSION.RELEASE}")

      // --- Legacy RGBA readback (removed from the modern Android embedding) ---
      "createTexture", "updateTextureRgba", "disposeTexture", "notifyFrameAvailable" ->
        result.error(
          "unsupported",
          "CPU readback texture path is not supported on Android in this Flutter " +
            "version; use createSurfaceTexture instead",
          null,
        )

      // --- Surface zero-copy (GPU path) ---
      "createSurfaceTexture" -> {
        val width = call.argument<Number>("width")?.toInt()
        val height = call.argument<Number>("height")?.toInt()
        if (width == null || height == null || width <= 0 || height <= 0) {
          result.error("invalid_args", "createSurfaceTexture requires width/height > 0", null)
          return
        }
        val producer = requireTextureRegistry().createSurfaceProducer()
        producer.setSize(width, height)
        val textureId = producer.id()
        surfaceProducers[textureId] = producer
        val surface = producer.getSurface()
        nativeSetSurface(surface, width, height)
        result(
          mapOf(
            "textureId" to textureId,
            "width" to width,
            "height" to height,
          ),
        )
      }

      "resizeSurfaceTexture" -> {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val width = call.argument<Number>("width")?.toInt()
        val height = call.argument<Number>("height")?.toInt()
        val producer = textureId?.let { surfaceProducers[it] }
        if (producer == null || width == null || height == null || width <= 0 || height <= 0) {
          result.error(
            "invalid_args",
            "resizeSurfaceTexture requires existing textureId and width/height > 0",
            null,
          )
          return
        }
        producer.setSize(width, height)
        val surface = producer.getSurface()
        nativeSetSurface(surface, width, height)
        result(
          mapOf(
            "textureId" to textureId,
            "width" to width,
            "height" to height,
          ),
        )
      }

      "disposeSurfaceTexture" -> {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val producer = textureId?.let { surfaceProducers.remove(it) }
        if (producer != null) {
          nativeDetachSurface()
          producer.release()
        }
        result(null)
      }

      else -> result.notImplemented()
    }
  }

  private fun requireTextureRegistry(): TextureRegistry {
    return textureRegistry
      ?: throw IllegalStateException("flutter_engine_bridge plugin not attached to engine")
  }

  private external fun nativeSetSurface(surface: Surface?, width: Int, height: Int)
  private external fun nativeDetachSurface()

  companion object {
    init {
      System.loadLibrary("engine_api")
    }
  }
}