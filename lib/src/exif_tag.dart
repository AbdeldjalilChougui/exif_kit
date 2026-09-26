/// EXIF tag names as used by androidx ExifInterface, for [ExifData.tags] and
/// `ExifChanges.set`.
abstract final class ExifTag {
  /// Camera maker.
  static const make = 'Make';

  /// Camera model.
  static const model = 'Model';

  /// Orientation, `1`-`8`.
  static const orientation = 'Orientation';

  /// Software that produced the file.
  static const software = 'Software';

  /// Last modification date, `YYYY:MM:DD HH:MM:SS`.
  static const dateTime = 'DateTime';

  /// Capture date, `YYYY:MM:DD HH:MM:SS`.
  static const dateTimeOriginal = 'DateTimeOriginal';

  /// Digitisation date, `YYYY:MM:DD HH:MM:SS`.
  static const dateTimeDigitized = 'DateTimeDigitized';

  /// UTC offset of [dateTime], `+HH:MM`.
  static const offsetTime = 'OffsetTime';

  /// UTC offset of [dateTimeOriginal], `+HH:MM`.
  static const offsetTimeOriginal = 'OffsetTimeOriginal';

  /// UTC offset of [dateTimeDigitized], `+HH:MM`.
  static const offsetTimeDigitized = 'OffsetTimeDigitized';

  /// Fractional seconds of [dateTimeOriginal], as digits.
  static const subSecTimeOriginal = 'SubSecTimeOriginal';

  /// Image description.
  static const imageDescription = 'ImageDescription';

  /// Photographer.
  static const artist = 'Artist';

  /// Copyright notice.
  static const copyright = 'Copyright';

  /// Owner name.
  static const cameraOwnerName = 'CameraOwnerName';

  /// Body serial number.
  static const bodySerialNumber = 'BodySerialNumber';

  /// Lens model.
  static const lensModel = 'LensModel';

  /// Exposure time in seconds.
  static const exposureTime = 'ExposureTime';

  /// Aperture f-number.
  static const fNumber = 'FNumber';

  /// ISO sensitivity.
  static const photographicSensitivity = 'PhotographicSensitivity';

  /// Legacy name of [photographicSensitivity].
  static const isoSpeedRatings = 'ISOSpeedRatings';

  /// Focal length in millimetres.
  static const focalLength = 'FocalLength';

  /// Width in pixels.
  static const imageWidth = 'ImageWidth';

  /// Height in pixels.
  static const imageLength = 'ImageLength';

  /// Valid image width.
  static const pixelXDimension = 'PixelXDimension';

  /// Valid image height.
  static const pixelYDimension = 'PixelYDimension';

  /// `N` or `S`.
  static const gpsLatitudeRef = 'GPSLatitudeRef';

  /// Latitude as degrees, minutes, seconds rationals.
  static const gpsLatitude = 'GPSLatitude';

  /// `E` or `W`.
  static const gpsLongitudeRef = 'GPSLongitudeRef';

  /// Longitude as degrees, minutes, seconds rationals.
  static const gpsLongitude = 'GPSLongitude';

  /// `0` above sea level, `1` below.
  static const gpsAltitudeRef = 'GPSAltitudeRef';

  /// Altitude in metres.
  static const gpsAltitude = 'GPSAltitude';

  /// UTC time of the GPS fix, `HH:MM:SS`.
  static const gpsTimeStamp = 'GPSTimeStamp';

  /// UTC date of the GPS fix, `YYYY:MM:DD`.
  static const gpsDateStamp = 'GPSDateStamp';
}
