import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';

/// Resultado de guardar un adjunto en almacenamiento temporal privado.
class PostAttachmentSaveResult {
  const PostAttachmentSaveResult.saved(this.path)
    : sessionInvalidated = false,
      failed = false;

  const PostAttachmentSaveResult.sessionInvalidated()
    : path = null,
      failed = false,
      sessionInvalidated = true;

  const PostAttachmentSaveResult.failed()
    : path = null,
      failed = true,
      sessionInvalidated = false;

  final String? path;
  final bool sessionInvalidated;
  final bool failed;

  bool get saved => path != null && !failed && !sessionInvalidated;
}

/// Resuelve el directorio temporal del SO (inyectable en pruebas).
typedef ResolveTemporaryDirectory = Future<Directory> Function();

/// Almacén temporal de adjuntos (caché privada de la app; sin almacenamiento público).
abstract class PostAttachmentStorage {
  void activateSession({required int sessionEpoch, required int userId});

  Future<void> invalidate();

  Future<PostAttachmentSaveResult> saveForSession({
    required int sessionEpoch,
    required int userId,
    required String fileName,
    required List<int> bytes,
  });

  int? get activeSessionEpoch;
  int? get activeUserId;
}

final postAttachmentStorageProvider = Provider<PostAttachmentStorage>((ref) {
  final storage =
      kIsWeb ? InMemoryPostAttachmentStorage() : IoPostAttachmentStorage();

  Future<void> syncSession(AuthState? previous, AuthState next) async {
    if (next is AuthAuthenticated) {
      final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
      final userChanged =
          previous is AuthAuthenticated && previous.user.id != next.user.id;
      final becameAuthenticated = previous is! AuthAuthenticated;
      if (userChanged || becameAuthenticated) {
        await storage.invalidate();
      }
      storage.activateSession(sessionEpoch: epoch, userId: next.user.id);
      return;
    }
    await storage.invalidate();
  }

  Future.microtask(() => syncSession(null, ref.read(authControllerProvider)));

  ref.onDispose(() {
    storage.invalidate();
  });

  ref.listen<AuthState>(authControllerProvider, (previous, next) {
    Future.microtask(() => syncSession(previous, next));
  });

  return storage;
});

String generateOpaqueSessionDirectoryId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

class InMemoryPostAttachmentStorage implements PostAttachmentStorage {
  final Map<String, List<int>> _files = {};
  int? _activeSessionEpoch;
  int? _activeUserId;
  String? _opaqueSessionId;
  int _operationGeneration = 0;
  bool _invalidated = true;
  final Map<String, Future<void>> _fileWriteTail = {};

  @override
  int? get activeSessionEpoch => _activeSessionEpoch;

  @override
  int? get activeUserId => _activeUserId;

  @visibleForTesting
  String? get opaqueSessionId => _opaqueSessionId;

  @override
  void activateSession({required int sessionEpoch, required int userId}) {
    final sessionChanged =
        _activeSessionEpoch != sessionEpoch || _activeUserId != userId;
    if (sessionChanged || _opaqueSessionId == null) {
      _files.clear();
      _opaqueSessionId = generateOpaqueSessionDirectoryId();
    }
    _activeSessionEpoch = sessionEpoch;
    _activeUserId = userId;
    _invalidated = false;
  }

  @override
  Future<void> invalidate() async {
    _invalidated = true;
    _operationGeneration++;
    _files.clear();
    _activeSessionEpoch = null;
    _activeUserId = null;
    _opaqueSessionId = null;
    _fileWriteTail.clear();
  }

  @override
  Future<PostAttachmentSaveResult> saveForSession({
    required int sessionEpoch,
    required int userId,
    required String fileName,
    required List<int> bytes,
  }) {
    return _withFileWriteLock(fileName, () async {
      return _saveForSessionUnlocked(
        sessionEpoch: sessionEpoch,
        userId: userId,
        fileName: fileName,
        bytes: bytes,
      );
    });
  }

  Future<PostAttachmentSaveResult> _saveForSessionUnlocked({
    required int sessionEpoch,
    required int userId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final op = _operationGeneration;
    if (_invalidated ||
        sessionEpoch != _activeSessionEpoch ||
        userId != _activeUserId ||
        _opaqueSessionId == null) {
      return const PostAttachmentSaveResult.sessionInvalidated();
    }

    if (op != _operationGeneration) {
      return const PostAttachmentSaveResult.sessionInvalidated();
    }

    final key = '$_opaqueSessionId::$fileName';
    _files[key] = List<int>.from(bytes);

    if (_invalidated ||
        op != _operationGeneration ||
        sessionEpoch != _activeSessionEpoch ||
        userId != _activeUserId) {
      _files.remove(key);
      return const PostAttachmentSaveResult.sessionInvalidated();
    }

    return PostAttachmentSaveResult.saved(key);
  }

  List<int>? read(String key) => _files[key];

  int get fileCount => _files.length;

  Future<T> _withFileWriteLock<T>(
    String fileName,
    Future<T> Function() action,
  ) async {
    final prior = _fileWriteTail[fileName] ?? Future<void>.value();
    final gate = Completer<void>();
    _fileWriteTail[fileName] = gate.future;
    await prior;
    try {
      return await action();
    } finally {
      gate.complete();
      if (_fileWriteTail[fileName] == gate.future) {
        _fileWriteTail.remove(fileName);
      }
    }
  }
}

/// Almacenamiento en disco bajo [getTemporaryDirectory] (nunca [Directory.systemTemp] en producción).
class IoPostAttachmentStorage implements PostAttachmentStorage {
  IoPostAttachmentStorage({
    ResolveTemporaryDirectory? resolveTemporaryDirectory,
  }) : _resolveTemporaryDirectory =
           resolveTemporaryDirectory ?? getTemporaryDirectory;

  final ResolveTemporaryDirectory _resolveTemporaryDirectory;

  Directory? _root;
  int? _activeSessionEpoch;
  int? _activeUserId;
  String? _opaqueSessionId;
  int _operationGeneration = 0;
  bool _invalidated = true;
  final Map<String, Future<void>> _fileWriteTail = {};

  @override
  int? get activeSessionEpoch => _activeSessionEpoch;

  @override
  int? get activeUserId => _activeUserId;

  @visibleForTesting
  String? get opaqueSessionId => _opaqueSessionId;

  @visibleForTesting
  Directory? get attachmentRoot => _root;

  @override
  void activateSession({required int sessionEpoch, required int userId}) {
    final sessionChanged =
        _activeSessionEpoch != sessionEpoch || _activeUserId != userId;
    if (sessionChanged || _opaqueSessionId == null) {
      _opaqueSessionId = generateOpaqueSessionDirectoryId();
    }
    _activeSessionEpoch = sessionEpoch;
    _activeUserId = userId;
    _invalidated = false;
  }

  @override
  Future<void> invalidate() async {
    _invalidated = true;
    _operationGeneration++;
    _activeSessionEpoch = null;
    _activeUserId = null;
    _opaqueSessionId = null;
    _fileWriteTail.clear();
    await _purgeSessionTree();
  }

  @override
  Future<PostAttachmentSaveResult> saveForSession({
    required int sessionEpoch,
    required int userId,
    required String fileName,
    required List<int> bytes,
  }) {
    return _withFileWriteLock(fileName, () async {
      return _saveForSessionUnlocked(
        sessionEpoch: sessionEpoch,
        userId: userId,
        fileName: fileName,
        bytes: bytes,
      );
    });
  }

  Future<PostAttachmentSaveResult> _saveForSessionUnlocked({
    required int sessionEpoch,
    required int userId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final op = _operationGeneration;
    if (_invalidated ||
        sessionEpoch != _activeSessionEpoch ||
        userId != _activeUserId ||
        _opaqueSessionId == null) {
      return const PostAttachmentSaveResult.sessionInvalidated();
    }

    final root = await _ensureRoot();
    if (root == null) {
      return const PostAttachmentSaveResult.failed();
    }

    final sessionDir = await _sessionDirectory(root);
    final target = File('${sessionDir.path}${Platform.pathSeparator}$fileName');
    final partial = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
    );

    try {
      await partial.writeAsBytes(bytes, flush: true);

      if (_invalidated ||
          op != _operationGeneration ||
          sessionEpoch != _activeSessionEpoch ||
          userId != _activeUserId) {
        await _deleteIfExists(partial);
        return const PostAttachmentSaveResult.sessionInvalidated();
      }

      if (await target.exists()) {
        await target.delete();
      }
      await partial.rename(target.path);

      if (_invalidated ||
          op != _operationGeneration ||
          sessionEpoch != _activeSessionEpoch ||
          userId != _activeUserId) {
        await _deleteIfExists(target);
        return const PostAttachmentSaveResult.sessionInvalidated();
      }

      return PostAttachmentSaveResult.saved(target.path);
    } on Object {
      await _deleteIfExists(partial);
      if (await target.exists()) {
        try {
          await target.delete();
        } on Object {
          // limpieza best-effort
        }
      }
      return const PostAttachmentSaveResult.failed();
    }
  }

  Future<Directory> _sessionDirectory(Directory root) async {
    final id = _opaqueSessionId;
    if (id == null) {
      throw StateError('Sin directorio de sesión opaco');
    }
    final sessionDir = Directory('${root.path}${Platform.pathSeparator}$id');
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    return sessionDir;
  }

  Future<Directory?> _ensureRoot() async {
    if (_root != null) {
      return _root;
    }
    try {
      final tempDir = await _resolveTemporaryDirectory();
      final root = Directory(
        '${tempDir.path}${Platform.pathSeparator}red_vecinal_posts',
      );
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      _root = root;
      return root;
    } on Object {
      return null;
    }
  }

  Future<void> _purgeSessionTree() async {
    final root = _root;
    if (root == null || !await root.exists()) {
      return;
    }
    await for (final entity in root.list()) {
      if (entity is Directory) {
        await _deleteDirectory(entity);
      } else if (entity is File) {
        await entity.delete();
      }
    }
  }

  Future<void> _deleteDirectory(Directory dir) async {
    if (!await dir.exists()) {
      return;
    }
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        await _deleteDirectory(entity);
      } else if (entity is File) {
        await entity.delete();
      }
    }
    await dir.delete();
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<T> _withFileWriteLock<T>(
    String fileName,
    Future<T> Function() action,
  ) async {
    final prior = _fileWriteTail[fileName] ?? Future<void>.value();
    final gate = Completer<void>();
    _fileWriteTail[fileName] = gate.future;
    await prior;
    try {
      return await action();
    } finally {
      gate.complete();
      if (_fileWriteTail[fileName] == gate.future) {
        _fileWriteTail.remove(fileName);
      }
    }
  }
}
