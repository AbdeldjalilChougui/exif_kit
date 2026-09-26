import 'dart:typed_data';

import 'package:exif_kit/exif_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/jpeg_builder.dart';

void main() {
  for (final little in [true, false]) {
    final order = little ? 'II (little-endian)' : 'MM (big-endian)';

    group('byte order $order', () {
      final thumb = [0xFF, 0xD8, 0xFF, 0xDB, 1, 2, 3, 0xFF, 0xD9];
      late ExifData data;

      setUpAll(() {
        final tiff =
            buildTiff(sampleIfd0(thumbnail: thumb), littleEndian: little);
        data = JpegExifReader.read(buildJpeg(tiff: tiff));
      });

      test('ASCII tags', () {
        expect(data.make, 'FUJIFILM');
        expect(data.model, 'X-T4');
        expect(data.software, 'Digital Camera X-T4 Ver2.00');
        expect(data.tags['Make'], 'FUJIFILM');
      });

      test('orientation SHORT', () {
        expect(data.tags['Orientation'], '3');
        expect(data.orientation, ExifOrientation.rotate180);
        expect(data.rotationDegrees, 180);
      });

      test('GPS rationals to decimal degrees', () {
        expect(data.tags['GPSLatitude'], '35/1,39/1,3120/100');
        expect(data.tags['GPSLatitudeRef'], 'N');
        // 35 + 39/60 + 31.20/3600
        expect(data.latitude, closeTo(35.658666666, 1e-8));
        // 139 + 41/60 + 4/3600
        expect(data.longitude, closeTo(139.684444444, 1e-8));
        expect(data.altitude, closeTo(40.5, 1e-9));
        expect(data.tags['GPSAltitudeRef'], '0');
        expect(data.tags['GPSTimeStamp'], '01:20:30');
        expect(data.tags['GPSDateStamp'], '2023:08:15');
      });

      test('dates with offset and sub-seconds', () {
        expect(data.dateTimeOriginal, DateTime(2023, 8, 15, 10, 20, 30, 500));
        expect(data.offsetTimeOriginal, const Duration(hours: 9));
        expect(data.dateTimeOriginalUtc,
            DateTime.utc(2023, 8, 15, 1, 20, 30, 500));
        expect(data.dateTime, DateTime(2023, 8, 15, 10, 20, 30));
      });

      test('exposure, aperture, ISO, focal length', () {
        expect(data.tags['ExposureTime'], '0.004');
        expect(data.exposureTime, closeTo(0.004, 1e-12));
        expect(data.tags['FNumber'], '5.6');
        expect(data.fNumber, closeTo(5.6, 1e-12));
        expect(data.tags['PhotographicSensitivity'], '800');
        expect(data.iso, 800);
        expect(data.tags['FocalLength'], '230/10');
        expect(data.focalLength, closeTo(23.0, 1e-12));
      });

      test('dimensions from SOF, pixel dimensions kept', () {
        expect(data.width, 640);
        expect(data.height, 480);
        expect(data.tags['PixelXDimension'], '6240');
      });

      test('thumbnail from IFD1', () {
        expect(data.hasThumbnail, isTrue);
        final bytes = JpegExifReader.thumbnail(buildJpeg(
            tiff:
                buildTiff(sampleIfd0(thumbnail: thumb), littleEndian: little)));
        expect(bytes, thumb);
      });

      test('format is JPEG', () {
        expect(data.format, ExifImageFormat.jpeg);
      });
    });
  }

  group('southern / western hemisphere and below sea level', () {
    for (final little in [true, false]) {
      test(little ? 'II' : 'MM', () {
        final ifd0 = TiffIfd([
          TiffEntry.short(0x0112, [8])
        ]);
        ifd0.children[0x8825] = TiffIfd([
          TiffEntry.ascii(0x0001, 'S'),
          TiffEntry.rational(0x0002, [
            [22, 1],
            [54, 1],
            [3000, 100],
          ]),
          TiffEntry.ascii(0x0003, 'W'),
          TiffEntry.rational(0x0004, [
            [43, 1],
            [12, 1],
            [2700, 100],
          ]),
          TiffEntry.byte(0x0005, [1]),
          TiffEntry.rational(0x0006, [
            [7, 2],
          ]),
        ]);
        final d = JpegExifReader.read(
            buildJpeg(tiff: buildTiff(ifd0, littleEndian: little)));
        expect(d.latitude, closeTo(-(22 + 54 / 60 + 30 / 3600), 1e-9));
        expect(d.longitude, closeTo(-(43 + 12 / 60 + 27 / 3600), 1e-9));
        expect(d.altitude, closeTo(-3.5, 1e-9));
        expect(d.orientation, ExifOrientation.rotate270);
        expect(d.rotationDegrees, 270);
        expect(d.hasThumbnail, isFalse);
      });
    }
  });

  test('SRATIONAL values; SOF overrides IFD0 ImageWidth', () {
    final ifd0 = TiffIfd([
      TiffEntry.long(0x0100, [4000])
    ]);
    ifd0.children[0x8769] = TiffIfd([
      TiffEntry.srational(0x9204, [
        [-2, 3],
      ]),
    ]);
    final d = JpegExifReader.read(
        buildJpeg(tiff: buildTiff(ifd0, littleEndian: false)));
    expect(d.tags['ExposureBiasValue'], '-2/3');
    // Like androidx ExifInterface, the JPEG SOF frame size overrides IFD0.
    expect(d.tags['ImageWidth'], '640');
    expect(d.width, 640);
  });

  test('skips an XMP APP1 before the Exif APP1', () {
    final d = JpegExifReader.read(buildJpeg(
      tiff: buildTiff(sampleIfd0(), littleEndian: true),
      withXmpFirst: true,
    ));
    expect(d.make, 'FUJIFILM');
  });

  test('JPEG without EXIF yields empty tags and SOF dimensions', () {
    final d = JpegExifReader.read(buildJpeg(width: 12, height: 34));
    expect(d.tags.keys, unorderedEquals(['ImageWidth', 'ImageLength']));
    expect(d.width, 12);
    expect(d.height, 34);
    expect(d.orientation, isNull);
    expect(d.rotationDegrees, 0);
    expect(d.latitude, isNull);
    expect(d.hasThumbnail, isFalse);
    expect(JpegExifReader.thumbnail(buildJpeg()), isNull);
  });

  test('non-JPEG input throws ExifUnsupportedFormatException', () {
    final png =
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect(() => JpegExifReader.read(png),
        throwsA(isA<ExifUnsupportedFormatException>()));
    expect(() => JpegExifReader.read(Uint8List(0)),
        throwsA(isA<ExifUnsupportedFormatException>()));
  });

  test('bad TIFF header throws ExifFormatException', () {
    final bogus = Uint8List.fromList([0x58, 0x58, 0, 42, 0, 0, 0, 8]);
    expect(() => JpegExifReader.read(buildJpeg(tiff: bogus)),
        throwsA(isA<ExifFormatException>()));
  });

  test('truncated data and out-of-range offsets do not crash', () {
    final full = buildJpeg(tiff: buildTiff(sampleIfd0(), littleEndian: true));
    for (var cut = 2; cut < full.length; cut += 7) {
      final part = Uint8List.sublistView(full, 0, cut);
      try {
        JpegExifReader.read(part);
      } on ExifKitException {
        // Typed errors are fine; anything else fails the test.
      }
    }
  });

  test('IFD loops are not followed forever', () {
    // IFD0 whose "next IFD" pointer points back to itself.
    final tiff = Uint8List.fromList([
      0x49, 0x49, 42, 0, 8, 0, 0, 0, //
      1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, //
      8, 0, 0, 0,
    ]);
    final d = JpegExifReader.read(buildJpeg(tiff: tiff));
    expect(d.orientation, ExifOrientation.rotate90);
  });
}
