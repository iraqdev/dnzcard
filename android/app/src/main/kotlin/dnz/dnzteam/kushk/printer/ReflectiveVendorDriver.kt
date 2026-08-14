package dnz.dnzteam.kushk.printer

/**
 * Bridges optional vendor SDKs without linking their proprietary AARs.
 * The implementation uses reflection only when the SDK is preinstalled/provided by the device.
 * Unsupported calls safely continue through the supplied standards-based fallback.
 */
abstract class ReflectiveVendorDriver(
    private val driverName: String,
    private val classNames: List<String>,
    private val fallback: PrinterDriver
) : PrinterDriver {
    private var service: Any? = null

    override fun initialize(): Boolean {
        service = classNames.asSequence().mapNotNull { className ->
            try {
                val type = Class.forName(className)
                type.methods.firstOrNull { it.name == "getInstance" && it.parameterCount == 0 }
                    ?.invoke(null)
                    ?: type.methods.firstOrNull { it.name == "getService" && it.parameterCount == 0 }
                        ?.invoke(null)
            } catch (_: Exception) {
                null
            }
        }.firstOrNull()
        return service != null || fallback.initialize()
    }

    override fun printText(text: String) = invoke("printText", text) || invoke("printOriginalText", text) || fallback.printText(text)
    override fun printImage(bytes: ByteArray?) = bytes?.let { invoke("printBitmap", it) || fallback.printImage(it) } ?: false
    override fun printQR(data: String) = invoke("printQRCode", data) || fallback.printQR(data)
    override fun printBarcode(data: String) = invoke("printBarCode", data) || fallback.printBarcode(data)
    override fun feed(lines: Int) = invoke("lineWrap", lines) || fallback.feed(lines)
    override fun cut() = invoke("cutPaper") || fallback.cut()
    override fun openDrawer() = invoke("openDrawer") || fallback.openDrawer()
    override fun isReady() = service != null || fallback.isReady()
    override fun name() = driverName

    private fun invoke(methodName: String, vararg args: Any): Boolean = try {
        val target = service ?: return false
        val method = target.javaClass.methods.firstOrNull {
            it.name == methodName && it.parameterCount == args.size
        } ?: return false
        method.invoke(target, *args)
        true
    } catch (_: Exception) {
        false
    }
}
