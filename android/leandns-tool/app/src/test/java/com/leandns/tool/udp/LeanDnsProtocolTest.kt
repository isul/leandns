package com.leandns.tool.udp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LeanDnsProtocolTest {
    @Test
    fun discoverPayload() {
        assertEquals("LEANDNS1|DISCOVER", LeanDnsProtocol.discoverPayload())
    }

    @Test
    fun setPayloadIncludesFields() {
        val p = LeanDnsProtocol.setPayload("tok", "192.168.1.250", "255.255.255.0", "192.168.1.1")
        assertTrue(p.startsWith("LEANDNS1|SET|"))
        assertTrue(p.contains("\"ipaddr\":\"192.168.1.250\""))
        assertTrue(p.contains("\"gateway\":\"192.168.1.1\""))
        assertTrue(p.contains("\"token\":\"tok\""))
    }

    @Test
    fun parseDiscoverOk() {
        val json =
            """{"name":"LeanDNS","version":"1","ipaddr":"192.168.0.250","netmask":"255.255.255.0","gateway":"192.168.0.1","mac":"aa:bb","token_required":false,"set_enabled":true}"""
        val reply = LeanDnsProtocol.parseReply("10.0.0.1", "LEANDNS1|DISCOVER_OK|$json")
        val info = reply as ProtocolReply.DiscoverInfo
        assertEquals("192.168.0.250", info.ipAddr)
        assertEquals(false, info.tokenRequired)
        assertEquals(true, info.setEnabled)
        assertEquals("불필요", info.tokenLabel)
        assertEquals("http://192.168.0.250/leandns/", info.uiUrl)
    }

    @Test
    fun parseDiscoverSetDisabled() {
        val json =
            """{"name":"LeanDNS","version":"1","ipaddr":"192.168.0.250","netmask":"255.255.255.0","gateway":"192.168.0.1","mac":"aa:bb","token_required":true,"set_enabled":false}"""
        val info = LeanDnsProtocol.parseReply("10.0.0.1", "LEANDNS1|DISCOVER_OK|$json")
            as ProtocolReply.DiscoverInfo
        assertEquals("UDP IP 변경 끔", info.tokenLabel)
    }

    @Test
    fun parseDiscoverLegacyWithoutSetEnabled() {
        val json =
            """{"name":"LeanDNS","version":"1.0.0","ipaddr":"192.168.200.250","netmask":"255.255.0.0","gateway":"192.168.200.1","mac":"aa:bb","token_required":true}"""
        val info = LeanDnsProtocol.parseReply("192.168.200.250", "LEANDNS1|DISCOVER_OK|$json")
            as ProtocolReply.DiscoverInfo
        assertEquals(null, info.setEnabled)
        assertEquals("구버전 데몬 · 장치 업데이트 필요", info.tokenLabel)
    }

    @Test
    fun parseSetOk() {
        val reply = LeanDnsProtocol.parseReply("10.0.0.1", "LEANDNS1|SET_OK|{\"ok\":true}")
        assertTrue(reply is ProtocolReply.SetOk)
    }
}
