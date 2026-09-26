/// Base type for every error thrown by `exif_kit`.
///
/// The family is sealed, so a `switch` over it is exhaustive.
sealed class ExifKitException implements Exception {
  const ExifKitException(this.message, {this.code});

  /// Human-readable description.
  final String message;

  /// The platform error code, when the error came from the platform.
  final String? code;

  @override
  String toString() => '$runtimeType(${code == null ? '' : '$code: '}$message)';
}

/// The file or content URI does not exist.
final class ExifFileNotFoundException extends ExifKitException {
  /// Creates the exception.
  const ExifFileNotFoundException(super.message, {super.code});
}

/// The image format is not supported for this operation (for example writing
/// to HEIF or DNG, or reading a non-JPEG with the pure-Dart reader).
final class ExifUnsupportedFormatException extends ExifKitException {
  /// Creates the exception.
  const ExifUnsupportedFormatException(super.message, {super.code});
}

/// Writing was refused: the target is a content URI, or the app lacks write
/// access to the file.
final class ExifWriteNotAllowedException extends ExifKitException {
  /// Creates the exception.
  const ExifWriteNotAllowedException(super.message, {super.code});
}

/// An argument was invalid (empty path, relative path, out-of-range value).
final class ExifInvalidArgumentException extends ExifKitException {
  /// Creates the exception.
  const ExifInvalidArgumentException(super.message, {super.code});
}

/// The EXIF data is malformed.
final class ExifFormatException extends ExifKitException {
  /// Creates the exception.
  const ExifFormatException(super.message, {super.code});
}

/// Reading or writing failed with an I/O error.
final class ExifIoException extends ExifKitException {
  /// Creates the exception.
  const ExifIoException(super.message, {super.code});
}

/// The operation needs the Android implementation and is not available on the
/// current platform.
final class ExifUnsupportedPlatformException extends ExifKitException {
  /// Creates the exception.
  const ExifUnsupportedPlatformException(super.message, {super.code});
}

/// Any other platform failure.
final class ExifPlatformException extends ExifKitException {
  /// Creates the exception.
  const ExifPlatformException(super.message, {super.code});
}
