package dnz.dnzteam.kushk.printer

import java.net.Socket

/** Raw TCP ESC/POS transport, used by Ethernet/Wi-Fi receipt printers (usually port 9100). */
class NetworkDriver : PrinterDriver {
    private val escPos = EscPosDriver()
    private var socket: Socket? = null
    private var host = ""
    private var port = 9100

    fun configure(ipAddress: String?, printerPort: Int?) {
        host = ipAddress.orEmpty()
        port = printerPort ?: 9100
        close()
    }

    override fun initialize(): Boolean {
        if (host.isBlank()) return false
        return try {
            socket = Socket(host, port)
            escPos.setOutputStream(socket?.getOutputStream())
            true
        } catch (_: Exception) {
            close()
            false
        }
    }

    override fun printText(text: String) = escPos.printText(text)
    override fun printImage(bytes: ByteArray?) = escPos.printImage(bytes)
    override fun printQR(data: String) = escPos.printQR(data)
    override fun printBarcode(data: String) = escPos.printBarcode(data)
    override fun feed(lines: Int) = escPos.feed(lines)
    override fun cut() = escPos.cut()
    override fun openDrawer() = escPos.openDrawer()
    override fun isReady() = socket?.isConnected == true && !socket!!.isClosed
    override fun name() = "NETWORK"

    private fun close() {
        escPos.setOutputStream(null)
        try { socket?.close() } catch (_: Exception) {}
        socket = null
    }
}
