package io.github.wikg1018.sitemark.system

import java.io.File
import java.security.MessageDigest

/** Only a complete, verified file inside our dedicated private cache is shared. */
internal fun verifiedUpdateFile(cacheDirectory: File, apkPath: String, expectedSha256: String): File {
    val directory = File(cacheDirectory, "sitemark-updates").canonicalFile
    val file = File(apkPath).canonicalFile
    require(file.parentFile == directory && file.name.matches(Regex("sitemark-v[0-9]+\\.[0-9]+\\.[0-9]+-(arm64|universal)\\.apk")))
    require(file.isFile && file.length() in 1..(200L * 1024 * 1024))
    require(expectedSha256.matches(Regex("[0-9a-f]{64}")))
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val bytes = ByteArray(64 * 1024)
        while (true) {
            val count = input.read(bytes)
            if (count < 0) break
            digest.update(bytes, 0, count)
        }
    }
    require(digest.digest().joinToString("") { "%02x".format(it) } == expectedSha256)
    return file
}

internal data class ApkIdentity(
    val packageName: String,
    val versionName: String?,
    val versionCode: Long,
    val signers: Set<String>,
    val signingHistory: Set<String> = emptySet(),
)

internal fun validateApkIdentity(installed: ApkIdentity, candidate: ApkIdentity, expectedVersion: String) {
    require(candidate.packageName == installed.packageName) { "package_mismatch" }
    require(candidate.versionName == expectedVersion) { "version_mismatch" }
    require(candidate.versionCode > installed.versionCode) { "version_not_newer" }
    require(candidate.signers.isNotEmpty() && installed.signers.isNotEmpty()) { "missing_signer" }
    val sameSigners = candidate.signers == installed.signers
    val validRotation = candidate.signers.size == 1 && installed.signers.size == 1 &&
        installed.signers.single() in candidate.signingHistory
    require(sameSigners || validRotation) { "signature_mismatch" }
}
