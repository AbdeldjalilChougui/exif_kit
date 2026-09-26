import 'dart:convert';
import 'dart:typed_data';

/// Test-only TIFF/EXIF writer: builds APP1 payloads with exact, known values
/// in either byte order, independent of the reader under test.
class TiffEntry {
  TiffEntry._(this.tag, this.type, this.count, this.values);

  factory TiffEntry.ascii(int tag, String s) {
    final bytes = [...latin1.encode(s), 0];
    return TiffEntry._(tag, 2, bytes.length, bytes);
  }

  factory TiffEntry.byte(int tag, List<int> v) =>
      TiffEntry._(tag, 1, v.length, v);

  factory TiffEntry.undefined(int tag, List<int> v) =>
      TiffEntry._(tag, 7, v.length, v);

  factory TiffEntry.short(int tag, List<int> v) =>
      TiffEntry._(tag, 3, v.length, v);

  factory TiffEntry.long(int tag, List<int> v) =>
      TiffEntry._(tag, 4, v.length, v);

  /// Each rational is `[numerator, denominator]`.
  factory TiffEntry.rational(int tag, List<List<int>> v) =>
      TiffEntry._(tag, 5, v.length, [for (final r in v) ...r]);

  factory TiffEntry.srational(int tag, List<List<int>> v) =>
      TiffEntry._(tag, 10, v.length, [for (final r in v) ...r]);

  final int tag;
  final int type;
  final int count;
  final List<int> values;

  List<int> encode(Endian e) {
    final out = <int>[];
    void put(int size, int v) {
      final b = ByteData(size);
      switch (size) {
        case 1:
          b.setUint8(0, v & 0xFF);
        case 2:
          b.setUint16(0, v, e);
        case 4:
          b.setInt32(0, v, e);
      }
      out.addAll(b.buffer.asUint8List());
    }

    switch (type) {
      case 1 || 2 || 7:
        for (final v in values) {
          put(1, v);
        }
      case 3:
        for (final v in values) {
          put(2, v);
        }
      case 4 || 5 || 10:
        for (final v in values) {
          put(4, v);
        }
    }
    return out;
  }
}

class TiffIfd {
  TiffIfd(this.entries);

  final List<TiffEntry> entries;
  final Map<int, TiffIfd> children = {};
  TiffIfd? next;
  List<int>? thumbnail;
}

class _Out {
  final bytes = <int>[];
  final Endian e;
  _Out(this.e);

  int get length => bytes.length;

  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, e);
    bytes.addAll(b.buffer.asUint8List());
  }

  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, e);
    bytes.addAll(b.buffer.asUint8List());
  }

  void patch32(int at, int v) {
    final b = ByteData(4)..setUint32(0, v, e);
    bytes.setRange(at, at + 4, b.buffer.asUint8List());
  }
}

int _writeIfd(_Out out, TiffIfd ifd) {
  final e = out.e;
  final all = <TiffEntry>[
    ...ifd.entries,
    for (final tag in ifd.children.keys) TiffEntry.long(tag, [0]),
    if (ifd.thumbnail != null) ...[
      TiffEntry.long(0x0201, [0]),
      TiffEntry.long(0x0202, [ifd.thumbnail!.length]),
    ],
  ]..sort((a, b) => a.tag.compareTo(b.tag));

  final start = out.length;
  out.u16(all.length);
  final valuePos = <int, int>{};
  final pending = <int, List<int>>{};
  for (final entry in all) {
    out
      ..u16(entry.tag)
      ..u16(entry.type)
      ..u32(entry.count);
    final data = entry.encode(e);
    valuePos[entry.tag] = out.length;
    if (data.length <= 4) {
      out.bytes.addAll([...data, ...List.filled(4 - data.length, 0)]);
    } else {
      pending[out.length] = data;
      out.u32(0);
    }
  }
  final nextPos = out.length;
  out.u32(0);
  for (final p in pending.entries) {
    out.patch32(p.key, out.length);
    out.bytes.addAll(p.value);
    if (out.length.isOdd) out.bytes.add(0);
  }
  for (final c in ifd.children.entries) {
    final at = _writeIfd(out, c.value);
    out.patch32(valuePos[c.key]!, at);
  }
  if (ifd.thumbnail != null) {
    out.patch32(valuePos[0x0201]!, out.length);
    out.bytes.addAll(ifd.thumbnail!);
  }
  if (ifd.next != null) {
    out.patch32(nextPos, _writeIfd(out, ifd.next!));
  }
  return start;
}

/// Serialises a TIFF structure rooted at [ifd0].
Uint8List buildTiff(TiffIfd ifd0, {required bool littleEndian}) {
  final out = _Out(littleEndian ? Endian.little : Endian.big);
  out.bytes.addAll(littleEndian ? [0x49, 0x49] : [0x4D, 0x4D]);
  out
    ..u16(42)
    ..u32(8);
  _writeIfd(out, ifd0);
  return Uint8List.fromList(out.bytes);
}

List<int> _segment(int marker, List<int> payload) {
  final len = payload.length + 2;
  return [0xFF, marker, len >> 8, len & 0xFF, ...payload];
}

/// A structurally valid JPEG header: SOI, optional APP0/XMP, APP1 Exif, SOF0
/// with [width] x [height], an empty SOS and EOI. No pixel data is needed by
/// the reader.
Uint8List buildJpeg({
  Uint8List? tiff,
  int width = 640,
  int height = 480,
  bool withJfif = true,
  bool withXmpFirst = false,
}) {
  return Uint8List.fromList([
    0xFF,
    0xD8,
    if (withJfif)
      ..._segment(0xE0, [
        ...ascii.encode('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, //
      ]),
    if (withXmpFirst)
      ..._segment(0xE1, [
        ...ascii.encode('http://ns.adobe.com/xap/1.0/'),
        0,
        ...ascii.encode('<x:xmpmeta/>'),
      ]),
    if (tiff != null)
      ..._segment(0xE1, [...ascii.encode('Exif'), 0, 0, ...tiff]),
    ..._segment(0xC0, [
      8, height >> 8, height & 0xFF, width >> 8, width & 0xFF, 3, //
      1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1,
    ]),
    ..._segment(0xDA, [3, 1, 0, 2, 0x11, 3, 0x11, 0, 0x3F, 0]),
    0x00,
    0xFF,
    0xD9,
  ]);
}

/// A full camera-like EXIF tree used by several tests.
TiffIfd sampleIfd0({List<int>? thumbnail}) {
  final ifd0 = TiffIfd([
    TiffEntry.ascii(0x010F, 'FUJIFILM'),
    TiffEntry.ascii(0x0110, 'X-T4'),
    TiffEntry.short(0x0112, [3]),
    TiffEntry.ascii(0x0131, 'Digital Camera X-T4 Ver2.00'),
    TiffEntry.ascii(0x0132, '2023:08:15 10:20:30'),
  ]);
  ifd0.children[0x8769] = TiffIfd([
    TiffEntry.rational(0x829A, [
      [1, 250],
    ]),
    TiffEntry.rational(0x829D, [
      [56, 10],
    ]),
    TiffEntry.short(0x8827, [800]),
    TiffEntry.ascii(0x9003, '2023:08:15 10:20:30'),
    TiffEntry.ascii(0x9011, '+09:00'),
    TiffEntry.ascii(0x9291, '5'),
    TiffEntry.rational(0x920A, [
      [230, 10],
    ]),
    TiffEntry.long(0xA002, [6240]),
    TiffEntry.long(0xA003, [4160]),
  ]);
  ifd0.children[0x8825] = TiffIfd([
    TiffEntry.byte(0x0000, [2, 3, 0, 0]),
    TiffEntry.ascii(0x0001, 'N'),
    TiffEntry.rational(0x0002, [
      [35, 1],
      [39, 1],
      [3120, 100],
    ]),
    TiffEntry.ascii(0x0003, 'E'),
    TiffEntry.rational(0x0004, [
      [139, 1],
      [41, 1],
      [4, 1],
    ]),
    TiffEntry.byte(0x0005, [0]),
    TiffEntry.rational(0x0006, [
      [405, 10],
    ]),
    TiffEntry.rational(0x0007, [
      [1, 1],
      [20, 1],
      [30, 1],
    ]),
    TiffEntry.ascii(0x001D, '2023:08:15'),
  ]);
  if (thumbnail != null) {
    ifd0.next = TiffIfd([
      TiffEntry.short(0x0103, [6]),
    ])
      ..thumbnail = thumbnail;
  }
  return ifd0;
}
