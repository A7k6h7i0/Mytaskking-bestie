package com.mytaskking.mytaskking_mobile

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterFragmentActivity
import java.io.IOException

object CallRecordingStorageHelper {
    private val audioExtensions = setOf(
        "m4a", "mp3", "aac", "wav", "amr", "mp4", "3gp", "ogg", "opus",
    )

    fun isAudioName(name: String?): Boolean {
        if (name.isNullOrBlank()) return false
        val ext = name.substringAfterLast('.', "").lowercase()
        return ext in audioExtensions
    }

    fun pickFolderResult(activity: FlutterFragmentActivity, treeUri: Uri): Map<String, Any?> {
        val flags = android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
            android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            activity.contentResolver.takePersistableUriPermission(treeUri, flags)
        } catch (_: SecurityException) {
            try {
                activity.contentResolver.takePersistableUriPermission(
                    treeUri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {}
        }

        val root = DocumentFile.fromTreeUri(activity, treeUri)
        val count = if (root != null) countAudioFiles(root) else 0
        return mapOf(
            "treeUri" to treeUri.toString(),
            "displayName" to (root?.name ?: treeUri.lastPathSegment ?: "Folder"),
            "audioCount" to count,
        )
    }

    fun pickFileResult(activity: FlutterFragmentActivity, fileUri: Uri): Map<String, Any?> {
        try {
            activity.contentResolver.takePersistableUriPermission(
                fileUri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {}
        val doc = DocumentFile.fromSingleUri(activity, fileUri)
        return mapOf(
            "fileUri" to fileUri.toString(),
            "displayName" to (doc?.name ?: fileUri.lastPathSegment ?: "recording"),
            "modifiedMs" to (doc?.lastModified() ?: 0L),
            "size" to (doc?.length() ?: 0L),
        )
    }

    fun verifyTreeAccess(context: Context, treeUriString: String): Boolean {
        return try {
            val root = DocumentFile.fromTreeUri(context, Uri.parse(treeUriString))
                ?: return false
            root.canRead() && root.exists()
        } catch (_: SecurityException) {
            false
        }
    }

    fun countAudioInTree(context: Context, treeUriString: String): Int {
        val uri = Uri.parse(treeUriString)
        val root = DocumentFile.fromTreeUri(context, uri) ?: return 0
        return countAudioFiles(root)
    }

    private fun countAudioFiles(root: DocumentFile): Int {
        var count = 0
        fun walk(dir: DocumentFile) {
            for (child in dir.listFiles()) {
                if (child.isDirectory) {
                    walk(child)
                } else if (child.isFile && isAudioName(child.name)) {
                    count++
                }
            }
        }
        walk(root)
        return count
    }

    fun findNewestRecording(
        context: Context,
        treeUri: String?,
        modifiedAfterMs: Long,
        skipUri: String?,
        skipModifiedMs: Long,
    ): Map<String, Any?>? {
        treeUri?.let {
            findNewestInTree(context, it, modifiedAfterMs, skipUri, skipModifiedMs)?.let { hit ->
                return hit
            }
        }
        return findNewestInMediaStore(context, modifiedAfterMs, skipUri, skipModifiedMs)
    }

    private fun findNewestInTree(
        context: Context,
        treeUriString: String,
        modifiedAfterMs: Long,
        skipUri: String?,
        skipModifiedMs: Long,
    ): Map<String, Any?>? {
        val root = DocumentFile.fromTreeUri(context, Uri.parse(treeUriString)) ?: return null
        var best: DocumentFile? = null
        var bestMs = 0L

        fun consider(file: DocumentFile) {
            if (!file.isFile || !isAudioName(file.name)) return
            val ms = file.lastModified()
            if (ms < modifiedAfterMs) return
            val uri = file.uri.toString()
            if (skipUri != null && uri == skipUri && ms == skipModifiedMs) return
            if (ms > bestMs) {
                bestMs = ms
                best = file
            }
        }

        fun walk(dir: DocumentFile) {
            for (child in dir.listFiles()) {
                if (child.isDirectory) walk(child) else consider(child)
            }
        }

        try {
            walk(root)
        } catch (_: SecurityException) {
            return null
        }

        val hit = best ?: return null
        return mapOf(
            "uri" to hit.uri.toString(),
            "displayName" to (hit.name ?: "recording"),
            "modifiedMs" to hit.lastModified(),
            "size" to hit.length(),
            "source" to "saf",
            "mimeType" to CallRecordingStorageHelper.mimeForName(hit.name ?: ""),
        )
    }

    private fun findNewestInMediaStore(
        context: Context,
        modifiedAfterMs: Long,
        skipUri: String?,
        skipModifiedMs: Long,
    ): Map<String, Any?>? {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.SIZE,
        )

        val selection = "${MediaStore.Audio.Media.DATE_MODIFIED} >= ?"
        val selectionArgs = arrayOf((modifiedAfterMs / 1000).toString())
        val sort = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"

        context.contentResolver.query(
            collection,
            projection,
            selection,
            selectionArgs,
            sort,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val modCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)

            while (cursor.moveToNext()) {
                val name = cursor.getString(nameCol)
                if (!isAudioName(name)) continue
                val id = cursor.getLong(idCol)
                val uri = ContentUris.withAppendedId(collection, id)
                val uriStr = uri.toString()
                val modifiedMs = cursor.getLong(modCol) * 1000L
                if (skipUri != null && uriStr == skipUri && modifiedMs == skipModifiedMs) continue
                return mapOf(
                    "uri" to uriStr,
                    "displayName" to name,
                    "modifiedMs" to modifiedMs,
                    "size" to cursor.getLong(sizeCol),
                    "source" to "mediastore",
                    "mimeType" to mimeForName(name),
                )
            }
        }
        return null
    }

    fun readBytes(context: Context, uriString: String): ByteArray? {
        return try {
            context.contentResolver.openInputStream(Uri.parse(uriString))?.use { stream ->
                stream.readBytes()
            }
        } catch (_: IOException) {
            null
        } catch (_: SecurityException) {
            null
        }
    }

    fun mimeForName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "m4a", "mp4" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "aac" -> "audio/aac"
            "wav" -> "audio/wav"
            "amr" -> "audio/amr"
            "3gp" -> "video/3gpp"
            "ogg", "opus" -> "audio/ogg"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        }
    }
}
