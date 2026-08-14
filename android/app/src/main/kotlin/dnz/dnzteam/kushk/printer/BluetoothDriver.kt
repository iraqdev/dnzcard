package dnz.dnzteam.kushk.printer

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.util.UUID

/** Sends ESC/POS data through the standard Serial Port Profile (SPP). */
class BluetoothDriver(private val context: Context) : PrinterDriver {
    private val escPos = EscPosDriver()
    private var socket: BluetoothSocket? = null
    private var address: String? = null

    fun setAddress(value: String?) {
        address = value
        close()
    }

    fun listBondedDevices(): List<Map<String, String>> {
        if (!hasConnectPermission()) return emptyList()
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        return try {
            adapter.bondedDevices.orEmpty().map { device ->
                mapOf(
                    "id" to device.address,
                    "name" to (device.name ?: device.address),
                    "address" to device.address,
                    "type" to "BLUETOOTH"
                )
            }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    override fun initialize(): Boolean {
        if (!hasConnectPermission()) return false
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        if (!adapter.isEnabled) return false
        val device = resolveDevice(adapter) ?: return false
        return try {
            close()
            socket = device.createRfcommSocketToServiceRecord(SPP_UUID).apply {
                adapter.cancelDiscovery()
                connect()
            }
            escPos.setOutputStream(socket?.outputStream)
            address = device.address
            true
        } catch (_: Exception) {
            // بعض الطابعات تحتاج قناة انعكاس غير آمنة
            try {
                @Suppress("DEPRECATION")
                val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                socket = (m.invoke(device, 1) as BluetoothSocket).apply { connect() }
                escPos.setOutputStream(socket?.outputStream)
                address = device.address
                true
            } catch (_: Exception) {
                close()
                false
            }
        }
    }

    private fun resolveDevice(adapter: BluetoothAdapter): BluetoothDevice? {
        address?.let { return adapter.getRemoteDevice(it) }
        val bonded = try {
            adapter.bondedDevices.orEmpty().toList()
        } catch (_: SecurityException) {
            emptyList()
        }
        bonded.firstOrNull { isLikelyPrinter(it.name) }?.let { return it }
        // إن وُجد جهاز مقترن واحد فقط، جرّبه
        if (bonded.size == 1) return bonded.first()
        return null
    }

    private fun isLikelyPrinter(name: String?): Boolean {
        if (name.isNullOrBlank()) return false
        val n = name.lowercase()
        return PRINTER_HINTS.any { n.contains(it) }
    }

    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    override fun printText(text: String) = escPos.printText(text)
    override fun printImage(bytes: ByteArray?) = escPos.printImage(bytes)
    override fun printQR(data: String) = escPos.printQR(data)
    override fun printBarcode(data: String) = escPos.printBarcode(data)
    override fun feed(lines: Int) = escPos.feed(lines)
    override fun cut() = escPos.cut()
    override fun openDrawer() = escPos.openDrawer()
    override fun isReady() = socket?.isConnected == true && escPos.isReady()
    override fun name() = "BLUETOOTH"

    private fun close() {
        escPos.setOutputStream(null)
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
    }

    private companion object {
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        val PRINTER_HINTS = listOf(
            "printer", "print", "pos", "thermal", "receipt", "escpos", "esc/pos",
            "xp-", "xprinter", "mtp", "rpp", "innerprinter", "blueooth", "bluetooth printer",
            "gt-", "gs-", "sprt", "zj-", "woosim", "bixolon", "epson", "citizen", "star",
            "sunmi", "imin", "urovo", "telpo", "newland", "pax", "hoin", "gprinter", "rongta"
        )
    }
}
