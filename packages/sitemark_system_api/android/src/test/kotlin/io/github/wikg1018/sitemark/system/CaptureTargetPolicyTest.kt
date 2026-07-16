package io.github.wikg1018.sitemark.system

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CaptureTargetPolicyTest {
    @Test
    fun `uses capture id as deterministic jpeg file name`() {
        assertEquals("2f90c1a8-1234.jpg", CaptureTargetPolicy.fileName("2f90c1a8-1234"))
    }

    @Test
    fun `rejects ids that could escape the private originals directory`() {
        assertThrows(IllegalArgumentException::class.java) {
            CaptureTargetPolicy.fileName("../outside")
        }
    }

    @Test
    fun `only a non-empty target is considered captured during recovery`() {
        assertEquals(
            RecoveryDisposition.CAPTURED,
            CaptureTargetPolicy.recoveryDisposition(exists = true, length = 512),
        )
        assertEquals(
            RecoveryDisposition.CANCELLED,
            CaptureTargetPolicy.recoveryDisposition(exists = true, length = 0),
        )
        assertEquals(
            RecoveryDisposition.CANCELLED,
            CaptureTargetPolicy.recoveryDisposition(exists = false, length = 512),
        )
    }
}
