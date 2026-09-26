package dev.abdeldjalilchougui.exif_kit

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Android side of the `exif_kit` plugin. All I/O runs on a background thread. */
class ExifKitPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var executor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        executor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor?.shutdown()
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val task: () -> Any? = when (call.method) {
            "read" -> { -> read(call.source(), call.requireOriginal()) }
            "thumbnail" -> { -> withExif(call.source(), call.requireOriginal()) { exif, _ -> exif.thumbnailBytes } }
            "rotationDegrees" -> { -> withExif(call.source(), false) { exif, _ -> exif.rotationDegrees } }
            "write" -> { -> write(call.argument<String>("path"), call.argument<Map<String, Any?>>("changes")) }
            else -> {
                result.notImplemented()
                return
            }
        }
        val ex = executor ?: run {
            result.error("NATIVE_ERROR", "Plugin detached from engine", null)
            return
        }
        ex.execute {
            try {
                val value = task()
                mainHandler.post { result.success(value) }
            } catch (e: Throwable) {
                val code = if (call.method == "write") ExifMapping.errorCode(e) else ExifMapping.readErrorCode(e)
                mainHandler.post { result.error(code, e.message ?: e.toString(), null) }
            }
        }
    }

    private fun MethodCall.source(): String {
        val s = argument<String>("source")
        require(!s.isNullOrEmpty()) { "Missing source" }
        return s
    }

    private fun MethodCall.requireOriginal(): Boolean = argument<Boolean>("requireOriginal") == true

    private fun contentUri(source: String, requireOriginal: Boolean): Uri {
        val uri = Uri.parse(source)
        return if (requireOriginal && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.setRequireOriginal(uri)
        } else {
            uri
        }
    }

    private fun openStream(source: String, requireOriginal: Boolean): InputStream =
        if (ExifMapping.isContentUri(source)) {
            context.contentResolver.openInputStream(contentUri(source, requireOriginal))
                ?: throw FileNotFoundException("Cannot open $source")
        } else {
            FileInputStream(source)
        }

    private fun detect(source: String, requireOriginal: Boolean): ImageFormat =
        openStream(source, requireOriginal).use { input ->
            val header = ByteArray(16)
            var read = 0
            while (read < header.size) {
                val n = input.read(header, read, header.size - read)
                if (n <= 0) break
                read += n
            }
            ExifMapping.detectFormat(header.copyOf(read))
        }

    /**
     * Opens [source] with ExifInterface and runs [block] while the file descriptor is still open
     * (ExifInterface reads thumbnails lazily).
     */
    private fun <T> withExif(source: String, requireOriginal: Boolean, block: (ExifInterface, ImageFormat) -> T): T {
        if (!ExifMapping.isContentUri(source) && !File(source).exists()) {
            throw FileNotFoundException("No such file: $source")
        }
        val format = detect(source, requireOriginal)
        ExifMapping.requireReadable(format)
        return if (ExifMapping.isContentUri(source)) {
            val pfd = context.contentResolver.openFileDescriptor(contentUri(source, requireOriginal), "r")
                ?: throw FileNotFoundException("Cannot open $source")
            pfd.use { block(ExifInterface(it.fileDescriptor), format) }
        } else {
            block(ExifInterface(source), format)
        }
    }

    private fun read(source: String, requireOriginal: Boolean): Map<String, Any?> =
        withExif(source, requireOriginal) { exif, format ->
            val tags = HashMap<String, String>()
            for (tag in ExifTags.READ) exif.getAttribute(tag)?.let { tags[tag] = it }
            mapOf("tags" to ExifMapping.withoutCompatibilityDefaults(tags), "format" to format.wire, "hasThumbnail" to exif.hasThumbnail())
        }

    private fun write(path: String?, changes: Map<String, Any?>?): Any? {
        require(!path.isNullOrEmpty() && path.startsWith("/")) { "Expected an absolute file path" }
        val file = File(path)
        if (!file.exists()) throw FileNotFoundException("No such file: $path")
        if (!file.canWrite()) throw SecurityException("The app cannot write $path")
        val plan = WritePlan.parse(changes)
        val format = detect(path, false)
        if (!format.writable) {
            throw UnsupportedOperationException(
                "ExifInterface can only save JPEG, PNG and WebP; this file is ${format.wire}",
            )
        }
        val exif = ExifInterface(path)
        for (op in plan.operations()) {
            when (op) {
                is ExifOp.SetTag -> exif.setAttribute(op.tag, op.value)
                is ExifOp.SetLatLong -> exif.setLatLong(op.latitude, op.longitude)
                is ExifOp.SetAltitude -> exif.setAltitude(op.altitude)
            }
        }
        exif.saveAttributes()
        return null
    }

    companion object {
        const val CHANNEL = "dev.abdeldjalilchougui/exif_kit"
    }
}
