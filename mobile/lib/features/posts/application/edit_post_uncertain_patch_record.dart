import 'edit_post_patch_support.dart';

/// Fase del intento persistido (distingue envío en curso vs resultado incierto).
enum EditPostUncertainPatchPhase {
  /// Registrado antes del await PATCH; bloquea un segundo envío.
  inFlight,

  /// Respuesta HTTP no confirmada (red, timeout, 5xx u otro).
  outcomeUncertain,
}

/// Intento de PATCH enlazado a usuario, epoch y postId (memoria de app; ver persistence).
class EditPostUncertainPatchRecord {
  const EditPostUncertainPatchRecord({
    required this.userId,
    required this.sessionEpoch,
    required this.postId,
    required this.revisionId,
    required this.categoryId,
    required this.title,
    required this.body,
    required this.operationGeneration,
    required this.phase,
  });

  final int userId;
  final int sessionEpoch;
  final int postId;
  final int revisionId;
  final int categoryId;
  final String title;
  final String body;
  final int operationGeneration;
  final EditPostUncertainPatchPhase phase;

  bool get blocksNewPatch => true;

  EditPostPatchPayload toPayload() {
    return EditPostPatchPayload(
      postId: postId,
      revisionId: revisionId,
      categoryId: categoryId,
      title: title,
      body: body,
      sessionEpoch: sessionEpoch,
      saveGeneration: operationGeneration,
    );
  }

  EditPostUncertainPatchRecord copyWith({EditPostUncertainPatchPhase? phase}) {
    return EditPostUncertainPatchRecord(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      revisionId: revisionId,
      categoryId: categoryId,
      title: title,
      body: body,
      operationGeneration: operationGeneration,
      phase: phase ?? this.phase,
    );
  }
}
