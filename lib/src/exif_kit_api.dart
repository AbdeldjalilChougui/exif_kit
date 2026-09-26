import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'exif_changes.dart';
import 'exif_data.dart';
import 'exif_orientation.dart';
import 'jpeg_exif_reader.dart';

/// Reads and writes EXIF metadata.
///
/// On Android every call goes through androidx ExifInterface (JPEG, PNG,
/// WebP, HEIF, DNG and the raw formats it supports). Elsewhere, and when the
/// plugin is not registered, reads fall back to [JpegExifReader] for JPEG
/// files; writes need Android.
///
/// Reads accept a file path or, on Android, a `content://` URI. **Writes need
/// a file path the app is allowed to write**, such as a file in the app's
/// own directories. Content URIs are refused with
/// [ExifWriteNotAllowedException]: copy the image to a writable file, edit
/// it, then save it back yourself.
abstract final class ExifKit {
  /// The platform channel. Exposed so tests can install a mock handler.
  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('dev.abdeldjalilchougui/exif_kit');

  static bool get _native =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _isUri(String s) => s.startsWith('content://');

  static void _checkSource(String source) {
    if (source.isEmpty) {
      throw const ExifInvalidArgumentException('Source must not be empty');
    }
  }

  /// Reads the EXIF metadata of [source], a file path or `content://` URI.
  ///
  /// On Android 10+ the system redacts GPS tags in media URIs unless the app
  /// holds `ACCESS_MEDIA_LOCATION`; pass [requireOriginal] to request the
  /// unredacted original (Android only, ignored for file paths).
  static Future<ExifData> read(
    String source, {
    bool requireOriginal = false,
  }) async {
    _checkSource(source);
    if (_native) {
      try {
        final map = await _invoke<Map<Object?, Object?>>('read', {
          'source': source,
          'requireOriginal': requireOriginal,
        });
        if (map == null) {
          throw const ExifPlatformException('read returned no data');
        }
        return ExifData.fromMap(map);
      } on MissingPluginException {
        // Fall through to the pure-Dart reader.
      }
    }
    if (_isUri(source)) {
      throw const ExifUnsupportedPlatformException(
          'content:// URIs can only be read on Android');
    }
    return readFile(source);
  }

  /// Reads a JPEG file with the pure-Dart reader on any platform.
  static Future<ExifData> readFile(String path) async =>
      JpegExifReader.read(await _readBytes(path));

  /// Parses in-memory JPEG [bytes] with the pure-Dart reader.
  static ExifData readBytes(Uint8List bytes) => JpegExifReader.read(bytes);

  /// Returns the embedded EXIF thumbnail of [source], or `null`.
  static Future<Uint8List?> thumbnail(
    String source, {
    bool requireOriginal = false,
  }) async {
    _checkSource(source);
    if (_native) {
      try {
        return await _invoke<Uint8List>('thumbnail', {
          'source': source,
          'requireOriginal': requireOriginal,
        });
      } on MissingPluginException {
        // Fall through.
      }
    }
    if (_isUri(source)) {
      throw const ExifUnsupportedPlatformException(
          'content:// URIs can only be read on Android');
    }
    return JpegExifReader.thumbnail(await _readBytes(source));
  }

  /// Clockwise rotation, in degrees, needed to display [source] upright.
  static Future<int> rotationDegrees(String source) async {
    _checkSource(source);
    if (_native) {
      try {
        return await _invoke<int>('rotationDegrees', {'source': source}) ?? 0;
      } on MissingPluginException {
        // Fall through.
      }
    }
    return (await read(source)).rotationDegrees;
  }

  /// Applies [changes] to the image at the absolute file [path], in place.
  ///
  /// Android only. Supported formats: JPEG, PNG and WebP (the formats
  /// ExifInterface can save). The app must be allowed to write [path].
  static Future<void> write(String path, ExifChanges changes) async {
    _checkSource(path);
    if (_isUri(path)) {
      throw const ExifWriteNotAllowedException(
          'Writing needs a file path the app can write, not a content:// URI');
    }
    if (!path.startsWith('/')) {
      throw ExifInvalidArgumentException('Expected an absolute path: $path');
    }
    if (changes.isEmpty) return;
    if (!_native) {
      throw const ExifUnsupportedPlatformException(
          'Writing EXIF is only supported on Android');
    }
    try {
      await _invoke<void>('write', {'path': path, 'changes': changes.toMap()});
    } on MissingPluginException {
      throw const ExifUnsupportedPlatformException(
          'exif_kit is not registered on this platform');
    }
  }

  /// Writes GPS coordinates (decimal degrees) and optional altitude (metres).
  static Future<void> setGps(
    String path, {
    required double latitude,
    required double longitude,
    double? altitude,
  }) =>
      write(
          path,
          ExifChanges()
            ..setGps(
                latitude: latitude, longitude: longitude, altitude: altitude));

  /// Removes every GPS tag.
  static Future<void> removeGps(String path) =>
      write(path, ExifChanges()..removeGps());

  /// Sets the orientation tag.
  static Future<void> setOrientation(
          String path, ExifOrientation orientation) =>
      write(path, ExifChanges()..setOrientation(orientation));

  /// Sets the capture time, see [ExifChanges.setDateTimeOriginal].
  static Future<void> setDateTimeOriginal(
    String path,
    DateTime dateTime, {
    Duration? offset,
  }) =>
      write(path, ExifChanges()..setDateTimeOriginal(dateTime, offset: offset));

  /// Privacy helper that removes metadata, see [ExifChanges.strip].
  static Future<void> strip(String path, {bool keepOrientation = true}) =>
      write(path, ExifChanges()..strip(keepOrientation: keepOrientation));

  static Future<Uint8List> _readBytes(String path) async {
    final file = File(path);
    try {
      return await file.readAsBytes();
    } on PathNotFoundException {
      throw ExifFileNotFoundException('No such file: $path');
    } on FileSystemException catch (e) {
      throw ExifIoException('${e.message}: $path');
    }
  }

  static Future<T?> _invoke<T>(String method, Object? arguments) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      final message = e.message ?? e.code;
      throw switch (e.code) {
        'FILE_NOT_FOUND' => ExifFileNotFoundException(message, code: e.code),
        'UNSUPPORTED_FORMAT' =>
          ExifUnsupportedFormatException(message, code: e.code),
        'PERMISSION_DENIED' =>
          ExifWriteNotAllowedException(message, code: e.code),
        'ACCESS_DENIED' => ExifAccessDeniedException(message, code: e.code),
        'INVALID_ARGUMENT' =>
          ExifInvalidArgumentException(message, code: e.code),
        'IO_ERROR' => ExifIoException(message, code: e.code),
        _ => ExifPlatformException(message, code: e.code),
      };
    }
  }
}
