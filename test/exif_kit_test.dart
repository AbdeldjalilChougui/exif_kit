import 'dart:io';

import 'package:exif_kit/exif_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) respond = (_) => null;

  setUp(() {
    calls.clear();
    respond = (_) => null;
    messenger.setMockMethodCallHandler(ExifKit.channel, (call) async {
      calls.add(call);
      return respond(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(ExifKit.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('channel name', () {
    expect(ExifKit.channel.name, 'dev.abdeldjalilchougui/exif_kit');
  });

  group('read', () {
    test('file path goes to native "read"', () async {
      respond = (_) => {
            'tags': {'Make': 'Google', 'Model': 'Pixel 8', 'Orientation': '6'},
            'format': 'jpeg',
            'hasThumbnail': false,
          };
      final d = await ExifKit.read('/sdcard/DCIM/a.jpg');
      expect(calls.single.method, 'read');
      expect(calls.single.arguments,
          {'source': '/sdcard/DCIM/a.jpg', 'requireOriginal': false});
      expect(d.model, 'Pixel 8');
      expect(d.rotationDegrees, 90);
    });

    test('content:// URIs are accepted with requireOriginal', () async {
      respond = (_) => {'tags': <String, String>{}, 'format': 'heif'};
      await ExifKit.read('content://media/external/images/media/42',
          requireOriginal: true);
      expect(calls.single.arguments, {
        'source': 'content://media/external/images/media/42',
        'requireOriginal': true,
      });
    });

    test('empty source is rejected locally', () async {
      await expectLater(
          ExifKit.read(''), throwsA(isA<ExifInvalidArgumentException>()));
      expect(calls, isEmpty);
    });

    test('native error codes map to typed exceptions', () async {
      final cases = <String, Matcher>{
        'FILE_NOT_FOUND': isA<ExifFileNotFoundException>(),
        'UNSUPPORTED_FORMAT': isA<ExifUnsupportedFormatException>(),
        'PERMISSION_DENIED': isA<ExifWriteNotAllowedException>(),
        'INVALID_ARGUMENT': isA<ExifInvalidArgumentException>(),
        'IO_ERROR': isA<ExifIoException>(),
        'SOMETHING': isA<ExifPlatformException>(),
      };
      for (final c in cases.entries) {
        respond = (_) => throw PlatformException(code: c.key, message: 'm');
        await expectLater(ExifKit.read('/x.jpg'), throwsA(c.value),
            reason: c.key);
      }
    });

    test('non-Android platforms use the pure-Dart reader', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final d = await ExifKit.read('test/fixtures/pillow_ii.jpg');
      expect(calls, isEmpty);
      expect(d.make, 'Canon');
    });

    test('non-Android platforms cannot read content URIs', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await expectLater(ExifKit.read('content://x/1'),
          throwsA(isA<ExifUnsupportedPlatformException>()));
    });

    test('missing plugin falls back to the pure-Dart reader', () async {
      messenger.setMockMethodCallHandler(ExifKit.channel, null);
      final d = await ExifKit.read('test/fixtures/pillow_mm.jpg');
      expect(d.make, 'NIKON CORPORATION');
    });

    test('readBytes parses in memory', () {
      final bytes = File('test/fixtures/pillow_ii.jpg').readAsBytesSync();
      expect(ExifKit.readBytes(bytes).iso, 400);
    });
  });

  group('write', () {
    test('sends path and serialised changes', () async {
      await ExifKit.write('/data/user/0/app/files/a.jpg',
          ExifChanges()..set(ExifTag.make, 'X'));
      expect(calls.single.method, 'write');
      final args = calls.single.arguments as Map;
      expect(args['path'], '/data/user/0/app/files/a.jpg');
      expect((args['changes'] as Map)['set'], {'Make': 'X'});
    });

    test('content URIs are refused before reaching native', () async {
      await expectLater(
        ExifKit.write('content://media/external/images/media/1',
            ExifChanges()..set(ExifTag.make, 'X')),
        throwsA(isA<ExifWriteNotAllowedException>()),
      );
      expect(calls, isEmpty);
    });

    test('relative paths are refused', () async {
      await expectLater(
          ExifKit.write('a.jpg', ExifChanges()..set(ExifTag.make, 'X')),
          throwsA(isA<ExifInvalidArgumentException>()));
    });

    test('empty changes are a no-op', () async {
      await ExifKit.write('/a.jpg', ExifChanges());
      expect(calls, isEmpty);
    });

    test('writing is unsupported off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await expectLater(
          ExifKit.write('/a.jpg', ExifChanges()..set(ExifTag.make, 'X')),
          throwsA(isA<ExifUnsupportedPlatformException>()));
      expect(calls, isEmpty);
    });

    test('missing plugin while writing is unsupported', () async {
      messenger.setMockMethodCallHandler(ExifKit.channel, null);
      await expectLater(
          ExifKit.write('/a.jpg', ExifChanges()..set(ExifTag.make, 'X')),
          throwsA(isA<ExifUnsupportedPlatformException>()));
    });

    test('PERMISSION_DENIED maps to ExifWriteNotAllowedException', () async {
      respond = (_) =>
          throw PlatformException(code: 'PERMISSION_DENIED', message: 'EACCES');
      await expectLater(
          ExifKit.write('/sdcard/DCIM/a.jpg', ExifChanges()..removeGps()),
          throwsA(isA<ExifWriteNotAllowedException>()
              .having((e) => e.message, 'message', 'EACCES')));
    });

    test('convenience helpers build the right changes', () async {
      await ExifKit.setGps('/a.jpg',
          latitude: 1.5, longitude: -2.5, altitude: 3);
      await ExifKit.removeGps('/a.jpg');
      await ExifKit.setOrientation('/a.jpg', ExifOrientation.rotate180);
      await ExifKit.setDateTimeOriginal(
          '/a.jpg', DateTime(2021, 6, 7, 8, 9, 10),
          offset: const Duration(hours: 2));
      await ExifKit.strip('/a.jpg');
      await ExifKit.strip('/a.jpg', keepOrientation: false);
      Map<Object?, Object?> ch(int i) =>
          (calls[i].arguments as Map)['changes'] as Map<Object?, Object?>;
      expect(calls.map((c) => c.method), everyElement('write'));
      expect(
          ch(0)['gps'], {'latitude': 1.5, 'longitude': -2.5, 'altitude': 3.0});
      expect(ch(1)['removeGps'], isTrue);
      expect(ch(2)['set'], {'Orientation': '3'});
      expect(ch(3)['set'], {
        'DateTimeOriginal': '2021:06:07 08:09:10',
        'OffsetTimeOriginal': '+02:00',
      });
      expect(ch(4)['strip'], isTrue);
      expect(ch(4)['keepOrientation'], isTrue);
      expect(ch(5)['keepOrientation'], isFalse);
    });
  });

  group('thumbnail', () {
    test('returns native bytes', () async {
      respond = (_) => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
      final t = await ExifKit.thumbnail('content://x/1');
      expect(calls.single.method, 'thumbnail');
      expect(calls.single.arguments,
          {'source': 'content://x/1', 'requireOriginal': false});
      expect(t, [0xFF, 0xD8, 0xFF, 0xD9]);
    });

    test('null when there is none', () async {
      respond = (_) => null;
      expect(await ExifKit.thumbnail('/a.jpg'), isNull);
    });

    test('pure-Dart fallback off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(await ExifKit.thumbnail('test/fixtures/no_exif.jpg'), isNull);
    });
  });

  group('rotationDegrees', () {
    test('uses native', () async {
      respond = (_) => 270;
      expect(await ExifKit.rotationDegrees('/a.jpg'), 270);
      expect(calls.single.method, 'rotationDegrees');
    });

    test('pure-Dart fallback off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(await ExifKit.rotationDegrees('test/fixtures/pillow_ii.jpg'), 90);
    });
  });

  test('exception family is sealed', () {
    const ExifKitException e = ExifIoException('boom', code: 'IO_ERROR');
    final label = switch (e) {
      ExifFileNotFoundException() => 'nf',
      ExifUnsupportedFormatException() => 'fmt',
      ExifWriteNotAllowedException() => 'deny',
      ExifInvalidArgumentException() => 'arg',
      ExifFormatException() => 'bad',
      ExifIoException() => 'io',
      ExifUnsupportedPlatformException() => 'platform',
      ExifPlatformException() => 'other',
    };
    expect(label, 'io');
    expect(e.toString(), contains('boom'));
  });
}
