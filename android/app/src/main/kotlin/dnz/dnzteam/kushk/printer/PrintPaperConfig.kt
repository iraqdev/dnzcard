package dnz.dnzteam.kushk.printer

/** عرض الورق الحالي بالنقاط — يُحدَّث من إعدادات المستخدم (58mm=384 / 80mm=576). */
object PrintPaperConfig {
    @Volatile
    var widthDots: Int = 384

    fun setFromMm(mm: Int) {
        widthDots = if (mm >= 80) 576 else 384
    }
}
