import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/presentation/widgets/post_attachment_list.dart';

import 'post_test_support.dart';

void main() {
  testWidgets('muestra adjuntos y dispara descarga', (tester) async {
    PostAttachment? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostAttachmentList(
            attachments: sampleCommunityPostDetail().attachments,
            onDownload: (attachment) async {
              captured = attachment;
              return const PostAttachmentDownloadFeedback(message: 'Listo');
            },
          ),
        ),
      ),
    );

    expect(find.text('informe.pdf'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.save_alt_outlined));
    await tester.pumpAndSettle();
    expect(captured?.id, 7);
    expect(find.text('Listo'), findsOneWidget);
  });
}
