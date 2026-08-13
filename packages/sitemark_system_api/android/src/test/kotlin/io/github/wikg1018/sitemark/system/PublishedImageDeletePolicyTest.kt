package io.github.wikg1018.sitemark.system

import android.provider.MediaStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PublishedImageDeletePolicyTest {
    @Test
    fun publishAndDeleteShareTheSiteMarkRelativePath() {
        assertEquals("Pictures/SiteMark/", PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH)
        assertEquals("media", MediaStore.AUTHORITY)
    }

    @Test
    fun allowsOnlyContentMediaStoreRowsUnderSiteMarkPictures() {
        assertTrue(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = MediaStore.AUTHORITY,
                relativePath = PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH,
            ),
        )
        assertTrue(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = "media",
                relativePath = "Pictures/SiteMark",
            ),
        )
        assertTrue(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = "media",
                relativePath = "Pictures/SiteMark/archive/",
            ),
        )
    }

    @Test
    fun rejectsEverythingOutsideTheAllowlist() {
        assertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "file",
                authority = MediaStore.AUTHORITY,
                relativePath = PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH,
            ),
        )
        assertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = "com.android.providers.media.documents",
                relativePath = PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH,
            ),
        )
        assertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = MediaStore.AUTHORITY,
                relativePath = "Pictures/Camera/",
            ),
        )
        assertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = MediaStore.AUTHORITY,
                relativePath = "Pictures/SiteMarkBackup/",
            ),
        )
        assertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = MediaStore.AUTHORITY,
                relativePath = null,
            ),
        )
        assertFalse(
            PublishedImageDeletePolicy.allowsDelete(
                scheme = "content",
                authority = "downloads",
                relativePath = PublishedImageDeletePolicy.PUBLISHED_RELATIVE_PATH,
            ),
        )
    }
}
