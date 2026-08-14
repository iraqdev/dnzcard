package dnz.dnzteam.kushk.printer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color

/** يحول صورة PNG/JPEG إلى أوامر ESC/POS نقطية (GS v 0). */
object EscPosRaster {
    fun pngToRaster(bytes: ByteArray, maxWidth: Int = PrintPaperConfig.widthDots): ByteArray? {
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val width = minOf(source.width, maxWidth).let { if (it % 8 == 0) it else it - (it % 8) }
        if (width <= 0) return null
        val height = (source.height * width.toFloat() / source.width).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
        val mono = toMono(scaled)
        return rasterCommand(mono)
    }

    private fun toMono(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val gray =
                    (Color.red(pixel) * 0.3 + Color.green(pixel) * 0.59 + Color.blue(pixel) * 0.11).toInt()
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
        val xL = widthBytes and 0xFF
        val xH = (widthBytes shr 8) and 0xFF
        val yL = height and 0xFF
        val yH = (height shr 8) and 0xFF
        val header = byteArrayOf(0x1D, 0x76, 0x30, 0x00, xL.toByte(), xH.toByte(), yL.toByte(), yH.toByte())
        return header + data + byteArrayOf(0x0A)
    }
}
