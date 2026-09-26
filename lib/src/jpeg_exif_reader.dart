import 'dart:convert';
import 'dart:typed_data';

import 'exceptions.dart';
import 'exif_data.dart';
import 'exif_image_format.dart';

/// Pure-Dart EXIF reader for JPEG files.
///
/// Reads IFD0, the Exif sub-IFD, the GPS sub-IFD and the IFD1 thumbnail, in
/// both byte orders, and produces values in the same string form as androidx
/// ExifInterface so [ExifData] behaves identically on every platform. It
/// never throws for out-of-range offsets; bad entries are skipped.
abstract final class JpegExifReader {
  /// Parses the EXIF metadata of the JPEG in [bytes].
  ///
  /// Throws [ExifUnsupportedFormatException] if [bytes] is not a JPEG and
  /// [ExifFormatException] if the EXIF block has an invalid TIFF header.
  static ExifData read(Uint8List bytes) => _parse(bytes).data;

  /// Returns the embedded EXIF thumbnail (usually a small JPEG), or `null`.
  static Uint8List? thumbnail(Uint8List bytes) => _parse(bytes).thumbnail;

  static _Result _parse(Uint8List bytes) {
    if (bytes.length < 3 ||
        bytes[0] != 0xFF ||
        bytes[1] != 0xD8 ||
        bytes[2] != 0xFF) {
      throw const ExifUnsupportedFormatException(
          'Not a JPEG file; the pure-Dart reader only supports JPEG');
    }
    Uint8List? tiff;
    int? width;
    int? height;
    var pos = 2;
    while (pos + 4 <= bytes.length) {
      if (bytes[pos] != 0xFF) break;
      final marker = bytes[pos + 1];
      if (marker == 0xFF) {
        pos++;
        continue;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
        pos += 2;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) break;
      final length = (bytes[pos + 2] << 8) | bytes[pos + 3];
      if (length < 2) break;
      final start = pos + 4;
      var end = pos + 2 + length;
      if (end > bytes.length) end = bytes.length;
      if (marker == 0xE1 && tiff == null && _isExifHeader(bytes, start, end)) {
        tiff = Uint8List.sublistView(bytes, start + 6, end);
      }
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof && end - start >= 5) {
        height = (bytes[start + 1] << 8) | bytes[start + 2];
        width = (bytes[start + 3] << 8) | bytes[start + 4];
      }
      pos = pos + 2 + length;
    }

    final tags = <String, String>{};
    Uint8List? thumb;
    if (tiff != null) thumb = _TiffParser(tiff, tags).parse();
    // Like ExifInterface, the SOF frame size overrides IFD0 for JPEG.
    if (width != null && height != null) {
      tags['ImageWidth'] = '$width';
      tags['ImageLength'] = '$height';
    }
    return _Result(
      ExifData(
        tags: tags,
        format: ExifImageFormat.jpeg,
        hasThumbnail: thumb != null,
      ),
      thumb,
    );
  }

  static bool _isExifHeader(Uint8List b, int start, int end) =>
      end - start >= 6 &&
      b[start] == 0x45 &&
      b[start + 1] == 0x78 &&
      b[start + 2] == 0x69 &&
      b[start + 3] == 0x66 &&
      b[start + 4] == 0 &&
      b[start + 5] == 0;
}

class _Result {
  _Result(this.data, this.thumbnail);
  final ExifData data;
  final Uint8List? thumbnail;
}

const _ifd0Tags = {
  0x0100: 'ImageWidth',
  0x0101: 'ImageLength',
  0x010E: 'ImageDescription',
  0x010F: 'Make',
  0x0110: 'Model',
  0x0112: 'Orientation',
  0x011A: 'XResolution',
  0x011B: 'YResolution',
  0x0128: 'ResolutionUnit',
  0x0131: 'Software',
  0x0132: 'DateTime',
  0x013B: 'Artist',
  0x8298: 'Copyright',
};

const _exifTags = {
  0x829A: 'ExposureTime',
  0x829D: 'FNumber',
  0x8822: 'ExposureProgram',
  0x8827: 'PhotographicSensitivity',
  0x9000: 'ExifVersion',
  0x9003: 'DateTimeOriginal',
  0x9004: 'DateTimeDigitized',
  0x9010: 'OffsetTime',
  0x9011: 'OffsetTimeOriginal',
  0x9012: 'OffsetTimeDigitized',
  0x9201: 'ShutterSpeedValue',
  0x9202: 'ApertureValue',
  0x9204: 'ExposureBiasValue',
  0x9207: 'MeteringMode',
  0x9209: 'Flash',
  0x920A: 'FocalLength',
  0x9290: 'SubSecTime',
  0x9291: 'SubSecTimeOriginal',
  0x9292: 'SubSecTimeDigitized',
  0xA002: 'PixelXDimension',
  0xA003: 'PixelYDimension',
  0xA402: 'ExposureMode',
  0xA403: 'WhiteBalance',
  0xA405: 'FocalLengthIn35mmFilm',
  0xA430: 'CameraOwnerName',
  0xA431: 'BodySerialNumber',
  0xA433: 'LensMake',
  0xA434: 'LensModel',
};

const _gpsTags = {
  0x0000: 'GPSVersionID',
  0x0001: 'GPSLatitudeRef',
  0x0002: 'GPSLatitude',
  0x0003: 'GPSLongitudeRef',
  0x0004: 'GPSLongitude',
  0x0005: 'GPSAltitudeRef',
  0x0006: 'GPSAltitude',
  0x0007: 'GPSTimeStamp',
  0x0010: 'GPSImgDirectionRef',
  0x0011: 'GPSImgDirection',
  0x0012: 'GPSMapDatum',
  0x001B: 'GPSProcessingMethod',
  0x001D: 'GPSDateStamp',
};

/// Rational tags ExifInterface reports as a decimal number.
const _decimalTags = {'ExposureTime', 'FNumber'};

const _typeSizes = {
  1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, //
};

class _TiffParser {
  _TiffParser(this.b, this.tags) : bd = ByteData.sublistView(b);

  final Uint8List b;
  final ByteData bd;
  final Map<String, String> tags;
  late final Endian e;
  final _visited = <int>{};

  Uint8List? parse() {
    if (b.length < 8) {
      throw const ExifFormatException('EXIF block shorter than a TIFF header');
    }
    if (b[0] == 0x49 && b[1] == 0x49) {
      e = Endian.little;
    } else if (b[0] == 0x4D && b[1] == 0x4D) {
      e = Endian.big;
    } else {
      throw const ExifFormatException('Invalid TIFF byte-order mark');
    }
    if (bd.getUint16(2, e) != 42) {
      throw const ExifFormatException('Invalid TIFF magic number');
    }
    final pointers = <int, int>{};
    final ifd1 = _readIfd(bd.getUint32(4, e), _ifd0Tags, pointers);
    if (pointers[0x8769] case final p?) _readIfd(p, _exifTags, {});
    if (pointers[0x8825] case final p?) _readIfd(p, _gpsTags, {});
    if (ifd1 == null) return null;
    final thumb = <int, int>{};
    _readIfd(ifd1, const {}, thumb);
    final offset = thumb[0x0201];
    final length = thumb[0x0202];
    if (offset == null || length == null || length <= 0) return null;
    if (offset + length > b.length) return null;
    return Uint8List.fromList(b.sublist(offset, offset + length));
  }

  /// Reads one IFD. Named tags go to [tags]; pointer and thumbnail tags go to
  /// [ints]. Returns the next IFD offset, or `null`.
  int? _readIfd(int offset, Map<int, String> names, Map<int, int> ints) {
    if (offset < 8 || offset + 2 > b.length || !_visited.add(offset)) {
      return null;
    }
    final count = bd.getUint16(offset, e);
    for (var i = 0; i < count; i++) {
      final at = offset + 2 + 12 * i;
      if (at + 12 > b.length) return null;
      final tag = bd.getUint16(at, e);
      final type = bd.getUint16(at + 2, e);
      final n = bd.getUint32(at + 4, e);
      final size = _typeSizes[type];
      if (size == null || n == 0 || n > b.length) continue;
      final total = size * n;
      final valueAt = total <= 4 ? at + 8 : bd.getUint32(at + 8, e);
      if (valueAt + total > b.length) continue;

      if (tag == 0x8769 || tag == 0x8825 || tag == 0x0201 || tag == 0x0202) {
        if (type == 4 || type == 3) {
          ints[tag] =
              type == 4 ? bd.getUint32(valueAt, e) : bd.getUint16(valueAt, e);
        }
        continue;
      }
      final name = names[tag];
      if (name == null) continue;
      final value = _format(name, type, n, valueAt);
      if (value != null) tags[name] = value;
    }
    final nextAt = offset + 2 + 12 * count;
    if (nextAt + 4 > b.length) return null;
    final next = bd.getUint32(nextAt, e);
    return next == 0 ? null : next;
  }

  String? _format(String name, int type, int n, int at) {
    switch (type) {
      case 2:
        var end = at;
        while (end < at + n && b[end] != 0) {
          end++;
        }
        return utf8.decode(b.sublist(at, end), allowMalformed: true);
      case 7:
        final raw = b.sublist(at, at + n);
        if (name == 'GPSAltitudeRef') return raw.join(',');
        if (raw.every((c) => c >= 0x20 && c < 0x7F)) return ascii.decode(raw);
        return null;
      case 1:
        return b.sublist(at, at + n).join(',');
      case 6:
        return [for (var i = 0; i < n; i++) bd.getInt8(at + i)].join(',');
      case 3:
        return [for (var i = 0; i < n; i++) bd.getUint16(at + 2 * i, e)]
            .join(',');
      case 8:
        return [for (var i = 0; i < n; i++) bd.getInt16(at + 2 * i, e)]
            .join(',');
      case 4:
        return [for (var i = 0; i < n; i++) bd.getUint32(at + 4 * i, e)]
            .join(',');
      case 9:
        return [for (var i = 0; i < n; i++) bd.getInt32(at + 4 * i, e)]
            .join(',');
      case 11:
        return [for (var i = 0; i < n; i++) bd.getFloat32(at + 4 * i, e)]
            .join(',');
      case 12:
        return [for (var i = 0; i < n; i++) bd.getFloat64(at + 8 * i, e)]
            .join(',');
      case 5 || 10:
        final signed = type == 10;
        final parts = <(int, int)>[
          for (var i = 0; i < n; i++)
            signed
                ? (bd.getInt32(at + 8 * i, e), bd.getInt32(at + 8 * i + 4, e))
                : (
                    bd.getUint32(at + 8 * i, e),
                    bd.getUint32(at + 8 * i + 4, e)
                  ),
        ];
        if (_decimalTags.contains(name)) {
          final (num, den) = parts.first;
          return den == 0 ? null : (num / den).toString();
        }
        if (name == 'GPSTimeStamp' && parts.length == 3) {
          if (parts.any((p) => p.$2 == 0)) return null;
          return parts
              .map((p) => (p.$1 ~/ p.$2).toString().padLeft(2, '0'))
              .join(':');
        }
        return parts.map((p) => '${p.$1}/${p.$2}').join(',');
    }
    return null;
  }
}
