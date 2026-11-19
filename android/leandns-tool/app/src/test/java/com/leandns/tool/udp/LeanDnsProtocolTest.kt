package com.leandns.tool.udp

import com.leandns.tool.TestStringLookup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LeanDnsProtocolTest {
    private val strings = TestStringLookup

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
        val reply = LeanDnsProtocol.parseReply("10.0.0.1", "LEANDNS1|DISCOVER_OK|$json", strings)
        val info = reply as ProtocolReply.DiscoverInfo
        assertEquals("192.168.0.250", info.ipAddr)
        assertEquals(false, info.tokenRequired)
        assertEquals(true, info.setEnabled)
        assertEquals("Not required", info.tokenLabel(strings))
        assertEquals("http://192.168.0.250/leandns/", info.uiUrl)
    }

    @Test
    fun parseDiscoverSetDisabled() {
        val json =
            """{"name":"LeanDNS","version":"1","ipaddr":"192.168.0.250","netmask":"255.255.255.0","gateway":"192.168.0.1","mac":"aa:bb","token_required":true,"set_enabled":false}"""
        val info = LeanDnsProtocol.parseReply("10.0.0.1", "LEANDNS1|DISCOVER_OK|$json", strings)
            as ProtocolReply.DiscoverInfo
        assertEquals("UDP IP change off", info.tokenLabel(strings))
    }

    @Test
    fun parseDiscoverLegacyWithoutSetEnabled() {
        val json =
            """{"name":"LeanDNS","version":"1.0.0","ipaddr":"192.168.200.250","netmask":"255.255.0.0","gateway":"192.168.200.1","mac":"aa:bb","token_required":true}"""
        val info = LeanDnsProtocol.parseReply("192.168.200.250", "LEANDNS1|DISCOVER_OK|$json", strings)
            as ProtocolReply.DiscoverInfo
        assertEquals(null, info.setEnabled)
        assertEquals("Legacy daemon · update device", info.tokenLabel(strings))
    }

    @Test
    fun parseSetOk() {
        val reply = LeanDnsProtocol.parseReply("10.0.0.1", "LEANDNS1|SET_OK|{\"ok\":true}", strings)
        assertTrue(reply is ProtocolReply.SetOk)
    }

    @Test
    fun parseSetErrExtractsMessage() {
        val reply = LeanDnsProtocol.parseReply(
            "10.0.0.1",
            """LEANDNS1|SET_ERR|{"ok":false,"error":"다른 네트워크 변경이 진행 중입니다."}""",
            strings,
        ) as ProtocolReply.SetErr
        assertEquals("다른 네트워크 변경이 진행 중입니다.", reply.message)
    }

    @Test
    fun formatSetFailureIncludesGuidance() {
        val reply = LeanDnsProtocol.parseReply(
            "10.0.0.1",
            """LEANDNS1|SET_ERR|{"ok":false,"error":"다른 네트워크 변경이 진행 중입니다."}""",
            strings,
        )
        val text = LeanDnsProtocol.formatSetFailure(listOf(reply), strings)
        assertTrue(text.contains("다른 네트워크 변경이 진행 중입니다."))
        assertTrue(text.contains("120 seconds"))
    }

    @Test
    fun formatSetFailureNoReply() {
        val text = LeanDnsProtocol.formatSetFailure(emptyList(), strings)
        assertTrue(text.contains("No device replied."))
    }

    @Test
    fun formatSetSuccessMentionsConfirm() {
        val text = LeanDnsProtocol.formatSetSuccess("192.168.0.250", strings)
        assertTrue(text.contains("192.168.0.250"))
        assertTrue(text.contains("120 seconds"))
        assertTrue(text.contains("confirm"))
    }
}
