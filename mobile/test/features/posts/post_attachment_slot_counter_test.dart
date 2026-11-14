import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/application/create_post_local_attachment.dart';
import 'package:red_vecinal/features/posts/application/create_post_uncertain_upload_record.dart';
import 'package:red_vecinal/features/posts/support/post_attachment_slot_counter.dart';

void main() {
  test('H: 3 servidor + 2 locales sin doble conteo', () {
    final remaining = PostAttachmentSlotCounter.remainingSlots(
      serverAttachmentIds: [1, 2, 3],
      localItems: [
        CreatePostLocalAttachment(
          clientId: 'a',
          path: '/a',
          displayName: 'a.pdf',
          sizeBytes: 1,
          mimeType: 'application/pdf',
          state: CreatePostAttachmentState.selected,
        ),
        CreatePostLocalAttachment(
          clientId: 'b',
          path: '/b',
          displayName: 'b.pdf',
          sizeBytes: 1,
          mimeType: 'application/pdf',
          state: CreatePostAttachmentState.selected,
        ),
      ],
      uncertainRecords: const [],
    );
    expect(remaining, 0);
  });

  test('H: uploaded local con id en servidor no duplica', () {
    final remaining = PostAttachmentSlotCounter.remainingSlots(
      serverAttachmentIds: [10, 11],
      localItems: [
        CreatePostLocalAttachment(
          clientId: 'u',
          path: '/u',
          displayName: 'u.pdf',
          sizeBytes: 1,
          mimeType: 'application/pdf',
          state: CreatePostAttachmentState.uploaded,
          serverAttachmentId: 10,
        ),
      ],
      uncertainRecords: const [],
    );
    expect(remaining, 3);
  });

  test('incertidumbre persistida reserva cupo', () {
    final remaining = PostAttachmentSlotCounter.remainingSlots(
      serverAttachmentIds: const [],
      localItems: const [],
      uncertainRecords: [
        CreatePostUncertainUploadRecord(
          clientId: 'x',
          displayName: 'x.pdf',
          sizeBytes: 1,
          mimeType: 'application/pdf',
        ),
      ],
    );
    expect(remaining, 4);
  });
}
