import '../../../core/network/api_failure.dart';

bool isEditPostSubmitOutcomeUncertain(ApiFailure failure) {
  return failure is ApiNetworkFailure ||
      failure is ApiTimeoutFailure ||
      failure is ApiServerFailure;
}

class EditPostSubmitPayload {
  const EditPostSubmitPayload({
    required this.postId,
    required this.revisionId,
    required this.sessionEpoch,
    required this.operationGeneration,
  });

  final int postId;
  final int revisionId;
  final int sessionEpoch;
  final int operationGeneration;
}
