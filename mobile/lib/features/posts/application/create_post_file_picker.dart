import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class PickedPostFile {
  const PickedPostFile({
    required this.path,
    required this.displayName,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String path;
  final String displayName;
  final int sizeBytes;
  final String mimeType;
}

abstract class CreatePostFilePickerPort {
  Future<PickedPostFile?> pickImage();
  Future<PickedPostFile?> pickPdf();
}

class CreatePostFilePicker implements CreatePostFilePickerPort {
  CreatePostFilePicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<PickedPostFile?> pickImage() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) {
      return null;
    }
    return _fromXFile(file);
  }

  @override
  Future<PickedPostFile?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withReadStream: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final platformFile = result.files.single;
    final path = platformFile.path;
    if (path == null || path.isEmpty) {
      return null;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final name =
        platformFile.name.isNotEmpty ? platformFile.name : 'documento.pdf';
    final mime = lookupMimeType(path) ?? 'application/pdf';
    return PickedPostFile(
      path: path,
      displayName: name,
      sizeBytes: platformFile.size,
      mimeType: mime,
    );
  }

  Future<PickedPostFile?> _fromXFile(XFile file) async {
    final path = file.path;
    if (path.isEmpty) {
      return null;
    }
    final dartFile = File(path);
    if (!dartFile.existsSync()) {
      return null;
    }
    final name = file.name.isNotEmpty ? file.name : 'imagen.jpg';
    final mime = lookupMimeType(path) ?? 'image/jpeg';
    return PickedPostFile(
      path: path,
      displayName: name,
      sizeBytes: await dartFile.length(),
      mimeType: mime,
    );
  }
}

final createPostFilePickerProvider = Provider<CreatePostFilePickerPort>((ref) {
  return CreatePostFilePicker();
});
