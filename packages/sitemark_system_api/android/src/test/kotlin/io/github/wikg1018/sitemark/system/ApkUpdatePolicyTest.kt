package io.github.wikg1018.sitemark.system

import org.junit.Assert.assertThrows
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.security.MessageDigest

class ApkUpdatePolicyTest {
    @get:Rule val temporary = TemporaryFolder()
    private val installed = ApkIdentity("io.github.wikg1018.sitemark", "1.0.31", 2046, setOf("trusted"))
    private val candidate = installed.copy(versionName = "1.0.32", versionCode = 2047)

    @Test fun acceptsNewerSameSigner() { validateApkIdentity(installed, candidate, "1.0.32") }
    @Test fun rejectsAnotherPackage() { rejects(candidate.copy(packageName = "other")) }
    @Test fun rejectsDifferentVersion() { rejects(candidate.copy(versionName = "9.9.9")) }
    @Test fun rejectsDowngradeVariant() { rejects(candidate.copy(versionCode = 47)) }
    @Test fun rejectsForeignSigner() { rejects(candidate.copy(signers = setOf("foreign"))) }
    @Test fun rejectsMissingSigner() { rejects(candidate.copy(signers = emptySet())) }
    @Test fun acceptsVerifiedSigningRotation() {
        validateApkIdentity(installed, candidate.copy(signers = setOf("new"), signingHistory = setOf("trusted", "new")), "1.0.32")
    }
    @Test fun rejectsUnrelatedRotation() {
        rejects(candidate.copy(signers = setOf("new"), signingHistory = setOf("other", "new")))
    }
    @Test fun acceptsVerifiedPrivateFile() {
        val file = updateFile()
        assertEquals(file.canonicalFile, verifiedUpdateFile(temporary.root, file.path, digest(file)))
    }
    @Test fun rejectsFileOutsideUpdateDirectory() {
        val file = temporary.newFile("sitemark-v1.0.32-universal.apk").apply { writeText("apk") }
        assertThrows(IllegalArgumentException::class.java) { verifiedUpdateFile(temporary.root, file.path, digest(file)) }
    }
    @Test fun rejectsPartialFilename() {
        val file = updateFile("sitemark-v1.0.32-universal.apk.part")
        assertThrows(IllegalArgumentException::class.java) { verifiedUpdateFile(temporary.root, file.path, digest(file)) }
    }
    @Test fun rejectsEmptyFile() {
        val file = updateFile().apply { writeBytes(byteArrayOf()) }
        assertThrows(IllegalArgumentException::class.java) { verifiedUpdateFile(temporary.root, file.path, digest(file)) }
    }
    @Test fun rejectsChangedBytes() {
        val file = updateFile()
        val original = digest(file)
        file.appendText("changed")
        assertThrows(IllegalArgumentException::class.java) { verifiedUpdateFile(temporary.root, file.path, original) }
    }
    private fun updateFile(name: String = "sitemark-v1.0.32-universal.apk"): File =
        File(temporary.newFolder("sitemark-updates"), name).apply { writeText("test bytes") }
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun rejects(value: ApkIdentity) {
        assertThrows(IllegalArgumentException::class.java) { validateApkIdentity(installed, value, "1.0.32") }
    }
}
