package io.github.wikg1018.sitemark.system

import android.provider.MediaStore

/**
 * Allowlist for [SiteMarkSystemApi.deletePublishedImage]. Only MediaStore
 * image rows that SiteMark itself published under [PUBLISHED_RELATIVE_PATH]
 * may be deleted.
 */
internal object PublishedImageDeletePolicy {
    const val PUBLISHED_RELATIVE_PATH = "Pictures/SiteMark/"

    fun allowsDelete(scheme: String?, authority: String?, relativePath: String?): Boolean =
        allowsUri(scheme, authority) && allowsRelativePath(relativePath)

    fun allowsUri(scheme: String?, authority: String?): Boolean =
        scheme == "content" && authority == MediaStore.AUTHORITY

    fun allowsRelativePath(relativePath: String?): Boolean {
        val path = relativePath ?: return false
        return path.startsWith(PUBLISHED_RELATIVE_PATH) ||
            path == PUBLISHED_RELATIVE_PATH.trimEnd('/')
    }
}
