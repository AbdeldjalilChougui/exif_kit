import 'dart:io';

import 'package:exif_kit/exif_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MaterialApp(home: ExifPage()));

/// Copies a bundled sample JPEG to a writable file, then reads and edits it.
class ExifPage extends StatefulWidget {
  /// Creates the page.
  const ExifPage({super.key});

  @override
  State<ExifPage> createState() => _ExifPageState();
}

class _ExifPageState extends State<ExifPage> {
  String? _path;
  ExifData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // Writing needs a file the app owns; the temp directory is one.
    final bytes = await rootBundle.load('assets/sample.jpg');
    final file = File('${Directory.systemTemp.path}/exif_kit_sample.jpg');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    _path = file.path;
    await _reload();
  }

  Future<void> _reload() async {
    try {
      final data = await ExifKit.read(_path!);
      setState(() {
        _data = data;
        _error = null;
      });
    } on ExifKitException catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function(String path) edit) async {
    try {
      await edit(_path!);
      await _reload();
    } on ExifKitException catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('exif_kit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (d != null) ...[
            Text('${d.make ?? '?'} ${d.model ?? ''}  (${d.format.name})'),
            Text('Taken: ${d.dateTimeOriginal} offset ${d.offsetTimeOriginal}'),
            Text('GPS: ${d.latitude}, ${d.longitude}, ${d.altitude} m'),
            Text(
                'Rotation: ${d.rotationDegrees}°  ISO ${d.iso}  f/${d.fNumber}'),
            const Divider(),
            for (final e in d.tags.entries) Text('${e.key}: ${e.value}'),
          ],
          const Divider(),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => _run((p) => ExifKit.setGps(p,
                    latitude: 36.7538, longitude: 3.0588, altitude: 12)),
                child: const Text('Set GPS'),
              ),
              FilledButton(
                onPressed: () => _run(ExifKit.removeGps),
                child: const Text('Remove GPS'),
              ),
              FilledButton(
                onPressed: () => _run(
                    (p) => ExifKit.setOrientation(p, ExifOrientation.normal)),
                child: const Text('Upright'),
              ),
              FilledButton(
                onPressed: () => _run((p) => ExifKit.setDateTimeOriginal(
                    p, DateTime.now(),
                    offset: DateTime.now().timeZoneOffset)),
                child: const Text('Date = now'),
              ),
              FilledButton(
                onPressed: () => _run(ExifKit.strip),
                child: const Text('Strip'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
