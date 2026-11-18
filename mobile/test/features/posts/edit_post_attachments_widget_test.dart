import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/create_post_local_attachment.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachment_upload_support.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/data/models/post_category.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/edit_post_screen.dart';
import 'package:red_vecinal/features/posts/presentation/widgets/edit_post_attachment_section.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('28 widget: sección de adjuntos en edición', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        901: draftPostDetail(
          id: 901,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(editPostAttachmentsPersistenceProvider);
    await container.read(editPostControllerProvider(901).future);
    final snap = EditPostSnapshot.fromDetail(gateway.detailById![901]!);
    container
        .read(editPostAttachmentsControllerProvider(901).notifier)
        .hydrateFromEditableRevision(
          revisionId: snap.editableRevisionId!,
          serverAttachments: snap.readOnlyAttachments,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: EditPostAttachmentSection(postId: 901, busy: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archivos adjuntos'), findsOneWidget);
    expect(find.text('Imagen'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('29 widget: mensaje de error de validación', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        902: draftPostDetail(
          id: 902,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(editPostControllerProvider(902).future);
    container
        .read(editPostAttachmentsControllerProvider(902).notifier)
        .hydrateFromEditableRevision(
          revisionId: 9020,
          serverAttachments: const [],
        );
    container
        .read(editPostAttachmentsControllerProvider(902).notifier)
        .setLocalItemsForTests(const []);

    container.invalidate(editPostAttachmentsControllerProvider(902));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final n = ref.read(
                  editPostAttachmentsControllerProvider(902).notifier,
                );
                return Column(
                  children: [
                    const EditPostAttachmentSection(postId: 902, busy: false),
                    TextButton(
                      onPressed: () {
                        n.hydrateFromEditableRevision(
                          revisionId: 9020,
                          serverAttachments: const [],
                        );
                        ref
                            .read(
                              editPostAttachmentsControllerProvider(
                                902,
                              ).notifier,
                            )
                            .pickAndAddPdf();
                      },
                      child: const Text('Simular pick'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archivos adjuntos'), findsOneWidget);
  });

  testWidgets('30 widget: incertidumbre visible en sección', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        904: draftPostDetail(
          id: 904,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(editPostAttachmentsPersistenceProvider);
    await container.read(editPostControllerProvider(904).future);
    final attach = container.read(
      editPostAttachmentsControllerProvider(904).notifier,
    );
    attach.setLocalItemsForTests([
      CreatePostLocalAttachment(
        clientId: 'u1',
        path: 'x',
        displayName: 'f.pdf',
        sizeBytes: 10,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.uncertain,
        userMessage: editPostUncertainUploadBlockedMessage,
      ),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: EditPostAttachmentSection(postId: 904, busy: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No pudimos confirmar'), findsWidgets);
  });

  testWidgets('31 EditPostScreen 320px sin overflow en adjuntos', (
    tester,
  ) async {
    const categories = [
      PostCategory(
        id: 2,
        slug: 'aviso-comunitario',
        name: 'Aviso comunitario',
        defaultAudience: 'group',
        sortOrder: 1,
        isSystem: true,
      ),
    ];
    final gateway = FakePostGateway(
      detailById: {
        905: draftPostDetail(
          id: 905,
          groupId: 2,
          categoryId: 2,
          title: 'Título largo de prueba',
          body: 'Cuerpo',
        ),
      },
      postCategories: categories,
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(editPostAttachmentsPersistenceProvider);
    await container.read(editPostControllerProvider(905).future);

    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditPostScreen(postId: 905)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Archivos adjuntos'), findsOneWidget);
    expect(find.text('Imagen'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.byType(OverflowBar), findsNothing);
  });
}
