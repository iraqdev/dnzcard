package dnz.dnzteam.kushk

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import dnz.dnzteam.kushk.printer.UniversalPrinterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var printer: UniversalPrinterEngine

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printer = UniversalPrinterEngine(applicationContext) { this }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handlePrinterCall(call, result) }
        IposBuiltInPrinterPlugin.registerWith(flutterEngine, this)
        SenraiseBuiltInPrinterPlugin.registerWith(flutterEngine, this)
        GenericEscPosPrinterPlugin.registerWith(flutterEngine, this)
    }

    private fun handlePrinterCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "detect" -> {
                    ensureBluetoothPermission()
                    runInBackground(result) { printer.detect() }
                }
                "getStatus" -> runInBackground(result) { printer.getStatus() }
                "listDevices" -> {
                    ensureBluetoothPermission()
                    runInBackground(result) { printer.listDevices() }
                }
                "setDriver" -> {
                    val values = arguments(call)
                    val driver = values["driver"] as? String ?: values["name"] as? String
                    if (driver.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "driver is required", null)
                    } else {
                        ensureBluetoothPermission()
                        runInBackground(result) { printer.setDriver(driver, values) }
                    }
                }
                "setPaperSize" -> {
                    val mm = (arguments(call)["mm"] as? Number)?.toInt() ?: 58
                    runInBackground(result) { printer.setPaperSizeMm(mm) }
                }
                "getPaperSize" -> runInBackground(result) { printer.getPaperSize() }
                "printText" -> runPrint(result) { printer.printText(text(call)) }
                "printReceipt" -> {
                    val values = arguments(call)
                    val image = asByteArray(values["image"])
                    runPrint(result) { printer.printReceipt(text(call), image) }
                }
                "printCard" -> {
                    val values = arguments(call)
                    runPrint(result) {
                        printer.printCard(
                            values["title"] as? String ?: "",
                            values["body"] as? String
                                ?: values["text"] as? String
                                ?: ""
                        )
                    }
                }
                "testPrint" -> runPrint(result) { printer.testPrint() }
                "openDrawer" -> runPrint(result) { printer.openDrawer() }
                "cut" -> runPrint(result) { printer.cut() }
                "feed" -> runPrint(result) {
                    printer.feed((arguments(call)["lines"] as? Number)?.toInt() ?: 1)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("PRINTER_ERROR", error.message ?: "Printer operation failed", null)
        }
    }

    private fun ensureBluetoothPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val needed = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
            != PackageManager.PERMISSION_GRANTED
        ) {
            needed += Manifest.permission.BLUETOOTH_CONNECT
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN)
            != PackageManager.PERMISSION_GRANTED
        ) {
            needed += Manifest.permission.BLUETOOTH_SCAN
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), REQ_BT)
        }
    }

    private fun text(call: MethodCall): String =
        (call.arguments as? String) ?: (arguments(call)["text"] as? String) ?: ""

    private fun arguments(call: MethodCall): Map<String, Any?> =
        (call.arguments as? Map<*, *>)?.entries
            ?.associate { (key, value) -> key.toString() to value }
            ?: emptyMap()

    private fun asByteArray(value: Any?): ByteArray? = when (value) {
        is ByteArray -> value
        is java.nio.ByteBuffer -> {
            val copy = ByteArray(value.remaining())
            value.duplicate().get(copy)
            copy
        }
        is List<*> -> value.mapNotNull { (it as? Number)?.toByte() }.toByteArray()
        else -> null
    }

    private fun success(value: Boolean) =
        mapOf("success" to value, "status" to printer.getStatus())

    private fun runPrint(result: MethodChannel.Result, operation: () -> Boolean) {
        if (printer.getStatus()["driver"] == "ANDROID_PRINT") {
            result.success(success(operation()))
        } else {
            runInBackgroundBool(result, operation)
        }
    }

    private fun runInBackgroundBool(
        result: MethodChannel.Result,
        operation: () -> Boolean
    ) {
        Thread {
            val value = try {
                operation()
            } catch (_: Exception) {
                false
            }
            runOnUiThread { result.success(success(value)) }
        }.start()
    }

    private fun runInBackground(
        result: MethodChannel.Result,
        operation: () -> Any?
    ) {
        Thread {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "PRINTER_ERROR",
                        error.message ?: "Printer operation failed",
                        null
                    )
                }
            }
        }.start()
    }

    private companion object {
        const val CHANNEL = "kushk/printer"
        const val REQ_BT = 2401
    }
}
