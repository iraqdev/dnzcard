package dnz.dnzteam.kushk.printer

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.IBinder
import dalvik.system.DexClassLoader
import java.io.File
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * طابعة Centerm/ROVOO المدمجة (مثل MTHD-M1).
 * تربط خدمة النظام aidl.com.centerm.IPrinterService وتعتمد على Stub
 * المضمّن في assets أو تطبيق PrinterDemo على الجهاز.
 */
class CentermDriver(private val context: Context) : PrinterDriver {
    private val serviceRef = AtomicReference<Any?>(null)
    private var connection: ServiceConnection? = null
    private var apiLoader: ClassLoader? = null
    private var stubClass: Class<*>? = null
    private var callbackClass: Class<*>? = null

    override fun initialize(): Boolean {
        if (serviceRef.get() != null) return true
        if (!ensureApiClasses()) return false
        return bindBlocking()
    }

    private fun ensureApiClasses(): Boolean {
        if (stubClass != null && callbackClass != null) return true
        val loader = buildApiClassLoader() ?: return false
        return try {
            stubClass = loader.loadClass("com.centerm.printerservice.IPrinterService\$Stub")
            callbackClass = loader.loadClass("com.centerm.printerservice.ICallback")
            apiLoader = loader
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun buildApiClassLoader(): ClassLoader? {
        val candidates = mutableListOf<String>()
        // 1) APK مضمّن في التطبيق
        try {
            val out = File(context.codeCacheDir, "centerm_printer_client.apk")
            if (!out.exists() || out.length() == 0L) {
                context.assets.open("centerm_printer_client.apk").use { input ->
                    out.outputStream().use { output -> input.copyTo(output) }
                }
            }
            candidates += out.absolutePath
        } catch (_: Exception) {
        }
        // 2) تطبيق العرض الرسمي إن وُجد
        try {
            candidates += context.packageManager
                .getApplicationInfo(DEMO_PACKAGE, 0).sourceDir
        } catch (_: Exception) {
        }

        val optimized = File(context.codeCacheDir, "centerm_dex").apply { mkdirs() }
        for (path in candidates.distinct()) {
            try {
                return DexClassLoader(path, optimized.absolutePath, null, context.classLoader)
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun bindBlocking(): Boolean {
        val latch = CountDownLatch(1)
        val stub = stubClass ?: return false
        val conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                try {
                    val asInterface = stub.getMethod("asInterface", IBinder::class.java)
                    serviceRef.set(asInterface.invoke(null, binder))
                } catch (_: Exception) {
                    serviceRef.set(null)
                } finally {
                    latch.countDown()
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                serviceRef.set(null)
            }
        }
        connection = conn
        val intent = Intent(ACTION).setPackage(SERVICE_PACKAGE)
        val ok = try {
            context.bindService(intent, conn, Context.BIND_AUTO_CREATE)
        } catch (_: Exception) {
            false
        }
        if (!ok) return false
        val ready = latch.await(8, TimeUnit.SECONDS) && serviceRef.get() != null
        if (ready) {
            invokeQuiet("initPrinter", newCallback())
        }
        return ready
    }

    override fun printText(text: String): Boolean {
        if (!ensureBound()) return false
        val lines = text.replace("\r\n", "\n").split('\n')
        var ok = true
        for (line in lines) {
            val printed = invoke("printText", line, newCallback()) ||
                invoke("printTextWithFont", line, "", 24f, newCallback())
            if (!printed) ok = false
        }
        invokeQuiet("lineFeed", 3, newCallback())
        invokeQuiet("commitTransaction", newCallback())
        return ok
    }

    override fun printImage(bytes: ByteArray?): Boolean {
        if (bytes == null || !ensureBound()) return false
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return false
        val opaque = flattenOnWhite(decoded)
        if (decoded !== opaque && !decoded.isRecycled) decoded.recycle()
        if (isMostlyBlack(opaque)) {
            if (!opaque.isRecycled) opaque.recycle()
            return false
        }
        val bitmap = scaleToPaper(opaque)
        return try {
            val printed = invoke("printImage", bitmap, newCallback()) ||
                invoke("printImageWithType", bitmap, 0, newCallback())
            invokeQuiet("lineFeed", 2, newCallback())
            invokeQuiet("commitTransaction", newCallback())
            printed
        } finally {
            if (bitmap !== opaque && !bitmap.isRecycled) bitmap.recycle()
            if (!opaque.isRecycled) opaque.recycle()
        }
    }

    private fun flattenOnWhite(source: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(out)
        canvas.drawColor(android.graphics.Color.WHITE)
        canvas.drawBitmap(source, 0f, 0f, null)
        return out
    }

    private fun isMostlyBlack(bitmap: Bitmap): Boolean {
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return true
        val stepX = (w / 24).coerceAtLeast(1)
        val stepY = (h / 24).coerceAtLeast(1)
        var dark = 0
        var total = 0
        var y = 0
        while (y < h) {
            var x = 0
            while (x < w) {
                val c = bitmap.getPixel(x, y)
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                val gray = (r * 30 + g * 59 + b * 11) / 100
                if (gray < 40) dark++
                total++
                x += stepX
            }
            y += stepY
        }
        return total > 0 && dark * 100 / total >= 85
    }

    private fun scaleToPaper(source: Bitmap): Bitmap {
        val maxWidth = PrintPaperConfig.widthDots.coerceAtLeast(192)
        if (source.width <= maxWidth) return source
        val height = (source.height * maxWidth.toFloat() / source.width).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(source, maxWidth, height, true)
    }

    override fun printQR(data: String): Boolean {
        if (!ensureBound()) return false
        return invoke("printQRCode", data, 6, 1, newCallback()) ||
            invoke("printQRCode", data, newCallback())
    }

    override fun printBarcode(data: String): Boolean {
        if (!ensureBound()) return false
        return invoke("printBarCode", data, 8, 80, 2, 0, newCallback())
    }

    override fun feed(lines: Int): Boolean {
        if (!ensureBound()) return false
        return invoke("lineFeed", lines.coerceIn(1, 20), newCallback())
    }

    override fun cut(): Boolean {
        if (!ensureBound()) return false
        val cut = byteArrayOf(0x1D, 0x56, 0x00)
        return invoke("sendEscData", cut, newCallback()) || true
    }

    override fun openDrawer(): Boolean {
        if (!ensureBound()) return false
        val pulse = byteArrayOf(0x1B, 0x70, 0x00, 0x19, 0xFA.toByte())
        return invoke("sendEscData", pulse, newCallback())
    }

    override fun isReady(): Boolean = serviceRef.get() != null

    override fun name(): String = "CENTERM"

    private fun ensureBound(): Boolean = serviceRef.get() != null || initialize()

    private fun newCallback(): Any? {
        val type = callbackClass ?: return null
        val loader = apiLoader ?: type.classLoader
        return try {
            Proxy.newProxyInstance(
                loader,
                arrayOf(type),
                InvocationHandler { _, method, _ ->
                    when (method.name) {
                        "asBinder" -> null
                        "hashCode" -> System.identityHashCode(this@CentermDriver)
                        "equals" -> false
                        "toString" -> "KushkCentermCallback"
                        else -> null
                    }
                }
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun invoke(methodName: String, vararg args: Any?): Boolean {
        val service = serviceRef.get() ?: return false
        return try {
            val method = findMethod(service.javaClass, methodName, args.size) ?: return false
            method.isAccessible = true
            method.invoke(service, *coerceArgs(method, args))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun invokeQuiet(methodName: String, vararg args: Any?) {
        invoke(methodName, *args)
    }

    private fun findMethod(type: Class<*>, name: String, paramCount: Int): Method? =
        (type.methods + type.declaredMethods)
            .firstOrNull { it.name == name && it.parameterCount == paramCount }

    private fun coerceArgs(method: Method, args: Array<out Any?>): Array<Any?> {
        val params = method.parameterTypes
        return Array(args.size) { i ->
            val arg = args[i]
            val expected = params[i]
            when {
                arg == null -> null
                expected == Float::class.javaPrimitiveType && arg is Number -> arg.toFloat()
                expected == Int::class.javaPrimitiveType && arg is Number -> arg.toInt()
                expected == Bitmap::class.java && arg is Bitmap -> arg
                expected.isArray && expected.componentType == Byte::class.javaPrimitiveType &&
                    arg is ByteArray -> arg
                else -> arg
            }
        }
    }

    private companion object {
        const val ACTION = "aidl.com.centerm.IPrinterService"
        const val SERVICE_PACKAGE = "com.centerm.printerservice"
        const val DEMO_PACKAGE = "com.centerm.printerdemo"
    }
}
