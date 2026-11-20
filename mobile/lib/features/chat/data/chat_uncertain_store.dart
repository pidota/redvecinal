import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/chat_enums.dart';

const String kChatUncertainStorageKey = 'rv_chat_uncertain_v1';
const int kChatUncertainSchemaVersion = 1;
const int kChatUncertainMaxRecords = 20;

class ChatUncertainRecord {
  const ChatUncertainRecord({
    required this.userId,
    required this.roomId,
    required this.clientMessageId,
    required this.body,
    required this.status,
    required this.updatedAt,
  });

  factory ChatUncertainRecord.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final roomId = json['room_id'];
    final clientMessageId = json['client_message_id'];
    final body = json['body'];
    final statusRaw = json['status'];
    final updatedAtRaw = json['updated_at'];
    if (userId is! int ||
        roomId is! int ||
        clientMessageId is! String ||
        body is! String ||
        statusRaw is! String ||
        updatedAtRaw is! String) {
      throw const FormatException('registro ilegible');
    }
    final status = statusRaw == 'sending'
        ? ChatOutgoingStatus.uncertain
        : ChatOutgoingStatus.values.firstWhere(
            (value) => value.name == statusRaw,
            orElse: () => ChatOutgoingStatus.uncertain,
          );
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      throw const FormatException('fecha ilegible');
    }
    return ChatUncertainRecord(
      userId: userId,
      roomId: roomId,
      clientMessageId: clientMessageId,
      body: body,
      status: status == ChatOutgoingStatus.confirmed
          ? ChatOutgoingStatus.uncertain
          : status,
      updatedAt: updatedAt,
    );
  }

  final int userId;
  final int roomId;
  final String clientMessageId;
  final String body;
  final ChatOutgoingStatus status;
  final DateTime updatedAt;

  String get storageKey => '$userId|$roomId|$clientMessageId';

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'room_id': roomId,
      'client_message_id': clientMessageId,
      'body': body,
      'status': status.name,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

abstract class ChatUncertainStore {
  Future<List<ChatUncertainRecord>> loadAll();

  Future<void> saveAll(List<ChatUncertainRecord> records);
}

final chatUncertainStoreProvider = Provider<ChatUncertainStore>((ref) {
  if (kIsWeb) {
    return InMemoryChatUncertainStore();
  }
  return FlutterSecureChatUncertainStore();
});

class InMemoryChatUncertainStore implements ChatUncertainStore {
  InMemoryChatUncertainStore({List<ChatUncertainRecord>? seed})
      : _records = List<ChatUncertainRecord>.from(seed ?? const []);

  List<ChatUncertainRecord> _records;

  List<ChatUncertainRecord> get snapshot =>
      List<ChatUncertainRecord>.from(_records);

  @override
  Future<List<ChatUncertainRecord>> loadAll() async {
    return List<ChatUncertainRecord>.from(_records);
  }

  @override
  Future<void> saveAll(List<ChatUncertainRecord> records) async {
    _records = List<ChatUncertainRecord>.from(records);
  }
}

class FlutterSecureChatUncertainStore implements ChatUncertainStore {
  FlutterSecureChatUncertainStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<List<ChatUncertainRecord>> loadAll() async {
    final raw = await _storage.read(key: kChatUncertainStorageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return parseChatUncertainPayload(raw);
  }

  @override
  Future<void> saveAll(List<ChatUncertainRecord> records) async {
    await _storage.write(
      key: kChatUncertainStorageKey,
      value: encodeChatUncertainPayload(records),
    );
  }
}

List<ChatUncertainRecord> parseChatUncertainPayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('payload inválido');
  }
  final schema = decoded['schema'];
  if (schema != null && schema != kChatUncertainSchemaVersion) {
    throw const FormatException('esquema desconocido');
  }
  final list = decoded['records'];
  if (list is! List) {
    throw const FormatException('records inválidos');
  }
  return list
      .whereType<Map>()
      .map((item) => ChatUncertainRecord.fromJson(Map<String, dynamic>.from(item)))
      .toList();
}

String encodeChatUncertainPayload(List<ChatUncertainRecord> records) {
  return jsonEncode({
    'schema': kChatUncertainSchemaVersion,
    'records': records.map((record) => record.toJson()).toList(),
  });
}

List<ChatUncertainRecord> boundChatUncertainRecords(
  List<ChatUncertainRecord> records,
) {
  if (records.length <= kChatUncertainMaxRecords) {
    return records;
  }
  final sorted = List<ChatUncertainRecord>.from(records)
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return sorted.take(kChatUncertainMaxRecords).toList();
}
