package dev.abdeldjalilchougui.exif_kit

import androidx.exifinterface.media.ExifInterface
import java.io.FileNotFoundException
import java.io.IOException

/** Image container, detected from the first bytes of a file. */
enum class ImageFormat(val wire: String, val writable: Boolean) {
    JPEG("jpeg", true),
    PNG("png", true),
    WEBP("webp", true),
    HEIF("heif", false),
    DNG("dng", false),
    UNKNOWN("unknown", false),
}

/** Tag name lists. Only compile-time constants are referenced, so this is JVM-testable. */
object ExifTags {
    val GPS: List<String> = listOf(
        ExifInterface.TAG_GPS_VERSION_ID,
        ExifInterface.TAG_GPS_LATITUDE_REF,
        ExifInterface.TAG_GPS_LATITUDE,
        ExifInterface.TAG_GPS_LONGITUDE_REF,
        ExifInterface.TAG_GPS_LONGITUDE,
        ExifInterface.TAG_GPS_ALTITUDE_REF,
        ExifInterface.TAG_GPS_ALTITUDE,
        ExifInterface.TAG_GPS_TIMESTAMP,
        ExifInterface.TAG_GPS_SATELLITES,
        ExifInterface.TAG_GPS_STATUS,
        ExifInterface.TAG_GPS_MEASURE_MODE,
        ExifInterface.TAG_GPS_DOP,
        ExifInterface.TAG_GPS_SPEED_REF,
        ExifInterface.TAG_GPS_SPEED,
        ExifInterface.TAG_GPS_TRACK_REF,
        ExifInterface.TAG_GPS_TRACK,
        ExifInterface.TAG_GPS_IMG_DIRECTION_REF,
        ExifInterface.TAG_GPS_IMG_DIRECTION,
        ExifInterface.TAG_GPS_MAP_DATUM,
        ExifInterface.TAG_GPS_DEST_LATITUDE_REF,
        ExifInterface.TAG_GPS_DEST_LATITUDE,
        ExifInterface.TAG_GPS_DEST_LONGITUDE_REF,
        ExifInterface.TAG_GPS_DEST_LONGITUDE,
        ExifInterface.TAG_GPS_DEST_BEARING_REF,
        ExifInterface.TAG_GPS_DEST_BEARING,
        ExifInterface.TAG_GPS_DEST_DISTANCE_REF,
        ExifInterface.TAG_GPS_DEST_DISTANCE,
        ExifInterface.TAG_GPS_PROCESSING_METHOD,
        ExifInterface.TAG_GPS_AREA_INFORMATION,
        ExifInterface.TAG_GPS_DATESTAMP,
        ExifInterface.TAG_GPS_DIFFERENTIAL,
        ExifInterface.TAG_GPS_H_POSITIONING_ERROR,
    )

    /** Tags returned by `read`, in ExifInterface string form. */
    val READ: List<String> = listOf(
        ExifInterface.TAG_IMAGE_WIDTH,
        ExifInterface.TAG_IMAGE_LENGTH,
        ExifInterface.TAG_IMAGE_DESCRIPTION,
        ExifInterface.TAG_MAKE,
        ExifInterface.TAG_MODEL,
        ExifInterface.TAG_ORIENTATION,
        ExifInterface.TAG_X_RESOLUTION,
        ExifInterface.TAG_Y_RESOLUTION,
        ExifInterface.TAG_RESOLUTION_UNIT,
        ExifInterface.TAG_SOFTWARE,
        ExifInterface.TAG_DATETIME,
        ExifInterface.TAG_ARTIST,
        ExifInterface.TAG_COPYRIGHT,
        ExifInterface.TAG_EXPOSURE_TIME,
        ExifInterface.TAG_F_NUMBER,
        ExifInterface.TAG_EXPOSURE_PROGRAM,
        ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY,
        ExifInterface.TAG_EXIF_VERSION,
        ExifInterface.TAG_DATETIME_ORIGINAL,
        ExifInterface.TAG_DATETIME_DIGITIZED,
        ExifInterface.TAG_OFFSET_TIME,
        ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
        ExifInterface.TAG_OFFSET_TIME_DIGITIZED,
        ExifInterface.TAG_SHUTTER_SPEED_VALUE,
        ExifInterface.TAG_APERTURE_VALUE,
        ExifInterface.TAG_EXPOSURE_BIAS_VALUE,
        ExifInterface.TAG_METERING_MODE,
        ExifInterface.TAG_FLASH,
        ExifInterface.TAG_FOCAL_LENGTH,
        ExifInterface.TAG_SUBSEC_TIME,
        ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
        ExifInterface.TAG_SUBSEC_TIME_DIGITIZED,
        ExifInterface.TAG_PIXEL_X_DIMENSION,
        ExifInterface.TAG_PIXEL_Y_DIMENSION,
        ExifInterface.TAG_COLOR_SPACE,
        ExifInterface.TAG_DIGITAL_ZOOM_RATIO,
        ExifInterface.TAG_EXPOSURE_MODE,
        ExifInterface.TAG_WHITE_BALANCE,
        ExifInterface.TAG_SCENE_CAPTURE_TYPE,
        ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM,
        ExifInterface.TAG_IMAGE_UNIQUE_ID,
        ExifInterface.TAG_CAMERA_OWNER_NAME,
        ExifInterface.TAG_BODY_SERIAL_NUMBER,
        ExifInterface.TAG_LENS_MAKE,
        ExifInterface.TAG_LENS_MODEL,
        ExifInterface.TAG_LENS_SERIAL_NUMBER,
    ) + GPS

    /** Tags needed to decode or lay out the image; never stripped. */
    val STRUCTURAL: Set<String> = setOf(
        ExifInterface.TAG_IMAGE_WIDTH,
        ExifInterface.TAG_IMAGE_LENGTH,
        ExifInterface.TAG_X_RESOLUTION,
        ExifInterface.TAG_Y_RESOLUTION,
        ExifInterface.TAG_RESOLUTION_UNIT,
        ExifInterface.TAG_PIXEL_X_DIMENSION,
        ExifInterface.TAG_PIXEL_Y_DIMENSION,
        ExifInterface.TAG_COLOR_SPACE,
        ExifInterface.TAG_EXIF_VERSION,
    )

    /** Free-text, binary or identifying tags removed by strip on top of [READ]. */
    private val EXTRA_PRIVATE: List<String> = listOf(
        ExifInterface.TAG_USER_COMMENT,
        ExifInterface.TAG_MAKER_NOTE,
        ExifInterface.TAG_XMP,
        ExifInterface.TAG_SUBJECT_LOCATION,
        ExifInterface.TAG_SUBJECT_AREA,
        ExifInterface.TAG_SUBJECT_DISTANCE,
        ExifInterface.TAG_DEVICE_SETTING_DESCRIPTION,
        ExifInterface.TAG_RELATED_SOUND_FILE,
    )

    fun stripTargets(keepOrientation: Boolean): List<String> =
        (READ + EXTRA_PRIVATE).distinct().filter { tag ->
            tag !in STRUCTURAL && !(keepOrientation && tag == ExifInterface.TAG_ORIENTATION)
        }
}

data class GpsChange(val latitude: Double, val longitude: Double, val altitude: Double?)

/** One edit applied to an `ExifInterface`. */
sealed class ExifOp {
    data class SetTag(val tag: String, val value: String?) : ExifOp()
    data class SetLatLong(val latitude: Double, val longitude: Double) : ExifOp()
    data class SetAltitude(val altitude: Double) : ExifOp()
}

/** The `changes` map sent by Dart, validated. */
data class WritePlan(
    val set: Map<String, String>,
    val remove: List<String>,
    val gps: GpsChange?,
    val removeGps: Boolean,
    val strip: Boolean,
    val keepOrientation: Boolean,
) {
    /** Edits in application order: strip, remove GPS, set GPS, removals, sets. */
    fun operations(): List<ExifOp> {
        val ops = ArrayList<ExifOp>()
        if (strip) ExifTags.stripTargets(keepOrientation).forEach { ops.add(ExifOp.SetTag(it, null)) }
        if (removeGps) ExifTags.GPS.forEach { ops.add(ExifOp.SetTag(it, null)) }
        gps?.let {
            ops.add(ExifOp.SetLatLong(it.latitude, it.longitude))
            it.altitude?.let { alt -> ops.add(ExifOp.SetAltitude(alt)) }
        }
        remove.forEach { ops.add(ExifOp.SetTag(it, null)) }
        set.forEach { (k, v) -> ops.add(ExifOp.SetTag(k, v)) }
        return ops
    }

    companion object {
        fun parse(args: Map<*, *>?): WritePlan {
            requireNotNull(args) { "Missing changes" }
            val set = (args["set"] as? Map<*, *> ?: emptyMap<Any, Any>()).entries.associate { (k, v) ->
                require(k is String && k.isNotEmpty()) { "Tag names must be non-empty strings" }
                require(v is String) { "Value for $k must be a string" }
                k to v
            }
            val remove = (args["remove"] as? List<*> ?: emptyList<Any>()).map {
                require(it is String && it.isNotEmpty()) { "Tag names must be non-empty strings" }
                it
            }
            val gps = (args["gps"] as? Map<*, *>)?.let { g ->
                val lat = (g["latitude"] as? Number)?.toDouble()
                val lon = (g["longitude"] as? Number)?.toDouble()
                require(lat != null && lon != null) { "gps needs latitude and longitude" }
                require(lat.isFinite() && lat in -90.0..90.0) { "latitude out of range: $lat" }
                require(lon.isFinite() && lon in -180.0..180.0) { "longitude out of range: $lon" }
                val alt = (g["altitude"] as? Number)?.toDouble()
                require(alt == null || alt.isFinite()) { "altitude must be finite" }
                GpsChange(lat, lon, alt)
            }
            return WritePlan(
                set = set,
                remove = remove,
                gps = gps,
                removeGps = args["removeGps"] == true,
                strip = args["strip"] == true,
                keepOrientation = args["keepOrientation"] != false,
            )
        }
    }
}

/** Android-free helpers. */
object ExifMapping {
    fun isContentUri(source: String): Boolean = source.startsWith("content://")

    private fun ByteArray.matches(offset: Int, vararg expected: Int): Boolean =
        size >= offset + expected.size &&
            expected.indices.all { this[offset + it] == expected[it].toByte() }

    private fun ByteArray.ascii(offset: Int, text: String): Boolean =
        matches(offset, *text.map { it.code }.toIntArray())

    private val HEIF_BRANDS = setOf("heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1", "avif", "avis")

    /** Detects the container from at least the first 12 bytes of a file. */
    fun detectFormat(header: ByteArray): ImageFormat = when {
        header.matches(0, 0xFF, 0xD8, 0xFF) -> ImageFormat.JPEG
        header.matches(0, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) -> ImageFormat.PNG
        header.ascii(0, "RIFF") && header.ascii(8, "WEBP") -> ImageFormat.WEBP
        header.ascii(4, "ftyp") && header.size >= 12 &&
            String(header, 8, 4, Charsets.US_ASCII) in HEIF_BRANDS -> ImageFormat.HEIF
        header.matches(0, 0x49, 0x49, 0x2A, 0x00) || header.matches(0, 0x4D, 0x4D, 0x00, 0x2A) ||
            header.ascii(0, "IIRO") || header.ascii(0, "MMOR") || header.matches(0, 0x49, 0x49, 0x55, 0x00) ->
            ImageFormat.DNG
        else -> ImageFormat.UNKNOWN
    }

    private fun Throwable.says(vararg needles: String): Boolean {
        val m = message ?: return false
        return needles.any { m.contains(it, ignoreCase = true) }
    }

    /**
     * Maps an exception thrown while *reading* to a Dart error code. Missing read access
     * (a SecurityException, EACCES, or MediaProvider's UnsupportedOperationException for
     * `setRequireOriginal` without ACCESS_MEDIA_LOCATION) becomes `ACCESS_DENIED`.
     */
    fun readErrorCode(e: Throwable): String = when {
        e is SecurityException -> "ACCESS_DENIED"
        e is UnsupportedOperationException && e.says("ACCESS_MEDIA_LOCATION") -> "ACCESS_DENIED"
        e is IOException && e.says("EACCES", "EPERM", "Permission denied") -> "ACCESS_DENIED"
        else -> errorCode(e)
    }

    /** Throws when [format] is not an image ExifInterface can parse. */
    fun requireReadable(format: ImageFormat) {
        if (format == ImageFormat.UNKNOWN) {
            throw UnsupportedOperationException("Not a JPEG, PNG, WebP, HEIF or DNG image")
        }
    }

    /**
     * ExifInterface reports ImageWidth, ImageLength and Orientation as "0" when the file has
     * none ("compatibility defaults"). Those are not data, so they are dropped.
     */
    fun withoutCompatibilityDefaults(tags: Map<String, String>): Map<String, String> =
        tags.filterNot { (tag, value) -> tag in COMPATIBILITY_DEFAULTS && value.trim() == "0" }

    private val COMPATIBILITY_DEFAULTS = setOf(
        ExifInterface.TAG_IMAGE_WIDTH,
        ExifInterface.TAG_IMAGE_LENGTH,
        ExifInterface.TAG_ORIENTATION,
    )

    /** Maps an exception to the error code the Dart side understands. */
    fun errorCode(e: Throwable): String = when {
        e is SecurityException -> "PERMISSION_DENIED"
        e is IOException && e.says("EACCES", "EPERM", "EROFS", "Permission denied", "Read-only file system") ->
            "PERMISSION_DENIED"
        e is FileNotFoundException -> "FILE_NOT_FOUND"
        e is IllegalArgumentException -> "INVALID_ARGUMENT"
        e is UnsupportedOperationException -> "UNSUPPORTED_FORMAT"
        e is IOException -> "IO_ERROR"
        else -> "NATIVE_ERROR"
    }
}
