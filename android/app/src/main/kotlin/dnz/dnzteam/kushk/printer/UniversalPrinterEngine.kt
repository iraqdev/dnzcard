package dnz.dnzteam.kushk.printer

import android.app.Activity
import android.content.Context

/**
 * Selects a real transport for the current Android device and persists the user's choice.
 */
class UniversalPrinterEngine(
    context: Context,
    activityProvider: () -> Activity?
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val registry = DriverRegistry(context.applicationContext, activityProvider)
    private val deviceInfo = DeviceInfo()
    private var selected: PrinterDriver? = null

    init {
        val vendor = registry.manufacturerDriver(deviceInfo)
        val persisted = persistedDriver()
        val initial = when {
            vendor != null && (
                persisted.isNullOrBlank() ||
                    persisted == "AUTO" ||
                    persisted == "ESC_POS" ||
                    persisted == "ANDROID_PRINT"
                ) -> vendor
            else -> persisted ?: vendor ?: "AUTO"
        }
        select(initial, emptyMap())
        registry.setPaperWidthDots(paperWidthDots(paperSizeMm()))
    }

    fun detect(): Map<String, Any> {
        val suggested = registry.manufacturerDriver(deviceInfo) ?: "BLUETOOTH"
        val devices = registry.listDevices()
        val paperMm = paperSizeMm()
        return deviceInfo.asMap() + mapOf(
            "suggestedDriver" to suggested,
            "selectedDriver" to (selected?.name() ?: ""),
            "driver" to (selected?.name() ?: ""),
            "ready" to (selected?.isReady() == true),
            "devices" to devices,
            "paperSizeMm" to paperMm,
            "paperWidthDots" to paperWidthDots(paperMm),
            "fallbacks" to listOf("USB", "BLUETOOTH", "NETWORK")
        )
    }

    fun getStatus(): Map<String, Any> = detect() + mapOf(
        "status" to statusLabel(),
        "ready" to (selected?.isReady() == true),
        "driver" to (selected?.name() ?: "")
    )

    fun listDevices(): List<Map<String, String>> = registry.listDevices()

    fun setDriver(name: String, settings: Map<String, Any?> = emptyMap()): Boolean =
        select(name, settings)

    fun setPaperSizeMm(mm: Int): Map<String, Any> {
        val normalized = if (mm >= 80) 80 else 58
        preferences.edit().putInt(KEY_PAPER_MM, normalized).apply()
        registry.setPaperWidthDots(paperWidthDots(normalized))
        return mapOf(
            "mm" to normalized,
            "dots" to paperWidthDots(normalized)
        )
    }

    fun getPaperSize(): Map<String, Any> {
        val mm = paperSizeMm()
        return mapOf("mm" to mm, "dots" to paperWidthDots(mm))
    }

    fun printText(text: String) = withDriver { it.printText(text) }
    fun printReceipt(text: String, image: ByteArray? = null) = withDriver { driver ->
        registry.setPaperWidthDots(paperWidthDots(paperSizeMm()))
        val printed = when {
            image != null && driver.printImage(image) -> true
            text.isNotBlank() -> driver.printText(text)
            else -> false
        }
        printed && driver.feed(3) && driver.cut()
    }

    fun printCard(title: String, body: String) = withDriver {
        it.printText("$title\n$body\n") && it.feed(2)
    }

    fun testPrint() = printReceipt("Kushk\nPrinter test successful\n")
    fun openDrawer() = withDriver { it.openDrawer() }
    fun cut() = withDriver { it.cut() }
    fun feed(lines: Int) = withDriver { it.feed(lines) }

    private fun select(name: String, settings: Map<String, Any?>): Boolean {
        val normalized = name.trim().uppercase()
        if (normalized == "AUTO" || normalized.isEmpty()) {
            return autoSelect(settings)
        }
        val requested = registry.get(normalized) ?: return false
        registry.configure(normalized, settings)
        selected = if (requested.initialize()) {
            requested
        } else if (normalized == "ANDROID_PRINT") {
            // فقط إذا اختارها المستخدم صراحة
            requested
        } else {
            null
        }
        preferences.edit().putString(KEY_DRIVER, selected?.name() ?: normalized).apply()
        if (!settings.isEmpty()) {
            settings["address"]?.toString()?.let {
                preferences.edit().putString(KEY_ADDRESS, it).apply()
            }
            settings["id"]?.toString()?.let {
                preferences.edit().putString(KEY_ADDRESS, it).apply()
            }
        }
        return selected?.isReady() == true
    }

    private fun autoSelect(settings: Map<String, Any?>): Boolean {
        val address = settings["address"] as? String
            ?: settings["id"] as? String
            ?: preferences.getString(KEY_ADDRESS, null)
        val withAddress = if (address.isNullOrBlank()) emptyMap() else mapOf("address" to address)

        val vendor = registry.manufacturerDriver(deviceInfo)
        if (vendor != null) {
            registry.configure(vendor, withAddress)
            val driver = registry.get(vendor)
            if (driver?.initialize() == true) {
                selected = driver
                preferences.edit().putString(KEY_DRIVER, driver.name()).apply()
                return true
            }
        }

        for (driver in registry.fallbackChain()) {
            registry.configure(driver.name(), withAddress)
            if (driver.initialize()) {
                selected = driver
                preferences.edit().putString(KEY_DRIVER, driver.name()).apply()
                return true
            }
        }

        selected = null
        preferences.edit().putString(KEY_DRIVER, "AUTO").apply()
        return false
    }

    private fun withDriver(action: (PrinterDriver) -> Boolean): Boolean {
        val current = selected
        if (current != null && (current.isReady() || current.initialize())) {
            return action(current)
        }
        if (autoSelect(emptyMap())) {
            val next = selected ?: return false
            return action(next)
        }
        return false
    }

    private fun statusLabel(): String {
        val driver = selected?.name()
        return when {
            driver == null -> "لم يتم العثور على طابعة — اختر جهازاً مقترناً أو USB"
            selected?.isReady() == true -> "متصل: $driver"
            else -> "غير جاهز: $driver"
        }
    }

    private fun persistedDriver() = preferences.getString(KEY_DRIVER, null)

    private fun paperSizeMm(): Int {
        val value = preferences.getInt(KEY_PAPER_MM, 58)
        return if (value >= 80) 80 else 58
    }

    private fun paperWidthDots(mm: Int): Int = if (mm >= 80) 576 else 384

    private companion object {
        const val PREFERENCES = "kushk_printer"
        const val KEY_DRIVER = "selected_driver"
        const val KEY_ADDRESS = "selected_address"
        const val KEY_PAPER_MM = "paper_size_mm"
    }
}
