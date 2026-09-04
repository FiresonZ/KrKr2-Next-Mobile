/*
 * KrKr2 Engine Bridge — Android plugin.
 *
 * Bridges the KrKr2 C++ engine to Flutter Android:
 *   - getPlatformVersion
 *   - Legacy RGBA texture upload (FlutterTexture + ByteBuffer) used by the
 *     engineReadFrameRgba fallback path.
 *   - SurfaceTexture zero-copy rendering (GPU path): the Kotlin side creates
 *     a SurfaceTexture backed Surface and hands the ANativeWindow to the
 *     engine via JNI (nativeSetSurface / nativeDetachSurface). The engine
 *     renders with EGL (ANGLE) and eglSwapBuffers delivers frames directly
 *     to Flutter, with no CPU readback.
 *
 * The native library (libengine_api.so) is built by build/build_android.sh
 * and copied into the app's jniLibs/arm64-v8a/ — it contains both the engine
 * runtime and the JNI glue (engine_api_android_jni.cpp).
 */

package dev.krkr2.flutter_engine_bridge

import android.graphics.SurfaceTexture
import android.os.Build
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.util.concurrent.locks.ReentrantLock

/** FlutterTexture implementation backed by an RGBA ByteBuffer (readback path). */
private class RgbaTexture : io.flutter.view.TextureRegistry.TextureEntry {
  private val lock = ReentrantLock()
  private var pixels: ByteBuffer? = null
  private var width: Int = 0
  private var height: Int = 0

  override fun copyPixelBuffer(): ByteBuffer? {
    lock.lock()
    try {
      val p = pixels ?: return null
      return p.duplicate()
    } finally {
      lock.unlock()
    }
  }

  /** Copies [data] into a tightly packed RGBA buffer (rowBytes == width * 4). */
  fun updateFrame(data: ByteArray, w: Int, h: Int, rowBytes: Int): Boolean {
    if (w <= 0 || h <= 0 || rowBytes < w * 4 || data.size < rowBytes * h) {
      return false
    }
    lock.lock()
    try {
      if (pixels == null || width != w || height != h) {
        pixels = ByteBuffer.allocateDirect(w * h * 4)
        width = w
        height = h
      }
      val buffer = pixels!!
      buffer.clear()
      val tightRow = w * 4
      if (rowBytes == tightRow) {
        buffer.put(data, 0, tightRow * h)
      } else {
        // Repack row by row to drop any padding (stride may exceed width*4).
        for (y in 0 until h) {
          buffer.put(data, y * rowBytes, tightRow)
        }
      }
      buffer.rewind()
      return true
    } finally {
      lock.unlock()
    }
  }
}

class FlutterEngineBridgePlugin : FlutterPlugin, MethodCallHandler {
  private var textureRegistry: TextureRegistry? = null
  private val rgbaTextures = mutableMapOf<Long, RgbaTexture>()
  private val surfaceTextures = mutableMapOf<Long, TextureRegistry.SurfaceTextureEntry>()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    textureRegistry = flutterPluginBinding.textureRegistry
    val channel = MethodChannel(
      flutterPluginBinding.binaryMessenger,
      "flutter_engine_bridge",
    )
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    textureRegistry = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> result("Android ${Build.VERSION.RELEASE}")

      // --- Legacy RGBA texture (readback fallback) ---
      "createTexture" -> {
        val texture = RgbaTexture()
        val textureId = requireTextureRegistry().register(texture)
        rgbaTextures[textureId] = texture
        result(textureId)
      }

      "updateTextureRgba" -> {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val rgba = call.argument<ByteArray>("rgba")
        val width = call.argument<Number>("width")?.toInt()
        val height = call.argument<Number>("height")?.toInt()
        val rowBytes = call.argument<Number>("rowBytes")?.toInt()
        val texture = textureId?.let { rgbaTextures[it] }
        if (textureId == null || rgba == null || width == null || height == null ||
            rowBytes == null || texture == null
        ) {
          result.error("invalid_args", "updateTextureRgba requires textureId/rgba/width/height/rowBytes", null)
          return
        }
        if (!texture.updateFrame(rgba, width, height, rowBytes)) {
          result.error("texture_update_failed", "Failed to update texture frame", null)
          return
        }
        requireTextureRegistry().textureFrameAvailable(textureId)
        result(null)
      }

      "disposeTexture" -> {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val texture = textureId?.let { rgbaTextures.remove(it) }
        if (texture != null) {
          requireTextureRegistry().unregisterTexture(textureId)
        }
        result(null)
      }

      // --- SurfaceTexture zero-copy (GPU path) ---
      "createSurfaceTexture" -> {
        val width = call.argument<Number>("width")?.toInt()
        val height = call.argument<Number>("height")?.toInt()
        if (width == null || height == null || width <= 0 || height <= 0) {
          result.error("invalid_args", "createSurfaceTexture requires width/height > 0", null)
          return
        }
        val surfaceTexture = SurfaceTexture(0)
        surfaceTexture.setDefaultBufferSize(width, height)
        val entry = requireTextureRegistry().createSurfaceTexture(surfaceTexture)
        surfaceTextures[entry.id()] = entry
        nativeSetSurface(entry.surface(), width, height)
        result(
          mapOf(
            "textureId" to entry.id(),
            "width" to width,
            "height" to height,
          ),
        )
      }

      "resizeSurfaceTexture" -> {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val width = call.argument<Number>("width")?.toInt()
        val height = call.argument<Number>("height")?.toInt()
        val entry = textureId?.let { surfaceTextures[it] }
        if (entry == null || width == null || height == null || width <= 0 || height <= 0) {
          result.error("invalid_args", "resizeSurfaceTexture requires existing textureId and width/height > 0", null)
          return
        }
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        nativeSetSurface(entry.surface(), width, height)
        result(
          mapOf(
            "textureId" to entry.id(),
            "width" to width,
            "height" to height,
          ),
        )
      }

      "disposeSurfaceTexture" -> {
        val textureId = call.argument<Number>("textureId")?.toLong()
        val entry = textureId?.let { surfaceTextures.remove(it) }
        if (entry != null) {
          nativeDetachSurface()
          entry.release()
        }
        result(null)
      }

      "notifyFrameAvailable" -> {
        // No-op on Android: SurfaceTexture buffers are delivered to Flutter
        // automatically by updateTexImage on the raster thread.
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
