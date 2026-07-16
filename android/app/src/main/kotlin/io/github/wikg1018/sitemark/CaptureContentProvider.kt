package io.github.wikg1018.sitemark

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

class CaptureContentProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "image/jpeg"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val file = captureFile(uri)
        file.parentFile?.mkdirs()
        val flags = when (mode) {
            "r" -> ParcelFileDescriptor.MODE_READ_ONLY
            "w", "wt" ->
                ParcelFileDescriptor.MODE_CREATE or
                    ParcelFileDescriptor.MODE_TRUNCATE or
                    ParcelFileDescriptor.MODE_WRITE_ONLY
            "rw", "rwt" ->
                ParcelFileDescriptor.MODE_CREATE or
                    ParcelFileDescriptor.MODE_TRUNCATE or
                    ParcelFileDescriptor.MODE_READ_WRITE
            else -> throw FileNotFoundException("Unsupported mode: $mode")
        }
        return ParcelFileDescriptor.open(file, flags)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = captureFile(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns, 1)
        val row = cursor.newRow()
        columns.forEach { column ->
            when (column) {
                OpenableColumns.DISPLAY_NAME -> row.add(file.name)
                OpenableColumns.SIZE -> row.add(file.length())
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("Insert is not supported")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException("Update is not supported")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        return if (captureFile(uri).delete()) 1 else 0
    }

    private fun captureFile(uri: Uri): File {
        if (uri.pathSegments.size != 2 || uri.pathSegments.first() != "capture") {
            throw FileNotFoundException("Unknown capture URI")
        }
        val captureId = uri.pathSegments.last()
        val fileName = CaptureTargetPolicy.fileName(captureId)
        val appContext = context ?: throw FileNotFoundException("Provider unavailable")
        return File(File(appContext.filesDir, "originals"), fileName)
    }
}
