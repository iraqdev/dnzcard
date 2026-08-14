package dnz.dnzteam.kushk.printer

/** iMin SDK is optional; reflection avoids a required proprietary AAR. */
class IMinDriver(fallback: PrinterDriver) : ReflectiveVendorDriver(
    "IMIN",
    listOf("com.imin.printerlib.IminPrintUtils"),
    fallback
)
