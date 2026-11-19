import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/post_report_outcome.dart';

class PostReportOutcomeStoreException implements Exception {
  const PostReportOutcomeStoreException([this.message]);

  final String? message;
}

/// Interpreta el JSON persistido. Cualquier registro ilegible invalida el lote.
List<PostReportOutcomeRecord> parsePostReportOutcomePayload(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const PostReportOutcomeStoreException('payload inválido');
    }
    final list = decoded['records'];
    if (list is! List) {
      throw const PostReportOutcomeStoreException('records inválidos');
    }
    final parsed = <PostReportOutcomeRecord>[];
    for (final item in list) {
      if (item is! Map) {
        throw const PostReportOutcomeStoreException('registro ilegible');
      }
      final record = PostReportOutcomeRecord.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (record == null) {
        throw const PostReportOutcomeStoreException('registro ilegible');
      }
      parsed.add(record);
    }
    return parsed;
  } on PostReportOutcomeStoreException {
    rethrow;
  } on Object {
    throw const PostReportOutcomeStoreException('almacenamiento corrupto');
  }
}

/// Persistencia mínima de resultados de reporte (sin motivo ni detalles).
///
/// Borrar datos de la app o cambiar de dispositivo elimina esta protección local.
abstract class PostReportOutcomeStore {
  Future<List<PostReportOutcomeRecord>> loadAll();

  Future<void> saveAll(List<PostReportOutcomeRecord> records);
}

final postReportOutcomeStoreProvider = Provider<PostReportOutcomeStore>((ref) {
  if (kIsWeb) {
    return InMemoryPostReportOutcomeStore();
  }
  return FlutterSecurePostReportOutcomeStore();
});

class InMemoryPostReportOutcomeStore implements PostReportOutcomeStore {
  InMemoryPostReportOutcomeStore({List<PostReportOutcomeRecord>? seed})
    : _records = List<PostReportOutcomeRecord>.from(seed ?? const []);

  List<PostReportOutcomeRecord> _records;
  bool failWrites = false;
  bool failReads = false;
  int? failOnSaveNumber;
  Duration writeDelay = Duration.zero;
  int saveCount = 0;
  List<PostReportOutcomeRecord> lastSaved = const [];

  List<PostReportOutcomeRecord> get snapshot =>
      List<PostReportOutcomeRecord>.from(_records);

  @override
  Future<List<PostReportOutcomeRecord>> loadAll() async {
    if (failReads) {
      throw const PostReportOutcomeStoreException('read failed');
    }
    return List<PostReportOutcomeRecord>.from(_records);
  }

  @override
  Future<void> saveAll(List<PostReportOutcomeRecord> records) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    saveCount++;
    if (failWrites || failOnSaveNumber == saveCount) {
      throw const PostReportOutcomeStoreException('write failed');
    }
    lastSaved = List<PostReportOutcomeRecord>.from(records);
    _records = List<PostReportOutcomeRecord>.from(records);
  }
}

class FlutterSecurePostReportOutcomeStore implements PostReportOutcomeStore {
  FlutterSecurePostReportOutcomeStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _key = 'rv_post_report_outcomes_v1';

  final FlutterSecureStorage _storage;

  @override
  Future<List<PostReportOutcomeRecord>> loadAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      return parsePostReportOutcomePayload(raw);
    } on PostReportOutcomeStoreException {
      rethrow;
    } on Object {
      throw const PostReportOutcomeStoreException('almacenamiento corrupto');
    }
  }

  @override
  Future<void> saveAll(List<PostReportOutcomeRecord> records) async {
    final payload = jsonEncode({
      'records': records.map((record) => record.toJson()).toList(),
    });
    await _storage.write(key: _key, value: payload);
  }
}
