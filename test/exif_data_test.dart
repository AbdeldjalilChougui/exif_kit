import 'package:exif_kit/exif_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExifData typed getters from ExifInterface strings', () {
    test('double-string FNumber and ExposureTime (ExifInterface compat)', () {
      final d = ExifData(tags: const {
        'FNumber': '1.8',
        'ExposureTime': '0.016666666666666666',
      });
      expect(d.fNumber, 1.8);
      expect(d.exposureTime, closeTo(1 / 60, 1e-12));
    });

    test('rational strings too', () {
      final d = ExifData(tags: const {
        'FNumber': '18/10',
        'ExposureTime': '1/60',
        'FocalLength': '4250/1000',
      });
      expect(d.fNumber, closeTo(1.8, 1e-12));
      expect(d.exposureTime, closeTo(1 / 60, 1e-12));
      expect(d.focalLength, closeTo(4.25, 1e-12));
    });

    test('zero denominator gives null', () {
      expect(ExifData(tags: const {'FNumber': '1/0'}).fNumber, isNull);
      expect(ExifData(tags: const {'GPSLatitude': '1/0,0/1,0/1'}).latitude,
          isNull);
    });

    test('ISO falls back to the legacy ISOSpeedRatings name', () {
      expect(ExifData(tags: const {'ISOSpeedRatings': '200'}).iso, 200);
      expect(ExifData(tags: const {'PhotographicSensitivity': '100,100'}).iso,
          100);
    });

    test('GPS in decimal DMS form is accepted', () {
      final d = ExifData(tags: const {
        'GPSLatitude': '10.0,30.0,0.0',
        'GPSLatitudeRef': 'S',
        'GPSLongitude': '20/1,15/1,0/1',
      });
      expect(d.latitude, -10.5);
      expect(d.longitude, 20.25, reason: 'missing ref means positive');
      expect(d.hasGps, isTrue);
    });

    test('GPS with too few components is ignored', () {
      final d = ExifData(tags: const {'GPSLatitude': '10/1,5/1'});
      expect(d.latitude, isNull);
      expect(d.hasGps, isFalse);
    });

    test('blank or zero dates give null', () {
      expect(
          ExifData(tags: const {'DateTimeOriginal': '    :  :     :  :  '})
              .dateTimeOriginal,
          isNull);
      expect(
          ExifData(tags: const {'DateTimeOriginal': '0000:00:00 00:00:00'})
              .dateTimeOriginal,
          isNull);
      expect(
          ExifData(tags: const {'DateTimeOriginal': 'garbage'})
              .dateTimeOriginal,
          isNull);
    });

    test('dates without offset have no UTC value', () {
      final d =
          ExifData(tags: const {'DateTimeOriginal': '2020:02:29 12:00:00'});
      expect(d.dateTimeOriginal, DateTime(2020, 2, 29, 12));
      expect(d.offsetTimeOriginal, isNull);
      expect(d.dateTimeOriginalUtc, isNull);
    });

    test('offset parsing', () {
      Duration? off(String s) =>
          ExifData(tags: {'OffsetTimeOriginal': s}).offsetTimeOriginal;
      expect(off('+05:45'), const Duration(hours: 5, minutes: 45));
      expect(off('-03:00'), const Duration(hours: -3));
      expect(off('+00:00'), Duration.zero);
      expect(off('Z'), isNull);
      expect(off('+5'), isNull);
    });

    test('width and height fall back to PixelX/YDimension', () {
      final d = ExifData(tags: const {
        'PixelXDimension': '4032',
        'PixelYDimension': '3024',
      });
      expect(d.width, 4032);
      expect(d.height, 3024);
    });

    test('trimmed strings; empty strings are null', () {
      final d = ExifData(tags: const {'Make': ' Google  ', 'Model': '   '});
      expect(d.make, 'Google');
      expect(d.model, isNull);
    });

    test('invalid orientation values', () {
      expect(ExifData(tags: const {'Orientation': '0'}).orientation, isNull);
      expect(ExifData(tags: const {'Orientation': '9'}).orientation, isNull);
      expect(ExifData(tags: const {'Orientation': '0'}).rotationDegrees, 0);
    });

    test('tags map is unmodifiable', () {
      final d = ExifData(tags: {'Make': 'x'});
      expect(() => d.tags['Make'] = 'y', throwsUnsupportedError);
    });

    test('fromMap reads the platform payload', () {
      final d = ExifData.fromMap(const {
        'tags': {'Make': 'Google', 'Orientation': '6'},
        'format': 'heif',
        'hasThumbnail': true,
      });
      expect(d.make, 'Google');
      expect(d.format, ExifImageFormat.heif);
      expect(d.hasThumbnail, isTrue);
      expect(d.rotationDegrees, 90);
    });
  });

  group('ExifOrientation', () {
    test('values, rotation and flip', () {
      expect(ExifOrientation.fromValue(1), ExifOrientation.normal);
      expect(ExifOrientation.normal.value, 1);
      final expected = {
        ExifOrientation.normal: (0, false),
        ExifOrientation.flipHorizontal: (0, true),
        ExifOrientation.rotate180: (180, false),
        ExifOrientation.flipVertical: (180, true),
        ExifOrientation.transpose: (90, true),
        ExifOrientation.rotate90: (90, false),
        ExifOrientation.transverse: (270, true),
        ExifOrientation.rotate270: (270, false),
      };
      for (final e in expected.entries) {
        expect(e.key.rotationDegrees, e.value.$1, reason: e.key.name);
        expect(e.key.isFlipped, e.value.$2, reason: e.key.name);
      }
      expect(
          ExifOrientation.values.map((o) => o.value), [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });

  test('ExifImageFormat.parse', () {
    expect(ExifImageFormat.parse('jpeg'), ExifImageFormat.jpeg);
    expect(ExifImageFormat.parse('png'), ExifImageFormat.png);
    expect(ExifImageFormat.parse('webp'), ExifImageFormat.webp);
    expect(ExifImageFormat.parse('dng'), ExifImageFormat.dng);
    expect(ExifImageFormat.parse('x'), ExifImageFormat.unknown);
    expect(ExifImageFormat.parse(null), ExifImageFormat.unknown);
    expect(ExifImageFormat.jpeg.isWritable, isTrue);
    expect(ExifImageFormat.png.isWritable, isTrue);
    expect(ExifImageFormat.webp.isWritable, isTrue);
    expect(ExifImageFormat.heif.isWritable, isFalse);
    expect(ExifImageFormat.dng.isWritable, isFalse);
  });
}
