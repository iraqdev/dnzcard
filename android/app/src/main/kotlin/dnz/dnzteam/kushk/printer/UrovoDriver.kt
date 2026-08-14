package dnz.dnzteam.kushk.printer

/** Urovo SDK is optional; reflection avoids a required proprietary AAR. */
class UrovoDriver(fallback: PrinterDriver) : ReflectiveVendorDriver(
    "UROVO",
    listOf("android.device.PrinterManager", "com.urovo.sdk.print.PrinterManager"),
    fallback
)
