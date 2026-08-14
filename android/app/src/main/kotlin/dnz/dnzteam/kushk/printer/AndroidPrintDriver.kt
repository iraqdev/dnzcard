package dnz.dnzteam.kushk.printer

import android.app.Activity
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.os.ParcelFileDescriptor
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager

/** Uses the Android system print UI, which lets the user choose any installed printer. */
class AndroidPrintDriver(private val activityProvider: () -> Activity?) : PrinterDriver {
    override fun initialize() = activityProvider() != null

    override fun printText(text: String): Boolean {
        val activity = activityProvider() ?: return false
        return try {
            val manager = activity.getSystemService(PrintManager::class.java) ?: return false
            manager.print("Kushk receipt", TextDocumentAdapter(text), PrintAttributes.Builder().build())
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun printImage(bytes: ByteArray?) = false
    override fun printQR(data: String) = printText(data)
    override fun printBarcode(data: String) = printText(data)
    override fun feed(lines: Int) = printText("\n".repeat(lines.coerceAtLeast(0)))
    override fun cut() = false
    override fun openDrawer() = false
    override fun isReady() = activityProvider() != null
    override fun name() = "ANDROID_PRINT"

    private class TextDocumentAdapter(private val text: String) : PrintDocumentAdapter() {
        override fun onLayout(
            oldAttributes: PrintAttributes?,
            newAttributes: PrintAttributes?,
            cancellationSignal: android.os.CancellationSignal?,
            callback: LayoutResultCallback?,
            extras: android.os.Bundle?
        ) {
            callback?.onLayoutFinished(
                PrintDocumentInfo.Builder("kushk-receipt.pdf")
                    .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                    .setPageCount(1)
                    .build(),
                oldAttributes != newAttributes
            )
        }

        override fun onWrite(
            pages: Array<android.print.PageRange>,
            destination: ParcelFileDescriptor,
            cancellationSignal: android.os.CancellationSignal?,
            callback: WriteResultCallback?
        ) {
            try {
                val document = PdfDocument()
                try {
                    val page = document.startPage(PdfDocument.PageInfo.Builder(300, 842, 1).create())
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 12f }
                    var y = 28f
                    text.lines().forEach {
                        page.canvas.drawText(it, 16f, y, paint)
                        y += 18f
                    }
                    document.finishPage(page)
                    ParcelFileDescriptor.AutoCloseOutputStream(destination).use { output ->
                        document.writeTo(output)
                    }
                } finally {
                    document.close()
                }
                callback?.onWriteFinished(arrayOf(android.print.PageRange.ALL_PAGES))
            } catch (_: Exception) {
                callback?.onWriteFailed("Unable to create receipt document")
            }
        }
    }
}
