package io.github.wikg1018.sitemark.system

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mockito.Mockito.`when`
import org.mockito.Mockito.doReturn
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import org.mockito.Mockito.spy
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt

class CaptureContentProviderTest {
    @get:Rule
    val temporary = TemporaryFolder()

    @Test
    fun readWriteReopenDoesNotRequestTruncationOfCameraOriginal() {
        assertOpenMode(
            "rw",
            ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_READ_WRITE,
        )
    }

    @Test
    fun explicitReadWriteTruncateStillReplacesTheOriginal() {
        assertOpenMode(
            "rwt",
            ParcelFileDescriptor.MODE_CREATE or
                ParcelFileDescriptor.MODE_READ_WRITE or
                ParcelFileDescriptor.MODE_TRUNCATE,
        )
    }

    @Test
    fun readOnlyOpenDoesNotCreateOrTruncateTheOriginal() {
        assertOpenMode("r", ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun assertOpenMode(mode: String, expectedFlags: Int) {
        val context = mock(Context::class.java)
        `when`(context.filesDir).thenReturn(temporary.root)
        val uri = mock(Uri::class.java)
        `when`(uri.pathSegments).thenReturn(listOf("capture", "capture-1"))
        val provider = spy(CaptureContentProvider())
        doReturn(context).`when`(provider).context
        val target = File(File(temporary.root, "originals"), "capture-1.jpg")
        target.parentFile!!.mkdirs()
        target.writeBytes(byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte()))
        val descriptor = mock(ParcelFileDescriptor::class.java)
        mockStatic(ParcelFileDescriptor::class.java).use { descriptors ->
            descriptors.`when`<ParcelFileDescriptor> {
                ParcelFileDescriptor.open(any(File::class.java), anyInt())
            }.thenAnswer { invocation ->
                assertEquals(target, invocation.getArgument<File>(0))
                assertEquals(expectedFlags, invocation.getArgument<Int>(1))
                descriptor
            }
            assertSame(descriptor, provider.openFile(uri, mode))
            descriptors.verify { ParcelFileDescriptor.open(target, expectedFlags) }
        }
    }
}
