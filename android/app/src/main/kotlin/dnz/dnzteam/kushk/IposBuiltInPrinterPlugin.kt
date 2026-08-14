package dnz.dnzteam.kushk

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.iposprinter.iposprinterservice.IPosPrinterCallback
import com.iposprinter.iposprinterservice.IPosPrinterService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class IposBuiltInPrinterPlugin private constructor(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private var service: IPosPrinterService? = null
    private var connection: ServiceConnection? = null

    companion object {
        private const val TAG = "IposBuiltInPrinter"
        private const val CHANNEL = "kushk/ipos_built_in_printer"
        private const val IPOS_PACKAGE = "com.iposprinter.iposprinterservice"
        private const val IPOS_ACTION = "com.iposprinter.iposprinterservice.IPosPrintService"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val plugin = IposBuiltInPrinterPlugin(context.applicationContext)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(plugin)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(isServiceInstalled() || isPackageInstalled())
            }

            "probeConnect" -> {
                Thread {
                    try {
                        bindServiceSync()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "probeConnect failed", e)
                        result.success(false)
                    } finally {
                        unbind()
                    }
                }.start()
            }

            "getDiagnostics" -> {
                val canBind = try {
                    bindServiceSync()
                    true
                } catch (e: Exception) {
                    false
                } finally {
                    unbind()
                }
                result.success(
                    mapOf(
                        "packageInstalled" to isPackageInstalled(),
                        "serviceQueryable" to isServiceInstalled(),
                        "canBind" to canBind,
                        "androidSdk" to Build.VERSION.SDK_INT,
                    ),
                )
            }

            "printTestText" -> {
                val text = call.argument<String>("text") ?: "اختبار الطابعة"
                Thread {
                    try {
                        bindAndPrintText(text)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "printTestText failed", e)
                        result.error("PRINT_FAILED", e.message ?: e.javaClass.simpleName, null)
                    } finally {
                        unbind()
                    }
                }.start()
            }

            "printPngPages" -> {
                val pages = decodePages(call.argument<Any>("pages"))
                val maxWidth = call.argument<Int>("maxWidthPx") ?: 384
                if (pages.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "pages required", null)
                    return
                }
                Thread {
                    try {
                        bindAndPrint(pages, maxWidth)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "printPngPages failed", e)
                        result.error("PRINT_FAILED", e.message ?: e.javaClass.simpleName, null)
                    } finally {
                        unbind()
                    }
                }.start()
            }

            else -> result.notImplemented()
        }
    }

    private fun isPackageInstalled(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    IPOS_PACKAGE,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(IPOS_PACKAGE, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun isServiceInstalled(): Boolean {
        val intent = Intent().apply {
            setPackage(IPOS_PACKAGE)
            action = IPOS_ACTION
        }
        return context.packageManager.queryIntentServices(intent, 0).isNotEmpty()
    }

    private fun decodePages(raw: Any?): List<ByteArray> {
        if (raw !is List<*>) return emptyList()
        return raw.mapNotNull { item ->
            when (item) {
                is ByteArray -> item
                is Array<*> -> item.filterIsInstance<Byte>().toByteArray()
                else -> null
            }
        }
    }

    private fun bindServiceSync() {
        if (service != null) return

        val latch = CountDownLatch(1)
        val bindError = AtomicReference<Exception?>(null)

        connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                try {
                    service = IPosPrinterService.Stub.asInterface(binder)
                } catch (e: Exception) {
                    bindError.set(e)
                }
                latch.countDown()
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                service = null
            }
        }

        val intent = Intent().apply {
            setPackage(IPOS_PACKAGE)
            action = IPOS_ACTION
        }
        val bound = context.bindService(intent, connection!!, Context.BIND_AUTO_CREATE)
        if (!bound) {
            throw IllegalStateException("IPOS_BIND_FAILED")
        }

        if (!latch.await(10, TimeUnit.SECONDS)) {
            throw IllegalStateException("IPOS_BIND_TIMEOUT")
        }
        bindError.get()?.let { throw it }
        if (service == null) {
            throw IllegalStateException("IPOS_SERVICE_NULL")
        }
    }

    private fun bindAndPrintText(text: String) {
        bindServiceSync()
        val printer = service ?: throw IllegalStateException("IPOS_SERVICE_NULL")

        runCallback { printer.printerInit(it) }
        runCallback { printer.PrintSpecFormatText("$text\n", "", 24, 1, it) }
        runCallback { printer.printBlankLines(2, 24, it) }
        runCallback { printer.printerPerformPrint(4, it) }
    }

    private fun bindAndPrint(pages: List<ByteArray>, maxWidth: Int) {
        bindServiceSync()
        val printer = service ?: throw IllegalStateException("IPOS_SERVICE_NULL")

        runCallback { printer.printerInit(it) }

        for (raw in pages) {
            var bitmap = BitmapFactory.decodeByteArray(raw, 0, raw.size)
                ?: throw IllegalStateException("IPOS_BITMAP_DECODE_FAILED")
            val scaled = scaleBitmap(bitmap, maxWidth)
            if (scaled !== bitmap && !bitmap.isRecycled) {
                bitmap.recycle()
            }
            bitmap = scaled
            runCallback { printer.printBitmap(1, 10, bitmap, it) }
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }

        runCallback { printer.printBlankLines(2, 24, it) }
        runCallback { printer.printerPerformPrint(4, it) }
    }

    private fun scaleBitmap(source: Bitmap, maxWidth: Int): Bitmap {
        if (source.width <= maxWidth) return source
        val matrix = Matrix()
        val scale = maxWidth.toFloat() / source.width.toFloat()
        matrix.postScale(scale, scale)
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private fun runCallback(block: (IPosPrinterCallback) -> Unit) {
        val latch = CountDownLatch(1)
        val error = AtomicReference<Exception?>(null)
        val callback = object : IPosPrinterCallback.Stub() {
            override fun onRunResult(isSuccess: Boolean) {
                if (!isSuccess) {
                    error.set(IllegalStateException("IPOS_CALLBACK_FAILED"))
                }
                latch.countDown()
            }

            override fun onReturnString(value: String?) {
                latch.countDown()
            }
        }
        block(callback)
        if (!latch.await(25, TimeUnit.SECONDS)) {
            throw IllegalStateException("IPOS_CALLBACK_TIMEOUT")
        }
        error.get()?.let { throw it }
    }

    private fun unbind() {
        connection?.let {
            runCatching { context.unbindService(it) }
        }
        connection = null
        service = null
    }
}
