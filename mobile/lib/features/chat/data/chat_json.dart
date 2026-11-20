import 'chat_api_exception.dart';

int parseRequiredInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw const ChatApiException();
}

int? parseOptionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  return parseRequiredInt(value);
}

String parseRequiredString(Object? value) {
  if (value is String) {
    return value;
  }
  throw const ChatApiException();
}

String? parseOptionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw const ChatApiException();
}

DateTime? parseOptionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw const ChatApiException();
}

Map<String, dynamic> unwrapResourceData(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (payload.containsKey('id')) {
    return payload;
  }
  throw const ChatApiException();
}

List<Map<String, dynamic>> unwrapResourceList(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data == null) {
    return const [];
  }
  if (data is! List) {
    throw const ChatApiException();
  }
  return data.whereType<Map<String, dynamic>>().toList();
}
