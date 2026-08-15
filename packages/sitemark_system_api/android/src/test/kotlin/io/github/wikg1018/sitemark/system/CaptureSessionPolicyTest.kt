package io.github.wikg1018.sitemark.system

import android.content.Intent
import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.mockito.ArgumentMatchers.anyString

class CaptureSessionPolicyTest {
    @Test
    fun clearPendingUsesCommitNotApply() {
        val editor = mock(SharedPreferences.Editor::class.java)
        `when`(editor.remove(anyString())).thenReturn(editor)
        `when`(editor.commit()).thenReturn(true)

        assertTrue(CaptureSessionPolicy.clearPending(editor))

        verify(editor).remove(CaptureSessionPolicy.KEY_CAPTURE_ID)
        verify(editor).remove(CaptureSessionPolicy.KEY_CAPTURE_PATH)
        verify(editor).commit()
        verify(editor, never()).apply()
    }

    @Test
    fun uriGrantFlagsAreReadAndWrite() {
        assertEquals(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            CaptureSessionPolicy.URI_GRANT_FLAGS,
        )
    }

    @Test
    fun revokeOnlyWhenACaptureIdIsPresent() {
        assertTrue(CaptureSessionPolicy.shouldRevoke("capture-1"))
        assertFalse(CaptureSessionPolicy.shouldRevoke(null))
        assertFalse(CaptureSessionPolicy.shouldRevoke(""))
    }
}
