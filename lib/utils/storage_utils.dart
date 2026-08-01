import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

enum StorageFileType {
  any,
  media,
  image,
  video,
  audio,
  custom,
}

extension StorageFileTypeExtension on StorageFileType {
  FileType get toFilePicker => FileType.values[index];
}

abstract final class StorageUtils {
  static Future<List<PlatformFile>?> pickFiles({
    StorageFileType type = StorageFileType.any,
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type.toFilePicker,
      allowedExtensions: allowedExtensions,
    );
    return result?.files;
  }

  static Future<String?> getDirectoryPath() =>
      FilePicker.platform.getDirectoryPath();

  static Future<String?> saveFile({
    required String fileName,
    required List<String> allowedExtensions,
    StorageFileType type = StorageFileType.custom,
    Uint8List? bytes,
  }) =>
      FilePicker.platform.saveFile(
        fileName: fileName,
        allowedExtensions: allowedExtensions,
        type: type.toFilePicker,
        bytes: bytes,
      );

  static Future<String?> saveBytes2File({
    required String name,
    required Uint8List bytes,
    required List<String> allowedExtensions,
    StorageFileType type = StorageFileType.custom,
  }) async {
    try {
      final path = await saveFile(
        fileName: name,
        allowedExtensions: allowedExtensions,
        type: type,
        bytes: bytes,
      );
      if (path == null) {
        SmartDialog.showToast("取消保存");
        return null;
      }
      await File(path).writeAsBytes(bytes);
      SmartDialog.showToast("已保存");
      return path;
    } catch (e) {
      SmartDialog.showToast("保存失败: $e");
      return null;
    }
  }
}
