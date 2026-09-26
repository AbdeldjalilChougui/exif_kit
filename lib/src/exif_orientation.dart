/// The eight EXIF orientation values (tag 0x0112).
enum ExifOrientation {
  /// 1: stored upright.
  normal(1, 0, false),

  /// 2: mirrored left to right.
  flipHorizontal(2, 0, true),

  /// 3: rotated 180 degrees.
  rotate180(3, 180, false),

  /// 4: mirrored top to bottom.
  flipVertical(4, 180, true),

  /// 5: mirrored along the top-left / bottom-right diagonal.
  transpose(5, 90, true),

  /// 6: display after rotating 90 degrees clockwise.
  rotate90(6, 90, false),

  /// 7: mirrored along the top-right / bottom-left diagonal.
  transverse(7, 270, true),

  /// 8: display after rotating 270 degrees clockwise.
  rotate270(8, 270, false);

  const ExifOrientation(this.value, this.rotationDegrees, this.isFlipped);

  /// The EXIF value, 1 to 8.
  final int value;

  /// Clockwise rotation needed to display the image upright, matching
  /// androidx `ExifInterface.getRotationDegrees()`.
  final int rotationDegrees;

  /// Whether a mirror is needed in addition to the rotation.
  final bool isFlipped;

  /// Returns the orientation for an EXIF [value], or `null` if it is not 1-8.
  static ExifOrientation? fromValue(int? value) {
    for (final o in values) {
      if (o.value == value) return o;
    }
    return null;
  }
}
