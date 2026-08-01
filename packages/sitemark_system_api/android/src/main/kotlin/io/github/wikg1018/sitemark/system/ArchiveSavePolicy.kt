package io.github.wikg1018.sitemark.system

import java.io.File
import java.io.OutputStream

internal object ArchiveSavePolicy {
    fun validateSource(sourcePath: String, dataDirectory: File): File {
        val source = File(sourcePath).canonicalFile
        val privateRoot = dataDirectory.canonicalFile
        require(source.path.startsWith(privateRoot.path + File.separator)) {
            "Backup source must be in app-private storage"
        }
        require(source.extension.equals("zip", ignoreCase = true)) {
            "Backup source must be a ZIP archive"
        }
        require(source.isFile && source.length() > 0L) {
            "Backup source is empty or missing"
        }
        return source
    }

    fun normalizeSuggestedName(suggestedName: String): String {
        val name = suggestedName.trim()
        require(name.endsWith(".zip", ignoreCase = true)) {
            "Backup filename must end with .zip"
        }
        require(name.length > 4 && !name.contains(Regex("[\\p{Cc}/\\\\:*?\"<>|]"))) {
            "Invalid backup filename"
        }
        return name
    }

    fun copy(source: File, destination: OutputStream) {
        source.inputStream().buffered().use { input ->
            destination.buffered().use { output -> input.copyTo(output) }
        }
    }
}
