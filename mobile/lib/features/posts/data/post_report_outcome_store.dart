import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/post_report_outcome.dart';

class PostReportOutcomeStoreException implements Exception {
  const PostReportOutcomeStoreException([this.message]);

  final String? message;
}

const String kPostReportOutcomesV1Key = 'rv_post_report_outcomes_v1';

const String kPostReportOutcomesV2Key = 'rv_post_report_outcomes_v2';

const int kPostReportOutcomesSchemaVersion = 2;

/// Interpreta el JSON persistido (v1 o v2). Cualquier registro ilegible invalida el lote.
List<PostReportOutcomeRecord> parsePostReportOutcomePayload(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const PostReportOutcomeStoreException('payload inválido');
    }
    final schema = decoded['schema'];
    if (schema != null && schema != 1 && schema != 2) {
      throw const PostReportOutcomeStoreException('esquema desconocido');
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

String encodePostReportOutcomePayload(List<PostReportOutcomeRecord> records) {
  return jsonEncode({
    'schema': kPostReportOutcomesSchemaVersion,
    'records': records.map((record) => record.toJson()).toList(),
  });
}

/// Persistencia de resultados de reporte.
///
/// v2 guarda clave y payload mientras el intento no está confirmado.
/// Un `confirmed` puede retenerlos si falló la limpieza; la hidratación lo reintenta.
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
  Duration readDelay = Duration.zero;
  int saveCount = 0;
  int loadCount = 0;
  List<PostReportOutcomeRecord> lastSaved = const [];

  List<PostReportOutcomeRecord> get snapshot =>
      List<PostReportOutcomeRecord>.from(_records);

  @override
  Future<List<PostReportOutcomeRecord>> loadAll() async {
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    loadCount++;
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

  final FlutterSecureStorage _storage;

  bool loadedLegacyV1 = false;

  @override
  Future<List<PostReportOutcomeRecord>> loadAll() async {
    loadedLegacyV1 = false;
    final v2 = await _storage.read(key: kPostReportOutcomesV2Key);
    if (v2 != null && v2.isNotEmpty) {
      return _parseOrThrow(v2);
    }
    final v1 = await _storage.read(key: kPostReportOutcomesV1Key);
    if (v1 == null || v1.isEmpty) {
      return const [];
    }
    loadedLegacyV1 = true;
    return _parseOrThrow(v1);
  }

  @override
  Future<void> saveAll(List<PostReportOutcomeRecord> records) async {
    await _storage.write(
      key: kPostReportOutcomesV2Key,
      value: encodePostReportOutcomePayload(records),
    );
  }

  List<PostReportOutcomeRecord> _parseOrThrow(String raw) {
    try {
      return parsePostReportOutcomePayload(raw);
    } on PostReportOutcomeStoreException {
      rethrow;
    } on Object {
      throw const PostReportOutcomeStoreException('almacenamiento corrupto');
    }
  }
}
