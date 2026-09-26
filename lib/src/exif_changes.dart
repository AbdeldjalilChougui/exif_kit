import 'exif_orientation.dart';
import 'exif_tag.dart';

/// A batch of EXIF edits for `ExifKit.write`.
///
/// On the device the edits are applied in this order: [strip], [removeGps],
/// [setGps], tag removals, tag sets. Later calls on the same tag win.
class ExifChanges {
  final Map<String, String> _set = {};
  final Set<String> _remove = {};
  Map<String, double>? _gps;
  bool _removeGps = false;
  bool _strip = false;
  bool _keepOrientation = true;

  /// Whether no edit has been recorded.
  bool get isEmpty =>
      _set.isEmpty && _remove.isEmpty && _gps == null && !_removeGps && !_strip;

  /// Sets [tag] (an ExifInterface tag name, see [ExifTag]) to [value].
  void set(String tag, String value) {
    _checkTag(tag);
    _remove.remove(tag);
    _set[tag] = value;
  }

  /// Removes [tag].
  void remove(String tag) {
    _checkTag(tag);
    _set.remove(tag);
    _remove.add(tag);
  }

  /// Writes GPS latitude and longitude in decimal degrees, and optionally
  /// altitude in metres (negative below sea level).
  void setGps({
    required double latitude,
    required double longitude,
    double? altitude,
  }) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'Must be in -90..90');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(longitude, 'longitude', 'Must be in -180..180');
    }
    if (altitude != null && !altitude.isFinite) {
      throw ArgumentError.value(altitude, 'altitude', 'Must be finite');
    }
    _removeGps = false;
    _gps = {
      'latitude': latitude.toDouble(),
      'longitude': longitude.toDouble(),
      if (altitude != null) 'altitude': altitude.toDouble(),
    };
  }

  /// Removes every GPS tag.
  void removeGps() {
    _gps = null;
    _removeGps = true;
  }

  /// Sets the orientation tag.
  void setOrientation(ExifOrientation orientation) =>
      set(ExifTag.orientation, '${orientation.value}');

  /// Sets `DateTimeOriginal` from the wall-clock fields of [dateTime], plus
  /// `OffsetTimeOriginal` when [offset] is given and `SubSecTimeOriginal`
  /// when [dateTime] has milliseconds. Tags not set are removed so no stale
  /// offset remains.
  void setDateTimeOriginal(DateTime dateTime, {Duration? offset}) {
    if (offset != null) {
      if (offset.inSeconds % 60 != 0 || offset.inMinutes.abs() > 14 * 60) {
        throw ArgumentError.value(
            offset, 'offset', 'Must be whole minutes within +-14 hours');
      }
    }
    set(ExifTag.dateTimeOriginal, formatExifDate(dateTime));
    if (offset == null) {
      remove(ExifTag.offsetTimeOriginal);
    } else {
      set(ExifTag.offsetTimeOriginal, formatExifOffset(offset));
    }
    if (dateTime.millisecond == 0) {
      remove(ExifTag.subSecTimeOriginal);
    } else {
      set(ExifTag.subSecTimeOriginal,
          dateTime.millisecond.toString().padLeft(3, '0'));
    }
  }

  /// Privacy helper: removes every metadata tag ExifInterface knows,
  /// including GPS, camera serials, owner and dates. Structural tags needed
  /// to decode the image are kept, and so is orientation unless
  /// [keepOrientation] is false. Other edits in this batch are applied after
  /// stripping.
  void strip({bool keepOrientation = true}) {
    _strip = true;
    _keepOrientation = keepOrientation;
  }

  /// The platform payload.
  Map<String, Object?> toMap() => {
        'set': Map<String, String>.of(_set),
        'remove': _remove.toList(),
        'gps': _gps == null ? null : Map<String, double>.of(_gps!),
        'removeGps': _removeGps,
        'strip': _strip,
        'keepOrientation': _keepOrientation,
      };

  static void _checkTag(String tag) {
    if (tag.isEmpty) throw ArgumentError.value(tag, 'tag', 'Must not be empty');
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Formats [d] as an EXIF date, `YYYY:MM:DD HH:MM:SS`.
String formatExifDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}:'
    '${_two(d.month)}:${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}:'
    '${_two(d.second)}';

/// Formats [offset] as an EXIF offset, `+HH:MM` or `-HH:MM`.
String formatExifOffset(Duration offset) {
  final minutes = offset.inMinutes.abs();
  return '${offset.isNegative ? '-' : '+'}${_two(minutes ~/ 60)}:'
      '${_two(minutes % 60)}';
}
