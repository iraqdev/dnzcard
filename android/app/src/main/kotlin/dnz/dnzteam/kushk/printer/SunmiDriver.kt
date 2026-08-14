package dnz.dnzteam.kushk.printer

/** Sunmi SDK is optional; reflection avoids a required proprietary AAR. */
class SunmiDriver(fallback: PrinterDriver) : ReflectiveVendorDriver(
    "SUNMI",
    listOf("woyou.aidlservice.jiuiv5.ICWoyouService", "com.sunmi.peripheral.printer.InnerPrinterManager"),
    fallback
)
