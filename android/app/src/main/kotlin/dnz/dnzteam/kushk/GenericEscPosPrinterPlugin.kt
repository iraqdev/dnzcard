package dnz.dnzteam.kushk

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * ناقلات ESC/POS عامة (منقولة من نظام طباعة Kushk):
 * - طابعات USB (USB-host bulk transfer)
 * - طابعات الشبكة Ethernet/Wi-Fi (TCP منفذ 9100)
 *
 * إضافة مستقلة تماماً — لا تمسّ مسارات الطابعات المدمجة الحالية
 * (Senraise / iPos / Sunmi / Switch Pos / Bluetooth).
 */
class GenericEscPosPrinterPlugin private constructor(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "GenericEscPosPrinter"
        private const val CHANNEL = "kushk/generic_escpos_printer"
        private const val ACTION_USB_PERMISSION =
            "dnz.dnzteam.cards.USB_PRINTER_PERMISSION"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val plugin = GenericEscPosPrinterPlugin(context.applicationContext)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(plugin)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasUsbPrinter" -> {
                result.success(findUsbPrinterDevice() != null)
            }

            "hasUsbPermission" -> {
                val device = findUsbPrinterDevice()
                val manager = usbManager()
                result.success(
                    device != null && manager != null && manager.hasPermission(device),
                )
            }

            "requestUsbPermission" -> {
                Thread {
                    try {
                        val granted = requestUsbPermissionSync()
                        postSuccess(result, granted)
                    } catch (e: Exception) {
                        Log.e(TAG, "requestUsbPermission failed", e)
                        postError(result, "USB_PERMISSION_FAILED", e)
                    }
                }.start()
            }

            "printUsbPng" -> {
                val pages = call.argument<List<ByteArray>>("pages") ?: emptyList()
                val maxWidth = call.argument<Int>("maxWidthPx") ?: 384
                Thread {
                    try {
                        printUsb(pages, maxWidth)
                        postSuccess(result, true)
                    } catch (e: Exception) {
                        Log.e(TAG, "printUsbPng failed", e)
                        postError(result, "USB_PRINT_FAILED", e)
                    }
                }.start()
            }

            "printNetworkPng" -> {
                val host = call.argument<String>("host") ?: ""
                val port = call.argument<Int>("port") ?: 9100
                val pages = call.argument<List<ByteArray>>("pages") ?: emptyList()
                val maxWidth = call.argument<Int>("maxWidthPx") ?: 384
                Thread {
                    try {
                        printNetwork(host, port, pages, maxWidth)
                        postSuccess(result, true)
                    } catch (e: Exception) {
                        Log.e(TAG, "printNetworkPng failed", e)
                        postError(result, "NETWORK_PRINT_FAILED", e)
                    }
                }.start()
            }

            else -> result.notImplemented()
        }
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: MethodChannel.Result, code: String, e: Exception) {
        mainHandler.post {
            result.error(code, e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ---------------------------------------------------------------- USB

    private fun usbManager(): UsbManager? =
        context.getSystemService(Context.USB_SERVICE) as? UsbManager

    /** يبحث عن أول جهاز USB يملك منفذ إخراج bulk (سمة الطابعات الحرارية). */
    private fun findUsbPrinterDevice(): UsbDevice? {
        val manager = usbManager() ?: return null
        return manager.deviceList.values.firstOrNull { device ->
            (0 until device.interfaceCount).any { i ->
                val iface = device.getInterface(i)
                (0 until iface.endpointCount).any { e ->
                    val endpoint = iface.getEndpoint(e)
                    endpoint.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                        endpoint.direction == UsbConstants.USB_DIR_OUT
                }
            }
        }
    }

    private fun requestUsbPermissionSync(): Boolean {
        val manager = usbManager() ?: throw IllegalStateException("USB_UNSUPPORTED")
        val device = findUsbPrinterDevice()
            ?: throw IllegalStateException("USB_PRINTER_NOT_FOUND")
        if (manager.hasPermission(device)) return true

        val latch = CountDownLatch(1)
        var granted = false
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action == ACTION_USB_PERMISSION) {
                    granted = intent.getBooleanExtra(
                        UsbManager.EXTRA_PERMISSION_GRANTED,
                        false,
                    )
                    latch.countDown()
                }
            }
        }

        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }

        try {
            val flags = if (Build.VERSION.SDK_INT >= 31) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
            val pending = PendingIntent.getBroadcast(
                context,
                0,
                Intent(ACTION_USB_PERMISSION).setPackage(context.packageName),
                flags,
            )
            manager.requestPermission(device, pending)
            latch.await(60, TimeUnit.SECONDS)
        } finally {
            try {
                context.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
        }
        return granted
    }

    private fun printUsb(pages: List<ByteArray>, maxWidth: Int) {
        val manager = usbManager() ?: throw IllegalStateException("USB_UNSUPPORTED")
        val device = findUsbPrinterDevice()
            ?: throw IllegalStateException("USB_PRINTER_NOT_FOUND")
        if (!manager.hasPermission(device)) {
            throw IllegalStateException("USB_PERMISSION_DENIED")
        }

        val usbInterface = (0 until device.interfaceCount)
            .map(device::getInterface)
            .firstOrNull { iface ->
                (0 until iface.endpointCount).any {
                    val ep = iface.getEndpoint(it)
                    ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                        ep.direction == UsbConstants.USB_DIR_OUT
                }
            } ?: throw IllegalStateException("USB_ENDPOINT_MISSING")
        val endpoint = (0 until usbInterface.endpointCount)
            .map(usbInterface::getEndpoint)
            .first {
                it.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    it.direction == UsbConstants.USB_DIR_OUT
            }

        val connection = manager.openDevice(device)
            ?.takeIf { it.claimInterface(usbInterface, true) }
            ?: throw IllegalStateException("USB_OPEN_FAILED")

        try {
            val payload = buildEscPosPayload(pages, maxWidth)
            var offset = 0
            // إرسال على دفعات — بعض الطابعات ترفض الحزم الكبيرة دفعة واحدة.
            val chunk = 16 * 1024
            while (offset < payload.size) {
                val len = minOf(chunk, payload.size - offset)
                val part = payload.copyOfRange(offset, offset + len)
                val sent = connection.bulkTransfer(endpoint, part, part.size, 10_000)
                if (sent != part.size) {
                    throw IllegalStateException("USB_TRANSFER_FAILED")
                }
                offset += len
            }
        } finally {
            try {
                connection.releaseInterface(usbInterface)
            } catch (_: Exception) {
            }
            connection.close()
        }
    }

    // ------------------------------------------------------------ Network

    private fun printNetwork(
        host: String,
        port: Int,
        pages: List<ByteArray>,
        maxWidth: Int,
    ) {
        if (host.isBlank()) {
            throw IllegalStateException("NETWORK_PRINTER_NOT_CONFIGURED")
        }
        val payload = buildEscPosPayload(pages, maxWidth)
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), 7_000)
            socket.getOutputStream().use { out ->
                out.write(payload)
                out.flush()
            }
        }
    }

    // ------------------------------------------------------------ ESC/POS

    /** init + صفحات raster + تغذية 3 أسطر + قص. */
    private fun buildEscPosPayload(pages: List<ByteArray>, maxWidth: Int): ByteArray {
        if (pages.isEmpty()) throw IllegalStateException("NO_PAGES")
        var payload = byteArrayOf(0x1B, 0x40) // ESC @ — init
        for (raw in pages) {
            val raster = pngToRaster(raw, maxWidth)
                ?: throw IllegalStateException("BITMAP_DECODE_FAILED")
            payload += raster
        }
        payload += byteArrayOf(0x1B, 0x64, 0x03) // ESC d 3 — feed
        payload += byteArrayOf(0x1D, 0x56, 0x42, 0x00) // GS V B 0 — cut
        return payload
    }

    /** يحول صورة PNG إلى أوامر ESC/POS نقطية (GS v 0) — منقول من Kushk. */
    private fun pngToRaster(bytes: ByteArray, maxWidth: Int): ByteArray? {
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val width = minOf(source.width, maxWidth).let {
            if (it % 8 == 0) it else it - (it % 8)
        }
        if (width <= 0) return null
        val height =
            (source.height * width.toFloat() / source.width).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
        if (scaled !== source && !source.isRecycled) source.recycle()
        val raster = rasterCommand(toMono(scaled))
        if (!scaled.isRecycled) scaled.recycle()
        return raster
    }

    private fun toMono(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val gray = (Color.red(pixel) * 0.3 +
                    Color.green(pixel) * 0.59 +
                    Color.blue(pixel) * 0.11).toInt()
                out.setPixel(x, y, if (gray < 160) Color.BLACK else Color.WHITE)
            }
        }
        return out
    }

    private fun rasterCommand(bitmap: Bitmap): ByteArray {
        val width = bitmap.width
        val height = bitmap.height
        val widthBytes = width / 8
        val data = ByteArray(widthBytes * height)
        var index = 0
        for (y in 0 until height) {
            for (xByte in 0 until widthBytes) {
                var bits = 0
                for (bit in 0 until 8) {
                    val x = xByte * 8 + bit
                    val pixel = bitmap.getPixel(x, y)
                    if (Color.red(pixel) < 128) {
                        bits = bits or (0x80 shr bit)
                    }
                }
                data[index++] = bits.toByte()
            }
        }
        if (!bitmap.isRecycled) bitmap.recycle()
        val xL = widthBytes and 0xFF
        val xH = (widthBytes shr 8) and 0xFF
        val yL = height and 0xFF
        val yH = (height shr 8) and 0xFF
        val header = byteArrayOf(
            0x1D, 0x76, 0x30, 0x00,
            xL.toByte(), xH.toByte(), yL.toByte(), yH.toByte(),
        )
        return header + data + byteArrayOf(0x0A)
    }
}
