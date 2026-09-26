import 'exif_image_format.dart';
import 'exif_orientation.dart';
import 'exif_tag.dart';

/// EXIF metadata of one image: the raw tag map plus typed getters for the
/// common tags.
///
/// Tag values use androidx ExifInterface conventions: rationals as `n/d`
/// (comma-separated for several), integers as decimal text, and `FNumber` /
/// `ExposureTime` as decimal numbers. Getters accept both rational and
/// decimal forms.
class ExifData {
  /// Creates a value from a raw tag map.
  ExifData({
    required Map<String, String> tags,
    this.format = ExifImageFormat.unknown,
    this.hasThumbnail = false,
  }) : tags = Map.unmodifiable(tags);

  /// Builds a value from the platform payload `{tags, format, hasThumbnail}`.
  factory ExifData.fromMap(Map<Object?, Object?> map) {
    final raw = map['tags'];
    return ExifData(
      tags: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key != null && e.value != null)
              e.key.toString(): e.value.toString(),
      },
      format: ExifImageFormat.parse(map['format'] as String?),
      hasThumbnail: map['hasThumbnail'] == true,
    );
  }

  /// Every tag that was read, keyed by ExifInterface tag name (see [ExifTag]).
  final Map<String, String> tags;

  /// The image container.
  final ExifImageFormat format;

  /// Whether the file embeds an EXIF thumbnail.
  final bool hasThumbnail;

  /// Camera maker.
  String? get make => _text(ExifTag.make);

  /// Camera model.
  String? get model => _text(ExifTag.model);

  /// Software that wrote the file.
  String? get software => _text(ExifTag.software);

  /// Orientation, or `null` when absent or invalid.
  ExifOrientation? get orientation =>
      ExifOrientation.fromValue(_int(ExifTag.orientation));

  /// Clockwise rotation needed to display the image upright; 0 when unknown.
  int get rotationDegrees => orientation?.rotationDegrees ?? 0;

  /// Capture time as a wall-clock value (no time zone), including
  /// `SubSecTimeOriginal` when present.
  DateTime? get dateTimeOriginal =>
      _date(ExifTag.dateTimeOriginal, _text(ExifTag.subSecTimeOriginal));

  /// UTC offset of [dateTimeOriginal] from `OffsetTimeOriginal`.
  Duration? get offsetTimeOriginal => _offset(ExifTag.offsetTimeOriginal);

  /// [dateTimeOriginal] converted to UTC, when the offset is known.
  DateTime? get dateTimeOriginalUtc {
    final local = dateTimeOriginal;
    final offset = offsetTimeOriginal;
    if (local == null || offset == null) return null;
    return DateTime.utc(local.year, local.month, local.day, local.hour,
            local.minute, local.second, local.millisecond)
        .subtract(offset);
  }

  /// Last modification time (`DateTime` tag), wall-clock.
  DateTime? get dateTime => _date(ExifTag.dateTime, null);

  /// Latitude in decimal degrees, negative in the southern hemisphere.
  double? get latitude =>
      _coordinate(ExifTag.gpsLatitude, ExifTag.gpsLatitudeRef, 'S', 90);

  /// Longitude in decimal degrees, negative west of Greenwich.
  double? get longitude =>
      _coordinate(ExifTag.gpsLongitude, ExifTag.gpsLongitudeRef, 'W', 180);

  /// Altitude in metres, negative below sea level.
  double? get altitude {
    final a = _numbers(ExifTag.gpsAltitude);
    if (a == null || a.isEmpty) return null;
    return _text(ExifTag.gpsAltitudeRef) == '1' ? -a.first : a.first;
  }

  /// Whether both [latitude] and [longitude] are present.
  bool get hasGps => latitude != null && longitude != null;

  /// Exposure time in seconds.
  double? get exposureTime => _number(ExifTag.exposureTime);

  /// Aperture f-number.
  double? get fNumber => _number(ExifTag.fNumber);

  /// ISO sensitivity.
  int? get iso =>
      _int(ExifTag.photographicSensitivity) ?? _int(ExifTag.isoSpeedRatings);

  /// Focal length in millimetres.
  double? get focalLength => _number(ExifTag.focalLength);

  /// Width in pixels (`ImageWidth`, else `PixelXDimension`).
  int? get width => _int(ExifTag.imageWidth) ?? _int(ExifTag.pixelXDimension);

  /// Height in pixels (`ImageLength`, else `PixelYDimension`).
  int? get height => _int(ExifTag.imageLength) ?? _int(ExifTag.pixelYDimension);

  String? _text(String tag) {
    final v = tags[tag]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  int? _int(String tag) {
    final v = _text(tag);
    if (v == null) return null;
    return int.tryParse(v.split(',').first.trim());
  }

  static double? _parseNumber(String s) {
    final t = s.trim();
    final slash = t.indexOf('/');
    if (slash < 0) return double.tryParse(t);
    final n = double.tryParse(t.substring(0, slash));
    final d = double.tryParse(t.substring(slash + 1));
    if (n == null || d == null || d == 0) return null;
    return n / d;
  }

  List<double>? _numbers(String tag) {
    final v = _text(tag);
    if (v == null) return null;
    final out = <double>[];
    for (final part in v.split(',')) {
      final n = _parseNumber(part);
      if (n == null) return null;
      out.add(n);
    }
    return out;
  }

  double? _number(String tag) {
    final n = _numbers(tag);
    return n == null || n.isEmpty ? null : n.first;
  }

  double? _coordinate(String tag, String refTag, String negative, num limit) {
    final dms = _numbers(tag);
    if (dms == null || dms.length < 3) return null;
    final value = dms[0] + dms[1] / 60 + dms[2] / 3600;
    if (value > limit) return null;
    return _text(refTag)?.toUpperCase() == negative ? -value : value;
  }

  static final _datePattern =
      RegExp(r'^(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})');

  DateTime? _date(String tag, String? subSec) {
    final v = _text(tag);
    if (v == null) return null;
    final m = _datePattern.firstMatch(v);
    if (m == null) return null;
    final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    if (p[0] == 0 || p[1] < 1 || p[1] > 12 || p[2] < 1 || p[2] > 31) {
      return null;
    }
    if (p[3] > 23 || p[4] > 59 || p[5] > 60) return null;
    var ms = 0;
    if (subSec != null && RegExp(r'^\d+$').hasMatch(subSec)) {
      ms = int.parse(subSec.padRight(3, '0').substring(0, 3));
    }
    return DateTime(p[0], p[1], p[2], p[3], p[4], p[5], ms);
  }

  static final _offsetPattern = RegExp(r'^([+-])(\d{2}):(\d{2})$');

  Duration? _offset(String tag) {
    final v = _text(tag);
    if (v == null) return null;
    final m = _offsetPattern.firstMatch(v);
    if (m == null) return null;
    final d = Duration(
        hours: int.parse(m.group(2)!), minutes: int.parse(m.group(3)!));
    return m.group(1) == '-' ? -d : d;
  }

  @override
  String toString() => 'ExifData(format: ${format.name}, $tags)';
}
