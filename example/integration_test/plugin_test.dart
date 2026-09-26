// Emulator integration test: reads and writes EXIF through the real plugin,
// then reads the same image back through MediaStore as a content:// URI.
// adb requests (media scan, permission grants) are served by
// tool/run_on_device.dart.
//
// Run from example/:
//   dart run tool/run_on_device.dart \
//     dev.abdeldjalilchougui.exif_kit_example emulator-5554

import 'dart:io';
import 'dart:ui' as ui;

import 'package:exif_kit/exif_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'adb_bridge.dart';

const _pkg = 'dev.abdeldjalilchougui.exif_kit_example';
const _files = '/data/data/$_pkg/files/it';
const _shared = '/storage/emulated/0/Pictures/exif_kit_it.jpg';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final adb = AdbBridge(_pkg);
  late String path;
  String? mediaUri;

  Future<String> copySample(String name) async {
    final data = await rootBundle.load('assets/sample.jpg');
    final file = File('$_files/$name');
    await file.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  Future<void> expectDecodable(String path) async {
    final codec =
        await ui.instantiateImageCodec(await File(path).readAsBytes());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(0));
    frame.image.dispose();
  }

  final taken = DateTime(2026, 9, 26, 14, 30, 15, 250);

  setUpAll(() async {
    path = await copySample('photo.jpg');
  });

  tearDownAll(() async {
    if (mediaUri != null) await adb.run('shell content delete --uri $mediaUri');
  });

  testWidgets('reads the bundled sample', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final data = await ExifKit.read(path);
    debugPrint('sample tags: ${data.tags}');
    // test/fixtures/generate_fixtures.py writes these values.
    expect(data.format, ExifImageFormat.jpeg);
    expect(data.make, 'Canon');
    expect(data.orientation, ExifOrientation.rotate90);
    expect(data.width, 64);
    expect(data.height, 48);
    expect(data.hasGps, isTrue);
    expect(await ExifKit.rotationDegrees(path), 90);
    // The native reader and the pure-Dart reader agree on the fixture.
    final dart = await ExifKit.readFile(path);
    expect(dart.latitude, closeTo(data.latitude!, 1e-6));
    expect(dart.longitude, closeTo(data.longitude!, 1e-6));
    expect(dart.dateTimeOriginal, data.dateTimeOriginal);
    expect(await ExifKit.thumbnail(path), isNull);
  });

  testWidgets('writes GPS, orientation and date, then reads them back',
      (tester) async {
    await ExifKit.setGps(path,
        latitude: 36.7538, longitude: -3.0588, altitude: 25.5);
    await ExifKit.setOrientation(path, ExifOrientation.rotate270);
    await ExifKit.setDateTimeOriginal(path, taken,
        offset: const Duration(hours: 1));
    await ExifKit.write(
        path,
        ExifChanges()
          ..set(ExifTag.make, 'exif_kit')
          ..set(ExifTag.model, 'emulator test'));

    final native = await ExifKit.read(path);
    // The pure-Dart reader parses the same bytes independently.
    final dart = await ExifKit.readFile(path);
    for (final data in [native, dart]) {
      debugPrint('after write: ${data.tags}');
      expect(data.latitude, closeTo(36.7538, 1e-4));
      expect(data.longitude, closeTo(-3.0588, 1e-4));
      expect(data.altitude, closeTo(25.5, 0.01));
      expect(data.orientation, ExifOrientation.rotate270);
      expect(data.rotationDegrees, 270);
      expect(data.dateTimeOriginal, taken);
      expect(data.offsetTimeOriginal, const Duration(hours: 1));
      expect(
          data.dateTimeOriginalUtc, DateTime.utc(2026, 9, 26, 13, 30, 15, 250));
      expect(data.make, 'exif_kit');
      expect(data.model, 'emulator test');
    }
    expect(await ExifKit.rotationDegrees(path), 270);
    await expectDecodable(path);
  });

  testWidgets('removeGps and strip remove what they promise', (tester) async {
    final copy = File('$_files/copy.jpg');
    await File(path).copy(copy.path);
    await ExifKit.removeGps(copy.path);
    final noGps = await ExifKit.read(copy.path);
    expect(noGps.hasGps, isFalse);
    expect(noGps.tags.keys.where((k) => k.startsWith('GPS')), isEmpty);
    expect(noGps.make, 'exif_kit');

    await ExifKit.strip(copy.path);
    final stripped = await ExifKit.read(copy.path);
    debugPrint('stripped: ${stripped.tags}');
    expect(stripped.hasGps, isFalse);
    expect(stripped.make, isNull);
    expect(stripped.dateTimeOriginal, isNull);
    expect(stripped.orientation, ExifOrientation.rotate270);
    expect((await ExifKit.readFile(copy.path)).hasGps, isFalse);

    await ExifKit.strip(copy.path, keepOrientation: false);
    expect((await ExifKit.read(copy.path)).orientation, isNull);
    await expectDecodable(copy.path);
  });

  testWidgets('strip on the geotagged photo removes GPS', (tester) async {
    final copy = File('$_files/strip.jpg');
    await File(path).copy(copy.path);
    expect((await ExifKit.read(copy.path)).hasGps, isTrue);
    await ExifKit.strip(copy.path);
    expect((await ExifKit.read(copy.path)).hasGps, isFalse);
    expect((await ExifKit.readFile(copy.path)).hasGps, isFalse);
  });

  testWidgets('a PNG without EXIF reads as no tags, not zeros', (tester) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 6),
        ui.Paint()..color = const ui.Color(0xFF2080C0));
    final image = await recorder.endRecording().toImage(8, 6);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_files/plain.png')
      ..writeAsBytesSync(png!.buffer.asUint8List());
    final data = await ExifKit.read(file.path);
    debugPrint('png tags: ${data.tags}');
    expect(data.format, ExifImageFormat.png);
    expect(data.width, isNot(0));
    expect(data.tags[ExifTag.orientation], isNot('0'));
    await ExifKit.setOrientation(file.path, ExifOrientation.rotate180);
    expect(
        (await ExifKit.read(file.path)).orientation, ExifOrientation.rotate180);
  });

  testWidgets('errors are typed on the device', (tester) async {
    await expectLater(ExifKit.read('$_files/missing.jpg'),
        throwsA(isA<ExifFileNotFoundException>()));
    final text = File('$_files/note.txt')..writeAsStringSync('not an image');
    // Regression: ExifInterface's "0" defaults used to come back as tags.
    await expectLater(ExifKit.read(text.path),
        throwsA(isA<ExifUnsupportedFormatException>()));
    await expectLater(ExifKit.setOrientation(text.path, ExifOrientation.normal),
        throwsA(isA<ExifUnsupportedFormatException>()));
    await expectLater(
        ExifKit.write('/system/etc/hosts', ExifChanges()..set('Make', 'x')),
        throwsA(isA<ExifWriteNotAllowedException>()));
  });

  testWidgets('reads a MediaStore content:// URI', (tester) async {
    // Publish the geotagged photo to shared storage and let MediaStore
    // index it. The row belongs to the shell, so this app needs
    // READ_MEDIA_IMAGES, and ACCESS_MEDIA_LOCATION for unredacted GPS.
    await adb.shell('"run-as $_pkg cat $_files/photo.jpg | cat > $_shared"');
    final local = await adb.shell('run-as $_pkg md5sum $_files/photo.jpg');
    final shared = await adb.shell('md5sum $_shared');
    expect(shared.split(' ').first, local.split(' ').first);
    await adb.shell(
        'content call --uri content://media --method scan_file --arg $_shared');
    final row = await adb.shell('content query --uri '
        'content://media/external/images/media --projection _id '
        '--where "_data=\\\'$_shared\\\'"');
    final id = RegExp(r'_id=(\d+)').firstMatch(row)!.group(1)!;
    final uri = 'content://media/external/images/media/$id';
    mediaUri = uri;

    await expectLater(
        ExifKit.read(uri), throwsA(isA<ExifAccessDeniedException>()),
        reason: 'no READ_MEDIA_IMAGES yet');

    await adb.shell('pm grant $_pkg android.permission.READ_MEDIA_IMAGES');
    final redacted = await ExifKit.read(uri);
    debugPrint('content:// without ACCESS_MEDIA_LOCATION: ${redacted.tags}');
    expect(redacted.format, ExifImageFormat.jpeg);
    expect(redacted.make, 'exif_kit');
    expect(redacted.orientation, ExifOrientation.rotate270);
    // Android zeroes GPS without ACCESS_MEDIA_LOCATION; that must not read
    // as a fix at 0, 0.
    expect(redacted.tags[ExifTag.gpsLatitude], '0/1,0/1,0/1');
    expect(redacted.hasGps, isFalse);
    await expectLater(ExifKit.read(uri, requireOriginal: true),
        throwsA(isA<ExifAccessDeniedException>()));

    await adb.shell('pm grant $_pkg android.permission.ACCESS_MEDIA_LOCATION');
    final original = await ExifKit.read(uri, requireOriginal: true);
    debugPrint('content:// original: ${original.tags}');
    expect(original.latitude, closeTo(36.7538, 1e-4));
    expect(original.longitude, closeTo(-3.0588, 1e-4));
    expect(original.dateTimeOriginal, taken);
    expect(await ExifKit.rotationDegrees(uri), 270);
    await expectLater(ExifKit.write(uri, ExifChanges()..set('Make', 'x')),
        throwsA(isA<ExifWriteNotAllowedException>()));
  });
}
