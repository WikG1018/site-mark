package io.github.wikg1018.sitemark.system

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

internal object GalleryImportPolicy {
    const val MAX_IMAGES = 20
    const val MAX_BYTES = 100L * 1024 * 1024

    fun parseExifTime(value: String?, offset: String?, localZone: TimeZone = TimeZone.getDefault()): Long? {
        if (value == null || !Regex("[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}").matches(value)) return null
        val zone = if (offset != null && Regex("[+-](0[0-9]|1[0-4]):[0-5][0-9]").matches(offset)) {
            TimeZone.getTimeZone("GMT$offset")
        } else localZone
        val format = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).apply {
            isLenient = false
            timeZone = zone
        }
        val position = ParsePosition(0)
        val date = format.parse(value, position) ?: return null
        return date.time.takeIf { position.index == value.length && value.substring(0, 4).toInt() in 1900..2100 }
    }

    fun copyAtomically(input: InputStream, target: File, limit: Long = MAX_BYTES, validate: (File) -> Unit) {
        check(!target.exists()) { "original_exists" }
        val temporary = File(target.parentFile, target.name + ".part")
        try {
            input.use { source ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val size = source.read(buffer)
                        if (size < 0) break
                        total += size
                        require(total <= limit) { "image_too_large" }
                        output.write(buffer, 0, size)
                    }
                    require(total > 0) { "empty_image" }
                    output.fd.sync()
                }
            }
            validate(temporary)
            check(temporary.renameTo(target)) { "copy_failed" }
        } finally { temporary.delete() }
    }
}
