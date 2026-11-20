/// JSON de chat ilegible. Los códigos HTTP siguen siendo `ApiFailure`.
class ChatApiException implements Exception {
  const ChatApiException([this.message = 'La respuesta del chat no es válida.']);

  final String message;

  @override
  String toString() => 'ChatApiException: $message';
}

/// La petición se canceló antes de completar; no confirma ni descarta el envío.
class ChatRequestCancelled implements Exception {
  const ChatRequestCancelled();
}
