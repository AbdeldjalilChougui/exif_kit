/// Image container detected by the reader.
enum ExifImageFormat {
  /// JPEG.
  jpeg(true),

  /// PNG (`eXIf` chunk).
  png(true),

  /// WebP (`EXIF` chunk).
  webp(true),

  /// HEIF / HEIC / AVIF. Read only.
  heif(false),

  /// DNG and other TIFF-based raw formats. Read only.
  dng(false),

  /// Anything else.
  unknown(false);

  const ExifImageFormat(this.isWritable);

  /// Whether androidx ExifInterface can save attributes to this format.
  final bool isWritable;

  /// Parses the platform name, returning [unknown] for anything else.
  static ExifImageFormat parse(String? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return unknown;
  }
}
