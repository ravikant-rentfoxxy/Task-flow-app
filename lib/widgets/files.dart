import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Opens the OS picker and returns the chosen files' names and bytes.
Future<List<({String name, Uint8List bytes})>> pickFilesAsBytes({FileType type = FileType.any}) async {
  final files = await FilePicker.pickFiles(type: type);
  final out = <({String name, Uint8List bytes})>[];
  for (final f in files) {
    out.add((name: f.name, bytes: await f.xFile.readAsBytes()));
  }
  return out;
}

/// Save dialog; returns false if the user cancelled.
Future<bool> saveBytes(String fileName, Uint8List bytes, {String mimeType = 'application/octet-stream'}) async {
  final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
  return uri != null;
}
