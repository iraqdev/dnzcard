package dnz.dnzteam.kushk

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import recieptservice.com.recieptservice.PrinterInterface

/**
 * طباعة عبر خدمة Senraise المدمجة (Rovoo H10S وأجهزة recieptservice).
 *
 * ملاحظة مهمة: حزمة senraise_printer على pub.dev لا تستدعي beginWork()/endWork()،
 * وبدونهما لا تُطبع البيانات فعلياً رغم نجاح الاستدعاء — لذلك تم تنفيذ هذا الاتصال
 * المباشر بخدمة AIDL مع تغليف كل عملية طباعة بـ beginWork/endWork.
 */
class SenraiseBuiltInPrinterPlugin private constructor(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private var service: PrinterInterface? = null
    private var connection: ServiceConnection? = null

    companion object {
        private const val TAG = "SenraiseBuiltInPrinter"
        private const val CHANNEL = "kushk/senraise_built_in_printer"
        private const val SERVICE_PACKAGE = "recieptservice.com.recieptservice"
        private const val SERVICE_CLASS = "recieptservice.com.recieptservice.service.PrinterService"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val plugin = SenraiseBuiltInPrinterPlugin(context.applicationContext)
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

            "printPngPages" -> {
                val pages = decodePages(call.argument<Any>("pages"))
                val maxWidth = call.argument<Int>("maxWidthPx") ?: 384
                if (pages.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "pages required", null)
                    return
                }
                Thread {
                    try {
                        bindAndPrintBitmap(pages, maxWidth)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "printPngPages failed", e)
                        result.error("PRINT_FAILED", e.message ?: e.javaClass.simpleName, null)
                    } finally {
                        unbind()
                    }
                }.start()
            }

            "printEscPos" -> {
                val data = decodeBytes(call.argument<Any>("data"))
                if (data.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "data required", null)
                    return
                }
                Thread {
                    try {
                        bindAndPrintEscPos(data)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "printEscPos failed", e)
                        result.error("PRINT_FAILED", e.message ?: e.javaClass.simpleName, null)
                    } finally {
                        unbind()
                    }
                }.start()
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

            else -> result.notImplemented()
        }
    }

    private fun isPackageInstalled(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    SERVICE_PACKAGE,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(SERVICE_PACKAGE, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun isServiceInstalled(): Boolean {
        val intent = Intent().apply {
            setClassName(SERVICE_PACKAGE, SERVICE_CLASS)
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
                    service = PrinterInterface.Stub.asInterface(binder)
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
            setClassName(SERVICE_PACKAGE, SERVICE_CLASS)
        }
        context.startService(intent)
        val bound = context.bindService(intent, connection!!, Context.BIND_AUTO_CREATE)
        if (!bound) {
            throw IllegalStateException("SENRAISE_BIND_FAILED")
        }

        if (!latch.await(10, TimeUnit.SECONDS)) {
            throw IllegalStateException("SENRAISE_BIND_TIMEOUT")
        }
        bindError.get()?.let { throw it }
        if (service == null) {
            throw IllegalStateException("SENRAISE_SERVICE_NULL")
        }
    }

    private fun decodeBytes(raw: Any?): ByteArray {
        return when (raw) {
            is ByteArray -> raw
            is Array<*> -> raw.filterIsInstance<Byte>().toByteArray()
            else -> ByteArray(0)
        }
    }

    private fun bindAndPrintBitmap(pages: List<ByteArray>, maxWidth: Int) {
        bindServiceSync()
        val printer = service ?: throw IllegalStateException("SENRAISE_SERVICE_NULL")

        printer.beginWork()
        try {
            printer.setAlignment(1)
            for (raw in pages) {
                var bitmap = BitmapFactory.decodeByteArray(raw, 0, raw.size)
                    ?: throw IllegalStateException("SENRAISE_BITMAP_DECODE_FAILED")
                val scaled = scaleBitmap(bitmap, maxWidth)
                if (scaled !== bitmap && !bitmap.isRecycled) {
                    bitmap.recycle()
                }
                bitmap = toMonochrome(scaled)
                if (scaled !== bitmap && !scaled.isRecycled) {
                    scaled.recycle()
                }
                printer.printBitmap(bitmap)
                if (!bitmap.isRecycled) {
                    bitmap.recycle()
                }
            }
            printer.nextLine(3)
        } finally {
            printer.endWork()
        }
    }

    private fun bindAndPrintEscPos(data: ByteArray) {
        bindServiceSync()
        val printer = service ?: throw IllegalStateException("SENRAISE_SERVICE_NULL")

        printer.beginWork()
        try {
            printer.printEpson(data)
            printer.nextLine(2)
        } finally {
            printer.endWork()
        }
    }

    private fun bindAndPrintText(text: String) {
        bindServiceSync()
        val printer = service ?: throw IllegalStateException("SENRAISE_SERVICE_NULL")

        printer.beginWork()
        try {
            printer.setAlignment(1)
            printer.setTextBold(true)
            printer.printText("$text\n")
            printer.setTextBold(false)
            printer.nextLine(3)
        } finally {
            printer.endWork()
        }
    }

    private fun toMonochrome(source: Bitmap): Bitmap {
        val width = source.width
        val height = source.height
        val mono = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width)
        for (y in 0 until height) {
            source.getPixels(pixels, 0, width, 0, y, width, 1)
            for (x in 0 until width) {
                val pixel = pixels[x]
                val alpha = Color.alpha(pixel)
                if (alpha < 64) {
                    pixels[x] = Color.WHITE
                    continue
                }
                val gray = (
                    Color.red(pixel) * 0.299 +
                        Color.green(pixel) * 0.587 +
                        Color.blue(pixel) * 0.114
                    ).toInt()
                pixels[x] = if (gray < 160) Color.BLACK else Color.WHITE
            }
            mono.setPixels(pixels, 0, width, 0, y, width, 1)
        }
        if (source !== mono && !source.isRecycled) {
            // caller recycles source separately
        }
        return mono
    }

    private fun bindAndPrint(pages: List<ByteArray>, maxWidth: Int) {
        bindAndPrintBitmap(pages, maxWidth)
    }

    private fun scaleBitmap(source: Bitmap, maxWidth: Int): Bitmap {
        if (source.width <= maxWidth) return source
        val matrix = Matrix()
        val scale = maxWidth.toFloat() / source.width.toFloat()
        matrix.postScale(scale, scale)
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private fun unbind() {
        connection?.let {
            runCatching { context.unbindService(it) }
        }
        connection = null
        service = null
    }
}
