package dnz.dnzteam.kushk.printer

/**
 * Common, dependency-free contract for all printer transports and vendor SDK adapters.
 * Methods return false when the operation could not be delivered to a physical printer.
 */
interface PrinterDriver {
    fun initialize(): Boolean
    fun printText(text: String): Boolean
    fun printImage(bytes: ByteArray?): Boolean
    fun printQR(data: String): Boolean
    fun printBarcode(data: String): Boolean
    fun feed(lines: Int): Boolean
    fun cut(): Boolean
    fun openDrawer(): Boolean
    fun isReady(): Boolean
    fun name(): String
}
