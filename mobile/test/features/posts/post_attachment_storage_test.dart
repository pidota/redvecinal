import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/post_attachment_storage.dart';

void main() {
  group('InMemoryPostAttachmentStorage', () {
    test('requiere activateSession antes de guardar', () async {
      final storage = InMemoryPostAttachmentStorage();
      final result = await storage.saveForSession(
        sessionEpoch: 1,
        userId: 10,
        fileName: 'a.pdf',
        bytes: [1, 2],
      );
      expect(result.sessionInvalidated, isTrue);
      expect(storage.fileCount, 0);
    });

    test('guarda con sesión activa', () async {
      final storage = InMemoryPostAttachmentStorage();
      storage.activateSession(sessionEpoch: 2, userId: 5);
      final result = await storage.saveForSession(
        sessionEpoch: 2,
        userId: 5,
        fileName: 'a.pdf',
        bytes: [1, 2],
      );
      expect(result.saved, isTrue);
      expect(storage.fileCount, 1);
    });

    test('clave opaca sin userId en ruta lógica', () async {
      final storage = InMemoryPostAttachmentStorage();
      storage.activateSession(sessionEpoch: 3, userId: 7);
      final result = await storage.saveForSession(
        sessionEpoch: 3,
        userId: 7,
        fileName: 'doc.pdf',
        bytes: [1],
      );
      expect(result.path, isNotNull);
      expect(result.path!, isNot(contains('_u_7')));
      expect(result.path!, isNot(contains('user')));
      expect(storage.read(result.path!), equals([1]));
    });

    test('invalidate bloquea escrituras posteriores', () async {
      final storage = InMemoryPostAttachmentStorage();
      storage.activateSession(sessionEpoch: 1, userId: 1);
      await storage.invalidate();
      final result = await storage.saveForSession(
        sessionEpoch: 1,
        userId: 1,
        fileName: 'x.pdf',
        bytes: [1],
      );
      expect(result.sessionInvalidated, isTrue);
    });

    test('cambio de usuario invalida guardado con epoch antiguo', () async {
      final storage = InMemoryPostAttachmentStorage();
      storage.activateSession(sessionEpoch: 1, userId: 1);
      storage.activateSession(sessionEpoch: 2, userId: 99);
      final result = await storage.saveForSession(
        sessionEpoch: 1,
        userId: 1,
        fileName: 'old.pdf',
        bytes: [9],
      );
      expect(result.sessionInvalidated, isTrue);
    });

    test('descargas concurrentes en la misma sesión', () async {
      final storage = InMemoryPostAttachmentStorage();
      storage.activateSession(sessionEpoch: 4, userId: 2);
      final results = await Future.wait([
        storage.saveForSession(
          sessionEpoch: 4,
          userId: 2,
          fileName: 'a.pdf',
          bytes: [1],
        ),
        storage.saveForSession(
          sessionEpoch: 4,
          userId: 2,
          fileName: 'b.pdf',
          bytes: [2],
        ),
      ]);
      expect(results.every((r) => r.saved), isTrue);
      expect(storage.fileCount, 2);
    });

    test('descargas concurrentes del mismo archivo', () async {
      final storage = InMemoryPostAttachmentStorage();
      storage.activateSession(sessionEpoch: 5, userId: 3);
      final results = await Future.wait([
        storage.saveForSession(
          sessionEpoch: 5,
          userId: 3,
          fileName: 'mismo.pdf',
          bytes: [9],
        ),
        storage.saveForSession(
          sessionEpoch: 5,
          userId: 3,
          fileName: 'mismo.pdf',
          bytes: [8],
        ),
      ]);
      expect(results.every((r) => r.saved), isTrue);
      expect(storage.fileCount, 1);
    });

    test('invalidate durante escritura descarta resultado', () async {
      final storage = _DelayedInMemoryStorage();
      storage.activateSession(sessionEpoch: 1, userId: 3);
      final future = storage.saveForSession(
        sessionEpoch: 1,
        userId: 3,
        fileName: 'late.pdf',
        bytes: List.filled(4, 7),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storage.invalidate();
      final result = await future;
      expect(result.sessionInvalidated, isTrue);
      expect(storage.fileCount, 0);
    });

    test('respuesta tardía no recrea archivo tras invalidate', () async {
      final storage = _DelayedInMemoryStorage();
      storage.activateSession(sessionEpoch: 8, userId: 4);
      final future = storage.saveForSession(
        sessionEpoch: 8,
        userId: 4,
        fileName: 'tardio.pdf',
        bytes: [3, 3],
      );
      await storage.invalidate();
      final result = await future;
      expect(result.sessionInvalidated, isTrue);
      expect(storage.fileCount, 0);
    });
  });

  group('IoPostAttachmentStorage', () {
    late Directory testTempParent;

    setUp(() async {
      testTempParent = await Directory.systemTemp.createTemp('rv_attach_test_');
    });

    tearDown(() async {
      if (await testTempParent.exists()) {
        await testTempParent.delete(recursive: true);
      }
    });

    IoPostAttachmentStorage buildStorage({
      ResolveTemporaryDirectory? resolver,
    }) {
      return IoPostAttachmentStorage(
        resolveTemporaryDirectory: resolver ?? () async => testTempParent,
      );
    }

    test('usa directorio temporal inyectado y carpeta opaca', () async {
      final storage = buildStorage();
      storage.activateSession(sessionEpoch: 1, userId: 42);
      final result = await storage.saveForSession(
        sessionEpoch: 1,
        userId: 42,
        fileName: 'informe.pdf',
        bytes: [4, 5, 6],
      );
      expect(result.saved, isTrue);
      final opaque = storage.opaqueSessionId;
      expect(opaque, isNotNull);
      expect(result.path!, contains(opaque!));
      expect(result.path!, isNot(contains('42')));
      expect(
        result.path!,
        startsWith(
          '${testTempParent.path}${Platform.pathSeparator}red_vecinal_posts',
        ),
      );
      final file = File(result.path!);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), [4, 5, 6]);
    });

    test('fallo al obtener directorio temporal devuelve failed', () async {
      final storage = IoPostAttachmentStorage(
        resolveTemporaryDirectory: () async {
          throw StateError('sin temp');
        },
      );
      storage.activateSession(sessionEpoch: 1, userId: 1);
      final result = await storage.saveForSession(
        sessionEpoch: 1,
        userId: 1,
        fileName: 'x.pdf',
        bytes: [1],
      );
      expect(result.failed, isTrue);
      expect(result.sessionInvalidated, isFalse);
    });

    test('invalidate elimina archivos bajo red_vecinal_posts', () async {
      final storage = buildStorage();
      storage.activateSession(sessionEpoch: 2, userId: 8);
      await storage.saveForSession(
        sessionEpoch: 2,
        userId: 8,
        fileName: 'a.bin',
        bytes: [1],
      );
      final root = storage.attachmentRoot;
      expect(root, isNotNull);
      expect(await root!.exists(), isTrue);

      await storage.invalidate();
      expect(storage.opaqueSessionId, isNull);
      if (await root.exists()) {
        var hasChildren = false;
        await for (final _ in root.list()) {
          hasChildren = true;
          break;
        }
        expect(hasChildren, isFalse);
      }
    });

    test('escritura concurrente del mismo adjunto', () async {
      final storage = buildStorage();
      storage.activateSession(sessionEpoch: 3, userId: 2);
      final results = await Future.wait([
        storage.saveForSession(
          sessionEpoch: 3,
          userId: 2,
          fileName: 'dup.pdf',
          bytes: [1],
        ),
        storage.saveForSession(
          sessionEpoch: 3,
          userId: 2,
          fileName: 'dup.pdf',
          bytes: [2],
        ),
      ]);
      expect(results.every((r) => r.saved), isTrue);
      final paths = results.map((r) => r.path).toSet();
      expect(paths.length, 1);
    });
  });
}

class _DelayedInMemoryStorage extends InMemoryPostAttachmentStorage {
  @override
  Future<PostAttachmentSaveResult> saveForSession({
    required int sessionEpoch,
    required int userId,
    required String fileName,
    required List<int> bytes,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return super.saveForSession(
      sessionEpoch: sessionEpoch,
      userId: userId,
      fileName: fileName,
      bytes: bytes,
    );
  }
}
