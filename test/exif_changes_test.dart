import 'package:exif_kit/exif_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty changes', () {
    final c = ExifChanges();
    expect(c.isEmpty, isTrue);
    expect(c.toMap(), {
      'set': <String, String>{},
      'remove': <String>[],
      'gps': null,
      'removeGps': false,
      'strip': false,
      'keepOrientation': true,
    });
  });

  test('set and remove tags; last write wins', () {
    final c = ExifChanges()
      ..set(ExifTag.make, 'Acme')
      ..set(ExifTag.artist, 'Me')
      ..remove(ExifTag.artist)
      ..remove(ExifTag.software)
      ..set(ExifTag.software, 'v2');
    expect(c.toMap()['set'], {'Make': 'Acme', 'Software': 'v2'});
    expect(c.toMap()['remove'], ['Artist']);
    expect(c.isEmpty, isFalse);
  });

  test('empty tag names are rejected', () {
    expect(() => ExifChanges().set('', 'x'), throwsArgumentError);
    expect(() => ExifChanges().remove(''), throwsArgumentError);
  });

  test('setGps validates and serialises', () {
    final c = ExifChanges()
      ..setGps(latitude: 36.75, longitude: 3.06, altitude: -2);
    expect(c.toMap()['gps'],
        {'latitude': 36.75, 'longitude': 3.06, 'altitude': -2.0});
    expect(c.toMap()['removeGps'], isFalse);
    final noAlt = ExifChanges()..setGps(latitude: 0, longitude: 0);
    expect(noAlt.toMap()['gps'], {'latitude': 0.0, 'longitude': 0.0});
    expect(() => ExifChanges().setGps(latitude: 91, longitude: 0),
        throwsArgumentError);
    expect(() => ExifChanges().setGps(latitude: 0, longitude: -180.5),
        throwsArgumentError);
    expect(() => ExifChanges().setGps(latitude: double.nan, longitude: 0),
        throwsArgumentError);
  });

  test('removeGps clears a pending setGps', () {
    final c = ExifChanges()
      ..setGps(latitude: 1, longitude: 2)
      ..removeGps();
    expect(c.toMap()['gps'], isNull);
    expect(c.toMap()['removeGps'], isTrue);
  });

  test('setOrientation', () {
    final c = ExifChanges()..setOrientation(ExifOrientation.rotate90);
    expect(c.toMap()['set'], {'Orientation': '6'});
  });

  test('setDateTimeOriginal formats EXIF date, offset and sub-seconds', () {
    final c = ExifChanges()
      ..setDateTimeOriginal(DateTime(2024, 1, 2, 3, 4, 5, 70),
          offset: const Duration(hours: -4, minutes: -30));
    expect(c.toMap()['set'], {
      'DateTimeOriginal': '2024:01:02 03:04:05',
      'OffsetTimeOriginal': '-04:30',
      'SubSecTimeOriginal': '070',
    });
  });

  test('setDateTimeOriginal without offset or millis', () {
    final c = ExifChanges()
      ..setDateTimeOriginal(DateTime(1999, 12, 31, 23, 59, 59));
    expect(c.toMap()['set'], {'DateTimeOriginal': '1999:12:31 23:59:59'});
    expect(c.toMap()['remove'], ['OffsetTimeOriginal', 'SubSecTimeOriginal']);
  });

  test('setDateTimeOriginal rejects offsets outside +-14h or with seconds', () {
    expect(
        () => ExifChanges().setDateTimeOriginal(DateTime(2000),
            offset: const Duration(hours: 15)),
        throwsArgumentError);
    expect(
        () => ExifChanges().setDateTimeOriginal(DateTime(2000),
            offset: const Duration(seconds: 30)),
        throwsArgumentError);
  });

  test('strip', () {
    final c = ExifChanges()..strip(keepOrientation: false);
    expect(c.toMap()['strip'], isTrue);
    expect(c.toMap()['keepOrientation'], isFalse);
    expect(c.isEmpty, isFalse);
  });
}
