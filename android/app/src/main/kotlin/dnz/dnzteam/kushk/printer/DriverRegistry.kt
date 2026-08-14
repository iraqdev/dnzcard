package dnz.dnzteam.kushk.printer

import android.app.Activity
import android.content.Context

class DriverRegistry(
    context: Context,
    activityProvider: () -> Activity?
) {
    private val androidPrint = AndroidPrintDriver(activityProvider)
    private val bluetooth = BluetoothDriver(context)
    private val usb = UsbDriver(context)
    private val network = NetworkDriver()
    private val escPos = EscPosDriver()
    private val centerm = CentermDriver(context)

    private val drivers: Map<String, PrinterDriver> = mapOf(
        "CENTERM" to centerm,
        "ROVOO" to centerm,
        "MTHD" to centerm,
        "SUNMI" to SunmiDriver(escPos),
        "PAX" to PaxDriver(escPos),
        "IMIN" to IMinDriver(escPos),
        "UROVO" to UrovoDriver(escPos),
        "TELPO" to TelpoDriver(escPos),
        "NEWLAND" to NewlandDriver(escPos),
        "ESC_POS" to escPos,
        "ANDROID_PRINT" to androidPrint,
        "BLUETOOTH" to bluetooth,
        "USB" to usb,
        "NETWORK" to network
    )

    fun get(name: String?): PrinterDriver? = drivers[name?.uppercase()]

    fun manufacturerDriver(device: DeviceInfo): String? {
        val hay = device.fingerprint
        return VENDOR_ALIASES.entries.firstOrNull { hay.contains(it.key) }?.value
    }

    /** ترتيب POS الحقيقي — بدون ANDROID_PRINT (يفتح حوار بحث فارغ). */
    fun fallbackChain(): List<PrinterDriver> = listOf(centerm, usb, bluetooth, network)

    fun setPaperWidthDots(dots: Int) {
        PrintPaperConfig.widthDots = dots.coerceIn(192, 576)
    }

    fun listDevices(): List<Map<String, String>> {
        val builtIn = mutableListOf<Map<String, String>>()
        if (centerm.initialize() || isCentermDevice()) {
            builtIn += mapOf(
                "id" to "builtin-centerm",
                "name" to "طابعة Centerm المدمجة (MTHD)",
                "address" to "builtin-centerm",
                "type" to "CENTERM"
            )
        }
        return builtIn + usb.listDevices() + bluetooth.listBondedDevices()
    }

    fun configure(name: String, settings: Map<String, Any?>) {
        when (get(name)?.name()) {
            "BLUETOOTH" -> bluetooth.setAddress(
                settings["address"] as? String ?: settings["id"] as? String
            )
            "USB" -> usb.setDeviceName(
                settings["address"] as? String ?: settings["id"] as? String
            )
            "NETWORK" -> network.configure(
                settings["host"] as? String ?: settings["ip"] as? String,
                (settings["port"] as? Number)?.toInt()
            )
        }
    }

    private fun isCentermDevice(): Boolean {
        val hay = DeviceInfo().fingerprint
        return VENDOR_ALIASES.keys.any { hay.contains(it) }
    }

    private companion object {
        val VENDOR_ALIASES = mapOf(
            "CENTERM" to "CENTERM",
            "ROVOO" to "CENTERM",
            "MTHD" to "CENTERM",
            "SUNMI" to "SUNMI",
            "PAX" to "PAX",
            "IMIN" to "IMIN",
            "UROVO" to "UROVO",
            "TELPO" to "TELPO",
            "NEWLAND" to "NEWLAND"
        )
    }
}
