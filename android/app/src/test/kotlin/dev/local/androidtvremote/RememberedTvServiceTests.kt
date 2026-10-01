package dev.local.androidtvremote

import dev.local.androidtvremote.discovery.RememberedTvService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RememberedTvServiceTests {
    @Test
    fun `parses the saved Google TV service locator`() {
        val key = "local.|_androidtvremote2._tcp|Living Room TV"
        assertEquals(RememberedTvService(key, "Living Room TV"), RememberedTvService.parse(key))
    }

    @Test
    fun `accepts Android NSD boundary dot variants and preserves the original locator`() {
        listOf(
            "local.|._androidtvremote2._tcp|LivingRoom",
            "local.|_androidtvremote2._tcp.|LivingRoom",
            "local.|._androidtvremote2._tcp.|LivingRoom",
        ).forEach { key ->
            assertEquals(RememberedTvService(key, "LivingRoom"), RememberedTvService.parse(key))
        }
    }

    @Test
    fun `preserves Unicode pipes and whitespace in the instance name`() {
        val name = " 客廳電視📺|Android|TV "
        val key = "local.|_androidtvremote2._tcp|$name"
        assertEquals(RememberedTvService(key, name), RememberedTvService.parse(key))
    }

    @Test
    fun `rejects absent malformed and manual legacy locators`() {
        listOf(
            null,
            "",
            "192.168.31.38",
            "manual:192.168.31.38",
            "Living Room TV",
            "local.|_androidtvremote2._tcp",
            "local.|_androidtvremote2._tcp|",
            "local.|_androidtvremote2._tcp| \t\n",
        ).forEach { key -> assertNull(key, RememberedTvService.parse(key)) }
    }

    @Test
    fun `rejects other domains and service types without normalizing the key`() {
        listOf(
            "local|_androidtvremote2._tcp|TV",
            "LOCAL.|_androidtvremote2._tcp|TV",
            "example.|_androidtvremote2._tcp|TV",
            "local.|.._androidtvremote2._tcp|TV",
            "local.|_androidtvremote2._tcp..|TV",
            "local.|_androidtvremote2.._tcp|TV",
            "local.|_androidtvremote._tcp|TV",
            "local.|_airplay._tcp|TV",
            "local.|._airplay._tcp.|TV",
            "local.|_androidtvremote2._tcp.local.|TV",
            "local.||TV",
        ).forEach { key -> assertNull(key, RememberedTvService.parse(key)) }
    }
}
