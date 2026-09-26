package dev.abdeldjalilchougui.exif_kit

import java.io.FileNotFoundException
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ExifMappingTest {
    private fun bytes(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }
    private fun ascii(s: String) = s.toByteArray(Charsets.US_ASCII)

    // --- format detection -------------------------------------------------

    @Test
    fun detectsJpegPngWebp() {
        assertEquals(ImageFormat.JPEG, ExifMapping.detectFormat(bytes(0xFF, 0xD8, 0xFF, 0xE1)))
        assertEquals(ImageFormat.PNG, ExifMapping.detectFormat(bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))
        assertEquals(ImageFormat.WEBP, ExifMapping.detectFormat(ascii("RIFF") + bytes(1, 2, 3, 4) + ascii("WEBPVP8X")))
    }

    @Test
    fun detectsHeifBrands() {
        for (brand in listOf("heic", "heix", "hevc", "mif1", "msf1", "avif")) {
            val header = bytes(0, 0, 0, 0x18) + ascii("ftyp$brand") + bytes(0, 0, 0, 0)
            assertEquals(ImageFormat.HEIF, ExifMapping.detectFormat(header), brand)
        }
        assertEquals(ImageFormat.UNKNOWN, ExifMapping.detectFormat(bytes(0, 0, 0, 0x18) + ascii("ftypmp42")))
    }

    @Test
    fun detectsTiffBasedRaw() {
        assertEquals(ImageFormat.DNG, ExifMapping.detectFormat(bytes(0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0)))
        assertEquals(ImageFormat.DNG, ExifMapping.detectFormat(bytes(0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8)))
        assertEquals(ImageFormat.DNG, ExifMapping.detectFormat(ascii("IIRO") + bytes(8, 0, 0, 0)))
        assertEquals(ImageFormat.DNG, ExifMapping.detectFormat(bytes(0x49, 0x49, 0x55, 0x00)))
    }

    @Test
    fun unknownOrShortInput() {
        assertEquals(ImageFormat.UNKNOWN, ExifMapping.detectFormat(ByteArray(0)))
        assertEquals(ImageFormat.UNKNOWN, ExifMapping.detectFormat(bytes(0xFF)))
        assertEquals(ImageFormat.UNKNOWN, ExifMapping.detectFormat(ascii("GIF89a")))
    }

    @Test
    fun writableFormatsMatchExifInterfaceSaveSupport() {
        assertTrue(ImageFormat.JPEG.writable)
        assertTrue(ImageFormat.PNG.writable)
        assertTrue(ImageFormat.WEBP.writable)
        assertFalse(ImageFormat.HEIF.writable)
        assertFalse(ImageFormat.DNG.writable)
        assertFalse(ImageFormat.UNKNOWN.writable)
        assertEquals(listOf("jpeg", "png", "webp", "heif", "dng", "unknown"), ImageFormat.values().map { it.wire })
    }

    // --- sources ---------------------------------------------------------

    @Test
    fun contentUriDetection() {
        assertTrue(ExifMapping.isContentUri("content://media/external/images/media/1"))
        assertFalse(ExifMapping.isContentUri("/sdcard/a.jpg"))
        assertFalse(ExifMapping.isContentUri("file:///sdcard/a.jpg"))
    }

    // --- tag lists -------------------------------------------------------

    @Test
    fun readListCoversCoreTagsWithoutDuplicates() {
        val read = ExifTags.READ
        for (t in listOf(
            "Make", "Model", "Orientation", "DateTimeOriginal", "OffsetTimeOriginal", "SubSecTimeOriginal",
            "GPSLatitude", "GPSLatitudeRef", "GPSLongitude", "GPSLongitudeRef", "GPSAltitude", "GPSAltitudeRef",
            "ExposureTime", "FNumber", "PhotographicSensitivity", "FocalLength", "ImageWidth", "ImageLength",
            "Software",
        )) assertTrue(t in read, t)
        assertEquals(read.size, read.toSet().size)
    }

    @Test
    fun stripRemovesPrivacyTagsAndKeepsStructure() {
        val keep = ExifTags.stripTargets(keepOrientation = true)
        for (t in listOf(
            "Make", "Model", "DateTimeOriginal", "GPSLatitude", "GPSLongitude", "GPSAltitude",
            "BodySerialNumber", "CameraOwnerName", "LensSerialNumber", "Artist", "Copyright",
            "ImageUniqueID", "UserComment", "Xmp", "MakerNote", "Software",
        )) assertTrue(t in keep, t)
        for (t in listOf("Orientation", "ImageWidth", "ImageLength", "PixelXDimension", "PixelYDimension"))
            assertFalse(t in keep, t)
        assertTrue("Orientation" in ExifTags.stripTargets(keepOrientation = false))
    }

    @Test
    fun gpsListIsAllGpsTags() {
        assertTrue(ExifTags.GPS.isNotEmpty())
        assertTrue(ExifTags.GPS.all { it.startsWith("GPS") })
        assertTrue("GPSLatitude" in ExifTags.GPS && "GPSDateStamp" in ExifTags.GPS)
    }

    // --- write plan ------------------------------------------------------

    private fun args(
        set: Map<String, Any?> = emptyMap(),
        remove: List<Any?> = emptyList(),
        gps: Map<String, Any?>? = null,
        removeGps: Boolean = false,
        strip: Boolean = false,
        keepOrientation: Boolean = true,
    ): Map<String, Any?> = mapOf(
        "set" to set, "remove" to remove, "gps" to gps,
        "removeGps" to removeGps, "strip" to strip, "keepOrientation" to keepOrientation,
    )

    @Test
    fun parsesAFullPlan() {
        val plan = WritePlan.parse(args(
            set = mapOf("Make" to "Acme"), remove = listOf("Artist"),
            gps = mapOf("latitude" to 36.75, "longitude" to 3.06, "altitude" to -2.0),
        ))
        assertEquals(mapOf("Make" to "Acme"), plan.set)
        assertEquals(listOf("Artist"), plan.remove)
        assertEquals(GpsChange(36.75, 3.06, -2.0), plan.gps)
        assertFalse(plan.removeGps)
        assertFalse(plan.strip)
    }

    @Test
    fun gpsAcceptsIntegersAndMissingAltitude() {
        val plan = WritePlan.parse(args(gps = mapOf("latitude" to 1, "longitude" to 2)))
        assertEquals(GpsChange(1.0, 2.0, null), plan.gps)
    }

    @Test
    fun rejectsBadInput() {
        assertFailsWith<IllegalArgumentException> { WritePlan.parse(null) }
        assertFailsWith<IllegalArgumentException> { WritePlan.parse(args(set = mapOf("Make" to 3))) }
        assertFailsWith<IllegalArgumentException> { WritePlan.parse(args(set = mapOf("" to "x"))) }
        assertFailsWith<IllegalArgumentException> { WritePlan.parse(args(remove = listOf(5))) }
        assertFailsWith<IllegalArgumentException> {
            WritePlan.parse(args(gps = mapOf("latitude" to 91.0, "longitude" to 0.0)))
        }
        assertFailsWith<IllegalArgumentException> {
            WritePlan.parse(args(gps = mapOf("latitude" to 0.0, "longitude" to 181.0)))
        }
        assertFailsWith<IllegalArgumentException> {
            WritePlan.parse(args(gps = mapOf("latitude" to Double.NaN, "longitude" to 0.0)))
        }
        assertFailsWith<IllegalArgumentException> { WritePlan.parse(args(gps = mapOf("latitude" to 1.0))) }
    }

    @Test
    fun operationsAreOrderedStripRemoveGpsGpsRemoveSet() {
        val plan = WritePlan.parse(args(
            set = mapOf("Make" to "Acme"), remove = listOf("Artist"),
            gps = mapOf("latitude" to 1.0, "longitude" to 2.0, "altitude" to 3.0),
            strip = true, keepOrientation = true,
        ))
        val ops = plan.operations()
        val stripCount = ExifTags.stripTargets(true).size
        assertTrue(ops.take(stripCount).all { it is ExifOp.SetTag && it.value == null })
        assertEquals(ExifOp.SetLatLong(1.0, 2.0), ops[stripCount])
        assertEquals(ExifOp.SetAltitude(3.0), ops[stripCount + 1])
        assertEquals(ExifOp.SetTag("Artist", null), ops[stripCount + 2])
        assertEquals(ExifOp.SetTag("Make", "Acme"), ops.last())
        assertFalse(ops.contains(ExifOp.SetTag("Orientation", null)))
    }

    @Test
    fun removeGpsClearsEveryGpsTag() {
        val ops = WritePlan.parse(args(removeGps = true)).operations()
        assertEquals(ExifTags.GPS.map { ExifOp.SetTag(it, null) }, ops)
    }

    @Test
    fun emptyPlanHasNoOperations() {
        assertTrue(WritePlan.parse(args()).operations().isEmpty())
    }

    // --- error mapping ---------------------------------------------------

    @Test
    fun mapsExceptionsToChannelCodes() {
        assertEquals("FILE_NOT_FOUND", ExifMapping.errorCode(FileNotFoundException("/x: open failed: ENOENT (No such file or directory)")))
        assertEquals("PERMISSION_DENIED", ExifMapping.errorCode(FileNotFoundException("/x: open failed: EACCES (Permission denied)")))
        assertEquals("PERMISSION_DENIED", ExifMapping.errorCode(IOException("write failed: EROFS (Read-only file system)")))
        assertEquals("PERMISSION_DENIED", ExifMapping.errorCode(SecurityException("no access")))
        assertEquals("INVALID_ARGUMENT", ExifMapping.errorCode(IllegalArgumentException("bad")))
        assertEquals("UNSUPPORTED_FORMAT", ExifMapping.errorCode(UnsupportedOperationException("no")))
        assertEquals("IO_ERROR", ExifMapping.errorCode(IOException("disk")))
        assertEquals("NATIVE_ERROR", ExifMapping.errorCode(IllegalStateException("?")))
    }
}
