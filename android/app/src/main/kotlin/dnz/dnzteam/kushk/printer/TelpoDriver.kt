package dnz.dnzteam.kushk.printer

/** Telpo SDK is optional; reflection avoids a required proprietary AAR. */
class TelpoDriver(fallback: PrinterDriver) : ReflectiveVendorDriver(
    "TELPO",
    listOf("com.telpoo.frame.object.TelpoPrint", "com.common.sdk.service.PrinterService"),
    fallback
)
