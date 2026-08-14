package dnz.dnzteam.kushk.printer

import java.io.OutputStream
import java.nio.charset.Charset

/** ESC/POS command encoder. A transport injects an OutputStream once connected. */
class EscPosDriver(private var output: OutputStream? = null) : PrinterDriver {
    private val charset = Charset.forName("UTF-8")

    fun setOutputStream(stream: OutputStream?) {
        output = stream
    }

    fun bytesForText(text: String): ByteArray = command(ESC_INIT, text.toByteArray(charset), LF)
    fun bytesForFeed(lines: Int): ByteArray = byteArrayOf(0x1B, 0x64, lines.coerceIn(0, 255).toByte())
    fun bytesForCut(): ByteArray = byteArrayOf(0x1D, 0x56, 0x00)
    fun bytesForDrawer(): ByteArray = byteArrayOf(0x1B, 0x70, 0x00, 0x19, 0xFA.toByte())
    fun bytesForQr(data: String): ByteArray {
        val payload = data.toByteArray(charset)
        val length = payload.size + 3
        return command(
            byteArrayOf(0x1D, 0x28, 0x6B, length.toByte(), (length shr 8).toByte(), 0x31, 0x50, 0x30),
            payload,
            byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30)
        )
    }

    fun bytesForBarcode(data: String): ByteArray {
        val payload = data.toByteArray(charset).take(255).toByteArray()
        return command(byteArrayOf(0x1D, 0x6B, 0x49, payload.size.toByte()), payload)
    }

    override fun initialize() = output != null
    override fun printText(text: String) = write(bytesForText(text))
    override fun printImage(bytes: ByteArray?): Boolean {
        if (bytes == null) return false
        val raster = EscPosRaster.pngToRaster(bytes) ?: return write(bytes)
        return write(raster)
    }
    override fun printQR(data: String) = write(bytesForQr(data))
    override fun printBarcode(data: String) = write(bytesForBarcode(data))
    override fun feed(lines: Int) = write(bytesForFeed(lines))
    override fun cut() = write(bytesForCut())
    override fun openDrawer() = write(bytesForDrawer())
    override fun isReady() = output != null
    override fun name() = "ESC_POS"

    private fun write(bytes: ByteArray): Boolean = try {
        output?.apply { write(bytes); flush() } != null
    } catch (_: Exception) {
        false
    }

    private fun command(vararg parts: ByteArray): ByteArray =
        parts.fold(ByteArray(0)) { all, part -> all + part }

    private companion object {
        val ESC_INIT = byteArrayOf(0x1B, 0x40)
        val LF = byteArrayOf(0x0A)
    }
}
