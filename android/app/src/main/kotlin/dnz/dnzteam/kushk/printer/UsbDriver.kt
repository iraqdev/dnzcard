package dnz.dnzteam.kushk.printer

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbManager
import android.os.Build
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** USB-host ESC/POS transport. Android grants per-device access via UsbManager permission. */
class UsbDriver(private val context: Context) : PrinterDriver {
    private val manager = context.getSystemService(UsbManager::class.java)
    private var connection: UsbDeviceConnection? = null
    private var endpoint: UsbEndpoint? = null
    private var claimedInterface: android.hardware.usb.UsbInterface? = null
    private var ready = false
    private var selectedDeviceName: String? = null

    fun setDeviceName(value: String?) {
        selectedDeviceName = value
        close()
    }

    fun listDevices(): List<Map<String, String>> {
        return manager.deviceList.values.mapNotNull { device ->
            if (!hasBulkOut(device)) return@mapNotNull null
            mapOf(
                "id" to device.deviceName,
                "name" to (device.productName?.takeIf { it.isNotBlank() }
                    ?: "USB ${device.vendorId}:${device.productId}"),
                "address" to device.deviceName,
                "type" to "USB",
                "hasPermission" to manager.hasPermission(device).toString()
            )
        }
    }

    override fun initialize(): Boolean {
        close()
        val device = resolveDevice() ?: return false
        if (!manager.hasPermission(device)) {
            if (!requestPermissionBlocking(device)) return false
        }
        val usbInterface = (0 until device.interfaceCount)
            .map(device::getInterface)
            .firstOrNull { iface ->
                (0 until iface.endpointCount).any {
                    iface.getEndpoint(it).type == UsbConstants.USB_ENDPOINT_XFER_BULK
                }
            } ?: return false
        endpoint = (0 until usbInterface.endpointCount).map(usbInterface::getEndpoint)
            .firstOrNull {
                it.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    it.direction == UsbConstants.USB_DIR_OUT
            } ?: return false
        connection = manager.openDevice(device)?.takeIf {
            it.claimInterface(usbInterface, true)
        }
        claimedInterface = if (connection != null) usbInterface else null
        ready = connection != null
        if (ready) selectedDeviceName = device.deviceName
        return ready
    }

    private fun resolveDevice(): UsbDevice? {
        val candidates = manager.deviceList.values.filter(::hasBulkOut)
        if (candidates.isEmpty()) return null
        selectedDeviceName?.let { name ->
            candidates.firstOrNull { it.deviceName == name }?.let { return it }
        }
        candidates.firstOrNull { manager.hasPermission(it) }?.let { return it }
        return candidates.firstOrNull()
    }

    private fun hasBulkOut(device: UsbDevice): Boolean {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            for (e in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT
                ) {
                    return true
                }
            }
        }
        return false
    }

    private fun requestPermissionBlocking(device: UsbDevice): Boolean {
        val latch = CountDownLatch(1)
        val granted = AtomicBoolean(false)
        val action = ACTION_USB_PERMISSION + ".${context.packageName}"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action != action) return
                granted.set(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
                latch.countDown()
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val permissionIntent = PendingIntent.getBroadcast(
            context,
            device.deviceId,
            Intent(action),
            flags
        )
        manager.requestPermission(device, permissionIntent)
        try {
            latch.await(20, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
        }
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        return granted.get() && manager.hasPermission(device)
    }

    override fun printText(text: String) = send(EscPosDriver().bytesForText(text))
    override fun printImage(bytes: ByteArray?): Boolean {
        if (bytes == null) return false
        val raster = EscPosRaster.pngToRaster(bytes) ?: return false
        return send(raster)
    }

    override fun printQR(data: String) = send(EscPosDriver().bytesForQr(data))
    override fun printBarcode(data: String) = send(EscPosDriver().bytesForBarcode(data))
    override fun feed(lines: Int) = send(EscPosDriver().bytesForFeed(lines))
    override fun cut() = send(EscPosDriver().bytesForCut())
    override fun openDrawer() = send(EscPosDriver().bytesForDrawer())
    override fun isReady() = ready
    override fun name() = "USB"

    private fun send(bytes: ByteArray): Boolean {
        val sent = connection?.bulkTransfer(endpoint, bytes, bytes.size, 5_000) ?: -1
        return sent == bytes.size
    }

    private fun close() {
        try {
            claimedInterface?.let { connection?.releaseInterface(it) }
            connection?.close()
        } catch (_: Exception) {
        }
        connection = null
        endpoint = null
        claimedInterface = null
        ready = false
    }

    private companion object {
        const val ACTION_USB_PERMISSION = "dnz.dnzteam.kushk.USB_PERMISSION"
    }
}
