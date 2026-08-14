package dnz.dnzteam.kushk.printer

/** Newland SDK is optional; reflection avoids a required proprietary AAR. */
class NewlandDriver(fallback: PrinterDriver) : ReflectiveVendorDriver(
    "NEWLAND",
    listOf("com.newland.nsdk.core.api.internal.printer.Printer"),
    fallback
)
