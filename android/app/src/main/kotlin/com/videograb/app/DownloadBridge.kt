package com.videograb.app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Bridges Flutter to an on-device yt-dlp (youtubedl-android + bundled python + ffmpeg).
 * Everything runs offline on the phone - no server involved.
 */
class DownloadBridge(
    private val context: Context,
    private val channel: MethodChannel
) {

    private val main = Handler(Looper.getMainLooper())
    private val pool = Executors.newFixedThreadPool(3)
    private val running = ConcurrentHashMap<String, Boolean>()
    private val lastEmit = ConcurrentHashMap<String, Long>()

    @Volatile
    private var engineReady = false

    // ------------------------------------------------------------- plumbing

    private fun bag(vararg pairs: Pair<String, Any?>): HashMap<String, Any?> {
        val map = HashMap<String, Any?>()
        for (pair in pairs) map[pair.first] = pair.second
        return map
    }

    private fun reply(result: MethodChannel.Result, payload: HashMap<String, Any?>) {
        main.post {
            try {
                result.success(payload)
            } catch (e: Throwable) {
                // result already answered
            }
        }
    }

    private fun emit(type: String, payload: HashMap<String, Any?>) {
        payload["type"] = type
        main.post {
            try {
                channel.invokeMethod("event", payload)
            } catch (e: Throwable) {
                // engine detached
            }
        }
    }

    private fun friendlyError(error: Throwable): String {
        val raw = (error.message ?: error.toString()).trim()
        if (raw.isEmpty()) return "Unknown error"
        val lines = raw.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
        val errorLine = lines.lastOrNull { it.contains("ERROR", ignoreCase = true) }
            ?: lines.lastOrNull()
            ?: raw
        return errorLine
            .replace("ERROR: ", "")
            .replace("WARNING: ", "")
            .take(320)
            .ifBlank { "Unknown error" }
    }

    private fun ensureEngine() {
        if (engineReady) return
        YoutubeDL.getInstance().init(context)
        try {
            FFmpeg.getInstance().init(context)
        } catch (e: Throwable) {
            // ffmpeg is optional; merging simply falls back
        }
        engineReady = true
    }

    // --------------------------------------------------------------- routes

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> initEngine(result)
            "engineInfo" -> engineInfo(result)
            "probe" -> probe(call.argument<String>("url"), result)
            "download" -> startDownload(call, result)
            "cancel" -> {
                val jobId = call.argument<String>("jobId") ?: ""
                running[jobId] = false
                val stopped = try {
                    YoutubeDL.getInstance().destroyProcessById(jobId)
                } catch (e: Throwable) {
                    false
                }
                reply(result, bag("ok" to stopped))
            }
            "streamUrl" -> streamUrl(call.argument<String>("url"), result)
            "updateEngine" -> updateEngine(result)
            "saveCopy" -> saveCopy(
                call.argument<String>("path"),
                call.argument<String>("name"),
                result
            )
            "deleteFile" -> deleteFile(call.argument<String>("path"), result)
            else -> result.notImplemented()
        }
    }

    private fun initEngine(result: MethodChannel.Result) {
        pool.execute {
            try {
                ensureEngine()
                val version = try {
                    YoutubeDL.getInstance().versionName(context)
                } catch (e: Throwable) {
                    "bundled"
                }
                reply(
                    result,
                    bag(
                        "ok" to true,
                        "version" to (version ?: "bundled"),
                        "sdkInt" to Build.VERSION.SDK_INT
                    )
                )
            } catch (error: Throwable) {
                reply(
                    result,
                    bag(
                        "ok" to false,
                        "error" to friendlyError(error),
                        "sdkInt" to Build.VERSION.SDK_INT
                    )
                )
            }
        }
    }

    private fun engineInfo(result: MethodChannel.Result) {
        var version = ""
        try {
            version = YoutubeDL.getInstance().versionName(context) ?: ""
        } catch (e: Throwable) {
            version = ""
        }
        reply(
            result,
            bag(
                "ok" to true,
                "ready" to engineReady,
                "version" to version,
                "sdkInt" to Build.VERSION.SDK_INT
            )
        )
    }

    private fun probe(url: String?, result: MethodChannel.Result) {
        val link = url ?: ""
        if (link.isBlank()) {
            reply(result, bag("ok" to false, "error" to "Link khali hai"))
            return
        }
        pool.execute {
            try {
                ensureEngine()
                val request = YoutubeDLRequest(link)
                request.addOption("--no-playlist")
                request.addOption("--no-warnings")
                val info = YoutubeDL.getInstance().getInfo(request)

                val heights = ArrayList<Int>()
                val sizes = HashMap<String, Long>()
                var audioOnly = false

                val formats = info.formats
                if (formats != null) {
                    for (format in formats) {
                        val vcodec = format.vcodec ?: "none"
                        val acodec = format.acodec ?: "none"
                        if (vcodec != "none" && format.height > 0) {
                            if (!heights.contains(format.height)) heights.add(format.height)
                            val size = if (format.fileSize > 0) format.fileSize
                            else format.fileSizeApproximate
                            if (size > 0) {
                                val key = format.height.toString()
                                val previous = sizes[key] ?: 0L
                                if (size > previous) sizes[key] = size
                            }
                        }
                        if (vcodec == "none" && acodec != "none") audioOnly = true
                    }
                }
                heights.sortDescending()

                var thumbnail = info.thumbnail
                if (thumbnail.isNullOrBlank()) {
                    val thumbs = info.thumbnails
                    if (thumbs != null && thumbs.isNotEmpty()) {
                        thumbnail = thumbs[thumbs.size - 1].url
                    }
                }

                reply(
                    result,
                    bag(
                        "ok" to true,
                        "url" to link,
                        "title" to (info.title ?: info.fulltitle ?: "Video"),
                        "uploader" to (info.uploader ?: ""),
                        "thumbnail" to (thumbnail ?: ""),
                        "extractor" to (info.extractorKey ?: info.extractor ?: ""),
                        "duration" to info.duration,
                        "heights" to heights,
                        "sizes" to sizes,
                        "audioOnly" to audioOnly
                    )
                )
            } catch (error: Throwable) {
                reply(result, bag("ok" to false, "error" to friendlyError(error)))
            }
        }
    }

    private fun startDownload(call: MethodCall, result: MethodChannel.Result) {
        val jobId = call.argument<String>("jobId") ?: ""
        val url = call.argument<String>("url") ?: ""
        val format = call.argument<String>("format") ?: "bv*+ba/b"
        val audioOnly = call.argument<Boolean>("audioOnly") ?: false
        val alsoSave = call.argument<Boolean>("alsoSave") ?: true

        if (jobId.isBlank() || url.isBlank()) {
            reply(result, bag("ok" to false, "error" to "Job id ya link missing"))
            return
        }
        if (running.containsKey(jobId)) {
            reply(result, bag("ok" to false, "error" to "Ye download already chal raha hai"))
            return
        }
        running[jobId] = true

        pool.execute {
            try {
                ensureEngine()
                val folder = downloadFolder()
                if (!folder.exists()) folder.mkdirs()

                val before = folder.listFiles()?.map { it.name }?.toHashSet()
                    ?: HashSet<String>()

                val request = YoutubeDLRequest(url)
                request.addOption("--no-playlist")
                request.addOption("--no-mtime")
                request.addOption("--newline")
                request.addOption("--no-warnings")
                request.addOption("--retries", "5")
                request.addOption("--fragment-retries", "5")
                request.addOption(
                    "-o",
                    File(folder, "%(title).80s [%(id)s].%(ext)s").absolutePath
                )

                if (audioOnly) {
                    request.addOption("-f", "ba/b")
                    request.addOption("-x")
                    request.addOption("--audio-format", "m4a")
                } else {
                    request.addOption("-f", format)
                    request.addOption("--merge-output-format", "mp4")
                }

                emit("stage", bag("jobId" to jobId, "message" to "Preparing"))

                YoutubeDL.getInstance().execute(request, jobId) { progress, eta, line ->
                    val now = System.currentTimeMillis()
                    val previous = lastEmit[jobId] ?: 0L
                    val interesting = line.contains("[download]") ||
                        line.contains("[Merger]") ||
                        line.contains("[ExtractAudio]")
                    if (interesting && (now - previous > 250L)) {
                        lastEmit[jobId] = now
                        emit(
                            "progress",
                            bag(
                                "jobId" to jobId,
                                "progress" to progress.toDouble(),
                                "eta" to eta,
                                "line" to line
                            )
                        )
                    }
                }

                val output = pickOutput(folder, before)
                if (output == null) {
                    emit(
                        "failed",
                        bag(
                            "jobId" to jobId,
                            "message" to "Download complete hua par file nahi mili"
                        )
                    )
                    reply(result, bag("ok" to false, "error" to "Output file not found"))
                } else {
                    var publicPath = ""
                    if (alsoSave) {
                        publicPath = exportToDownloads(output) ?: ""
                    }
                    emit(
                        "done",
                        bag(
                            "jobId" to jobId,
                            "path" to output.absolutePath,
                            "name" to output.name,
                            "size" to output.length(),
                            "publicPath" to publicPath
                        )
                    )
                    reply(
                        result,
                        bag(
                            "ok" to true,
                            "path" to output.absolutePath,
                            "name" to output.name,
                            "size" to output.length(),
                            "publicPath" to publicPath
                        )
                    )
                }
            } catch (error: Throwable) {
                val cancelled = running[jobId] == false || error is YoutubeDL.CanceledException
                if (cancelled) {
                    emit("cancelled", bag("jobId" to jobId, "message" to "Cancelled"))
                    reply(result, bag("ok" to false, "error" to "cancelled"))
                } else {
                    emit("failed", bag("jobId" to jobId, "message" to friendlyError(error)))
                    reply(result, bag("ok" to false, "error" to friendlyError(error)))
                }
            } finally {
                running.remove(jobId)
                lastEmit.remove(jobId)
            }
        }
    }

    private fun streamUrl(url: String?, result: MethodChannel.Result) {
        val link = url ?: ""
        if (link.isBlank()) {
            reply(result, bag("ok" to false, "error" to "Link khali hai"))
            return
        }
        pool.execute {
            var direct: String? = null
            var lastError = ""
            val selectors = listOf(
                "b[protocol^=http][ext=mp4]/b[protocol^=http]/b",
                "b",
                "bv*+ba/b"
            )
            for (selector in selectors) {
                try {
                    ensureEngine()
                    val request = YoutubeDLRequest(link)
                    request.addOption("--no-playlist")
                    request.addOption("-f", selector)
                    val info = YoutubeDL.getInstance().getInfo(request)
                    direct = info.url
                    if (!direct.isNullOrBlank()) break
                } catch (error: Throwable) {
                    lastError = friendlyError(error)
                }
            }
            if (direct.isNullOrBlank()) {
                reply(
                    result,
                    bag(
                        "ok" to false,
                        "error" to if (lastError.isBlank())
                            "Direct stream nahi mila - download karke Library se play karein"
                        else lastError
                    )
                )
            } else {
                reply(result, bag("ok" to true, "url" to direct))
            }
        }
    }

    private fun updateEngine(result: MethodChannel.Result) {
        pool.execute {
            try {
                ensureEngine()
                val status = YoutubeDL.getInstance()
                    .updateYoutubeDL(context, YoutubeDL.UpdateChannel._STABLE)
                val version = try {
                    YoutubeDL.getInstance().versionName(context) ?: ""
                } catch (e: Throwable) {
                    ""
                }
                reply(
                    result,
                    bag("ok" to true, "status" to (status?.name ?: "UNKNOWN"), "version" to version)
                )
            } catch (error: Throwable) {
                reply(result, bag("ok" to false, "error" to friendlyError(error)))
            }
        }
    }

    private fun saveCopy(path: String?, name: String?, result: MethodChannel.Result) {
        val filePath = path ?: ""
        if (filePath.isBlank()) {
            reply(result, bag("ok" to false, "error" to "File path missing"))
            return
        }
        pool.execute {
            val file = File(filePath)
            if (!file.exists()) {
                reply(result, bag("ok" to false, "error" to "File nahi mili"))
                return@execute
            }
            val exported = exportToDownloads(file)
            if (exported.isNullOrBlank()) {
                reply(
                    result,
                    bag(
                        "ok" to false,
                        "error" to "Save nahi hua - storage permission ya jagah check karein"
                    )
                )
            } else {
                reply(
                    result,
                    bag("ok" to true, "publicPath" to exported, "name" to file.name)
                )
            }
        }
    }

    private fun deleteFile(path: String?, result: MethodChannel.Result) {
        val target = path ?: ""
        if (target.isBlank()) {
            reply(result, bag("ok" to false))
            return
        }
        pool.execute {
            var deleted = false
            try {
                if (target.startsWith("content://")) {
                    val uri = android.net.Uri.parse(target)
                    deleted = context.contentResolver.delete(uri, null, null) > 0
                } else {
                    deleted = File(target).delete()
                }
            } catch (e: Throwable) {
                deleted = false
            }
            reply(result, bag("ok" to deleted))
        }
    }

    // ---------------------------------------------------------------- files

    private fun downloadFolder(): File {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        return File(base, "VideoGrab")
    }

    private fun pickOutput(folder: File, before: Set<String>): File? {
        val files = folder.listFiles() ?: return null
        val candidates = files.filter {
            it.isFile && !it.name.endsWith(".part") && !it.name.endsWith(".ytdl")
        }
        val fresh = candidates.filter { !before.contains(it.name) }
        val pool = if (fresh.isNotEmpty()) fresh else candidates
        return pool.maxByOrNull { it.lastModified() }
    }

    private fun mimeFor(name: String): String {
        val ext = name.substringAfterLast('.', "mp4").lowercase()
        return when (ext) {
            "mp4", "m4v" -> "video/mp4"
            "webm" -> "video/webm"
            "mkv" -> "video/x-matroska"
            "3gp" -> "video/3gpp"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "opus", "ogg" -> "audio/ogg"
            else -> "application/octet-stream"
        }
    }

    /** Copies the finished file into the public Download/VideoGrab folder. */
    private fun exportToDownloads(file: File): String? {
        return try {
            val mime = mimeFor(file.name)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/VideoGrab"
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return null
                resolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(file).use { input -> input.copyTo(output) }
                }
                val done = ContentValues()
                done.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, done, null, null)
                uri.toString()
            } else {
                val folder = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "VideoGrab"
                )
                if (!folder.exists()) folder.mkdirs()
                val target = File(folder, file.name)
                FileInputStream(file).use { input ->
                    FileOutputStream(target).use { output -> input.copyTo(output) }
                }
                target.absolutePath
            }
        } catch (e: Throwable) {
            null
        }
    }
}
