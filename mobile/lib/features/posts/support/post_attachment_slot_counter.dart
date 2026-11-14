import '../application/create_post_local_attachment.dart';
import '../application/create_post_uncertain_upload_record.dart';
import 'post_attachment_limits.dart';

/// Conteo de cupos sin doble contar IDs ya presentes en el servidor.
abstract final class PostAttachmentSlotCounter {
  static int occupiedSlots({
    required List<int> serverAttachmentIds,
    required List<CreatePostLocalAttachment> localItems,
    required List<CreatePostUncertainUploadRecord> uncertainRecords,
  }) {
    final serverIds = serverAttachmentIds.toSet();
    var extra = 0;

    final localClientIds = <String>{};
    for (final item in localItems) {
      localClientIds.add(item.clientId);
      final id = item.serverAttachmentId;
      if (id != null && serverIds.contains(id)) {
        continue;
      }
      extra++;
    }

    for (final record in uncertainRecords) {
      if (localClientIds.contains(record.clientId)) {
        continue;
      }
      extra++;
    }

    return serverIds.length + extra;
  }

  static int remainingSlots({
    required List<int> serverAttachmentIds,
    required List<CreatePostLocalAttachment> localItems,
    required List<CreatePostUncertainUploadRecord> uncertainRecords,
  }) {
    final occupied = occupiedSlots(
      serverAttachmentIds: serverAttachmentIds,
      localItems: localItems,
      uncertainRecords: uncertainRecords,
    );
    final remaining = PostAttachmentLimits.maxPerRevision - occupied;
    return remaining < 0 ? 0 : remaining;
  }
}
