import '../../../core/network/api_failure.dart';

/// Indica si un [ApiFailure] tras PATCH deja el resultado de aplicación desconocido.
/// No modifica la clasificación global de [mapDioError] para otros flujos.
bool isEditPostPatchOutcomeUncertain(ApiFailure failure) {
  return failure is ApiNetworkFailure ||
      failure is ApiTimeoutFailure ||
      failure is ApiServerFailure;
}

/// Payload inmutable capturado al iniciar un PATCH (antes del await).
class EditPostPatchPayload {
  const EditPostPatchPayload({
    required this.postId,
    required this.revisionId,
    required this.categoryId,
    required this.title,
    required this.body,
    required this.sessionEpoch,
    required this.saveGeneration,
  });

  final int postId;
  final int revisionId;
  final int categoryId;
  final String title;
  final String body;
  final int sessionEpoch;
  final int saveGeneration;

  bool contentMatchesRemote({
    required String remoteTitle,
    required String remoteBody,
    required int? remoteCategoryId,
  }) {
    return title == remoteTitle.trim() &&
        body == remoteBody.trim() &&
        remoteCategoryId == categoryId;
  }
}
