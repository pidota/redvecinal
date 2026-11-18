import 'dart:io';

import '../application/create_post_file_picker.dart';
import 'post_attachment_limits.dart';

String? validatePickedPostAttachmentFile(
  PickedPostFile file, {
  required int remainingSlots,
}) {
  if (file.sizeBytes > PostAttachmentLimits.maxSizeBytes) {
    return 'Cada archivo puede pesar hasta 5 MB.';
  }
  if (!PostAttachmentLimits.allowedMimeTypes.contains(file.mimeType)) {
    return 'Tipo de archivo no permitido.';
  }
  final ext = file.displayName.split('.').last.toLowerCase();
  if (!PostAttachmentLimits.allowedExtensions.contains(ext)) {
    return 'Extensión no permitida.';
  }
  if (!File(file.path).existsSync()) {
    return 'No se pudo acceder al archivo seleccionado.';
  }
  if (remainingSlots <= 0) {
    return 'Máximo ${PostAttachmentLimits.maxPerRevision} archivos por publicación.';
  }
  return null;
}
