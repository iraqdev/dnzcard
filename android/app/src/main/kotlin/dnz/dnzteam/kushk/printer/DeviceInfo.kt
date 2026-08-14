package dnz.dnzteam.kushk.printer

import android.os.Build

data class DeviceInfo(
    val manufacturer: String = Build.MANUFACTURER.orEmpty(),
    val brand: String = Build.BRAND.orEmpty(),
    val model: String = Build.MODEL.orEmpty(),
    val device: String = Build.DEVICE.orEmpty()
) {
    val fingerprint: String
        get() = listOf(manufacturer, brand, model, device)
            .joinToString(" ")
            .trim()
            .uppercase()

    fun asMap(): Map<String, String> = mapOf(
        "manufacturer" to manufacturer,
        "brand" to brand,
        "model" to model,
        "device" to device
    )
}
