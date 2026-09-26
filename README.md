# exif_kit

Read and write EXIF metadata (GPS, orientation, capture date with time-zone offset, camera
settings) through androidx ExifInterface, with a pure-Dart JPEG reader as a fallback.

[![pub package](https://img.shields.io/pub/v/exif_kit.svg)](https://pub.dev/packages/exif_kit)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Android only; iOS not supported.** Native read/write on Android; pure-Dart read fallback
elsewhere (JPEG files only, no writing).

## Features

- `ExifKit.read(pathOrUri)` returns `ExifData` with typed getters: `make`, `model`, `software`,
  `orientation`, `rotationDegrees`, `dateTimeOriginal`, `offsetTimeOriginal`,
  `dateTimeOriginalUtc`, `latitude`, `longitude`, `altitude`, `exposureTime`, `fNumber`, `iso`,
  `focalLength`, `width`, `height`, plus the raw `tags` map.
- Reads file paths and `content://` URIs (via `ContentResolver.openFileDescriptor`), including
  `MediaStore.setRequireOriginal` for unredacted GPS on Android 10+.
- Formats: whatever androidx ExifInterface 1.4 reads (JPEG, PNG, WebP, HEIF/HEIC/AVIF, DNG and
  several camera raw formats). Writing: JPEG, PNG and WebP.
- `ExifKit.write(path, ExifChanges)` for batch edits, and one-call helpers `setGps`, `removeGps`,
  `setOrientation`, `setDateTimeOriginal` and a `strip({keepOrientation})` privacy helper.
- `ExifKit.thumbnail(source)` and `ExifKit.rotationDegrees(source)`.
- `JpegExifReader` / `ExifKit.readFile` / `ExifKit.readBytes`: a dependency-free Dart reader for
  JPEG (IFD0, Exif, GPS and the IFD1 thumbnail, little- and big-endian) that produces the same
  tag strings as ExifInterface. Works in unit tests and on any platform with `dart:io`.
- Sealed, typed errors (`ExifFileNotFoundException`, `ExifAccessDeniedException`,
  `ExifWriteNotAllowedException`, `ExifUnsupportedFormatException`, ...).

## Install

```yaml
dependencies:
  exif_kit: ^0.1.0
```

## Usage

```dart
import 'package:exif_kit/exif_kit.dart';

Future<void> demo(String photoPath) async {
  final exif = await ExifKit.read(photoPath);
  print('${exif.make} ${exif.model}, ISO ${exif.iso}, f/${exif.fNumber}');
  print('Taken ${exif.dateTimeOriginal} (UTC ${exif.dateTimeOriginalUtc})');
  if (exif.hasGps) print('At ${exif.latitude}, ${exif.longitude}');
  print('Rotate by ${exif.rotationDegrees} degrees to display upright');

  // Edits: the path must be a file this app may write.
  await ExifKit.setGps(photoPath, latitude: 36.7538, longitude: 3.0588, altitude: 12);
  await ExifKit.setDateTimeOriginal(photoPath, DateTime(2026, 3, 1, 9, 30),
      offset: const Duration(hours: 1));

  // Several edits in one save.
  await ExifKit.write(
    photoPath,
    ExifChanges()
      ..strip() // keeps orientation by default
      ..set(ExifTag.copyright, '(c) 2026 Me'),
  );
}
```

### Content URIs

```dart
// Reading a MediaStore / document URI works on Android.
final exif = await ExifKit.read(
  'content://media/external/images/media/42',
  requireOriginal: true, // needs ACCESS_MEDIA_LOCATION on Android 10+
);
```

Reading another app's image needs `READ_MEDIA_IMAGES` (API 33+, `READ_EXTERNAL_STORAGE`
before). Without it, and for `requireOriginal: true` without `ACCESS_MEDIA_LOCATION`, `read`
throws `ExifAccessDeniedException`. Files that are not JPEG, PNG, WebP, HEIF or DNG throw
`ExifUnsupportedFormatException`.

### Writing needs a writable file path

`write`, `setGps`, `removeGps`, `setOrientation`, `setDateTimeOriginal` and `strip` edit the file
in place, so they need an **absolute file path that your app is allowed to write**: a file in
your app's own directories (`getApplicationDocumentsDirectory()`, the cache, `systemTemp`), or a
shared-storage file your app created or has write access to. They do **not** accept
`content://` URIs and throw `ExifWriteNotAllowedException` for them, and for files the app
cannot write. To edit a picked image, copy it to a file you own, edit that copy, then save it
where it needs to go (for example through MediaStore).

### Pure-Dart reader

```dart
final data = JpegExifReader.read(jpegBytes); // any platform
final thumb = JpegExifReader.thumbnail(jpegBytes);
```

## Limitations

- Android only; iOS not supported. On other platforms only reading JPEG files works, through
  the pure-Dart reader; writes throw `ExifUnsupportedPlatformException`.
- Writing is limited to JPEG, PNG and WebP (ExifInterface cannot save HEIF, DNG or raw files).
- `strip` removes the tags ExifInterface knows (including GPS, dates, camera, lens and body
  serials, owner, user comment, maker note and XMP), but ExifInterface re-writes the embedded
  EXIF thumbnail, which is a small copy of the original picture. Re-encode the image if you need
  that gone too.
- The pure-Dart reader handles JPEG only and a core tag set (IFD0, Exif, GPS, IFD1 thumbnail).
  It does not parse maker notes, XMP or IPTC.
- On Android 10+ GPS tags in media URIs are redacted unless the app holds
  `ACCESS_MEDIA_LOCATION` and passes `requireOriginal: true`.

## Data sources

The JPEG files in `test/fixtures/` are synthetic solid-colour images created for this package
by `test/fixtures/generate_fixtures.py`, with EXIF written by
[Pillow](https://python-pillow.org/) (used only as a tool; no Pillow code or images are
shipped). No third-party images are included. `example/assets/sample.jpg` is a copy of
`test/fixtures/pillow_ii.jpg`.

## License

MIT. See [LICENSE](LICENSE).

Made by [Abdeldjalil Chougui](https://abdeldjalilchougui.biz/).
