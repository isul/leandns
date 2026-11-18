package com.leandns.tool.udp

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.wifi.WifiManager
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.util.Collections
import kotlin.math.max

class LeanDnsUdpClient(private val context: Context) {

    fun discover(waitMs: Long = 2_000L): List<ProtocolReply> =
        sendRecv(LeanDnsProtocol.discoverPayload(), waitMs)

    fun set(
        token: String,
        ip: String,
        netmask: String,
        gateway: String,
        waitMs: Long = 3_000L,
    ): List<ProtocolReply> =
        sendRecv(LeanDnsProtocol.setPayload(token, ip, netmask, gateway), waitMs)

    fun sendRecv(payload: String, waitMs: Long): List<ProtocolReply> {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifi.createMulticastLock("leandns-tool").apply {
            setReferenceCounted(false)
            acquire()
        }

        val socket = DatagramSocket(null).apply {
            reuseAddress = true
            broadcast = true
            soTimeout = 300
            bind(InetSocketAddress(0))
        }

        try {
            val data = payload.toByteArray(Charsets.UTF_8)
            for (bcast in broadcastTargets()) {
                runCatching {
                    val packet = DatagramPacket(
                        data,
                        data.size,
                        InetAddress.getByName(bcast),
                        LeanDnsProtocol.PORT,
                    )
                    socket.send(packet)
                }
            }

            val deadline = System.nanoTime() + waitMs * 1_000_000L
            val out = LinkedHashMap<String, ProtocolReply>()
            val buf = ByteArray(4096)

            while (System.nanoTime() < deadline) {
                val remainingMs = max(1L, (deadline - System.nanoTime()) / 1_000_000L)
                socket.soTimeout = remainingMs.coerceAtMost(300L).toInt()
                try {
                    val packet = DatagramPacket(buf, buf.size)
                    socket.receive(packet)
                    val from = packet.address.hostAddress ?: continue
                    val text = String(packet.data, 0, packet.length, Charsets.UTF_8).trim()
                    val key = "$from|$text"
                    if (key in out) continue
                    out[key] = LeanDnsProtocol.parseReply(from, text)
                } catch (_: SocketTimeoutException) {
                    // keep listening until deadline
                }
            }
            return out.values.toList()
        } finally {
            runCatching { socket.close() }
            runCatching { if (lock.isHeld) lock.release() }
        }
    }

    private fun broadcastTargets(): List<String> {
        val targets = linkedSetOf("255.255.255.255")
        targets += interfaceBroadcasts()
        targets += connectivityBroadcasts()
        return targets.toList()
    }

    private fun interfaceBroadcasts(): List<String> {
        val out = mutableListOf<String>()
        runCatching {
            val ifaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (iface in ifaces) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in Collections.list(iface.inetAddresses)) {
                    if (addr !is Inet4Address || addr.isLoopbackAddress) continue
                    val prefix = iface.interfaceAddresses
                        .firstOrNull { it.address == addr }
                        ?.networkPrefixLength
                        ?.toInt()
                        ?: continue
                    ipv4Broadcast(addr.hostAddress ?: continue, prefix)?.let { out += it }
                }
            }
        }
        return out
    }

    private fun connectivityBroadcasts(): List<String> {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return emptyList()
        val props: LinkProperties = cm.getLinkProperties(network) ?: return emptyList()
        val out = mutableListOf<String>()
        for (link in props.linkAddresses) {
            val addr = link.address
            if (addr !is Inet4Address || addr.isLoopbackAddress) continue
            ipv4Broadcast(addr.hostAddress ?: continue, link.prefixLength)?.let { out += it }
        }
        return out
    }

    private fun ipv4Broadcast(ip: String, prefix: Int): String? {
        if (prefix !in 0..32) return null
        val parts = ip.split('.').mapNotNull { it.toIntOrNull() }
        if (parts.size != 4) return null
        var host = 0
        for (p in parts) {
            if (p !in 0..255) return null
            host = (host shl 8) or p
        }
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        val bcast = (host and mask) or mask.inv()
        return listOf(
            (bcast ushr 24) and 0xff,
            (bcast ushr 16) and 0xff,
            (bcast ushr 8) and 0xff,
            bcast and 0xff,
        ).joinToString(".")
    }
}
