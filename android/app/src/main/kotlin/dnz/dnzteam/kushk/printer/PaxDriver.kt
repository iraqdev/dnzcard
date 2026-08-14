package dnz.dnzteam.kushk.printer

/** PAX SDK is optional; reflection avoids a required proprietary AAR. */
class PaxDriver(fallback: PrinterDriver) : ReflectiveVendorDriver(
    "PAX",
    listOf("com.pax.neptunelite.api.NeptuneLiteUser", "com.pax.dal.IDAL"),
    fallback
)
