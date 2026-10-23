package qntx.shake

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Base64
import android.webkit.WebView
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Channel
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.ByteArrayOutputStream
import kotlin.math.sqrt

@InvokeArg
class WatchArgs {
  lateinit var handler: Channel
}

// The accelerometer needs no manifest permission; the manifest here is empty.
@TauriPlugin
class ShakePlugin(private val activity: Activity) : Plugin(activity), SensorEventListener {
  private var webView: WebView? = null
  private var handler: Channel? = null
  private var lastShakeAt = 0L
  private val sensors: SensorManager by lazy {
    activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
  }

  companion object {
    // In g, the reading over GRAVITY_EARTH: 1 at rest. iOS reads the same
    // number, so a shake is the same shake on both.
    const val SHAKE_G = 2.7f
    const val DEBOUNCE_MS = 500L
  }

  override fun load(webView: WebView) {
    this.webView = webView
  }

  @Command
  fun watch(invoke: Invoke) {
    val args = invoke.parseArgs(WatchArgs::class.java)
    if (sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) == null) {
      invoke.reject("no accelerometer on this device")
      return
    }
    handler = args.handler
    listen()
    invoke.resolve()
  }

  private fun listen() {
    val accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
    sensors.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)
  }

  override fun onResume() {
    if (handler != null) listen()
  }

  override fun onPause() {
    sensors.unregisterListener(this)
  }

  override fun onSensorChanged(event: SensorEvent) {
    val x = event.values[0] / SensorManager.GRAVITY_EARTH
    val y = event.values[1] / SensorManager.GRAVITY_EARTH
    val z = event.values[2] / SensorManager.GRAVITY_EARTH
    val g = sqrt(x * x + y * y + z * z)
    if (g < SHAKE_G) return
    val now = System.currentTimeMillis()
    if (now - lastShakeAt < DEBOUNCE_MS) return
    lastShakeAt = now
    val shaken = JSObject()
    shaken.put("at", now)
    handler?.send(shaken)
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

  @Command
  fun snapshot(invoke: Invoke) {
    val webView = this.webView
    if (webView == null) {
      invoke.reject("the web view is not loaded yet")
      return
    }
    activity.runOnUiThread {
      try {
        val width = webView.width
        val height = webView.height
        if (width == 0 || height == 0) {
          invoke.reject("the web view is ${width}x${height}, nothing to draw")
          return@runOnUiThread
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        webView.draw(Canvas(bitmap))
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
        bitmap.recycle()
        val png = Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
        val result = JSObject()
        result.put("png", "data:image/png;base64,$png")
        result.put("width", width)
        result.put("height", height)
        invoke.resolve(result)
      } catch (e: Exception) {
        invoke.reject("the snapshot failed: ${e.message}", e)
      }
    }
  }
}
