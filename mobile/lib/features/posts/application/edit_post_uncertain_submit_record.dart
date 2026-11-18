import 'edit_post_submit_support.dart';

enum EditPostUncertainSubmitPhase { inFlight, outcomeUncertain }

class EditPostUncertainSubmitRecord {
  const EditPostUncertainSubmitRecord({
    required this.userId,
    required this.sessionEpoch,
    required this.postId,
    required this.revisionId,
    required this.operationGeneration,
    required this.phase,
  });

  final int userId;
  final int sessionEpoch;
  final int postId;
  final int revisionId;
  final int operationGeneration;
  final EditPostUncertainSubmitPhase phase;

  EditPostSubmitPayload toPayload() {
    return EditPostSubmitPayload(
      postId: postId,
      revisionId: revisionId,
      sessionEpoch: sessionEpoch,
      operationGeneration: operationGeneration,
    );
  }

  EditPostUncertainSubmitRecord copyWith({
    EditPostUncertainSubmitPhase? phase,
  }) {
    return EditPostUncertainSubmitRecord(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      revisionId: revisionId,
      operationGeneration: operationGeneration,
      phase: phase ?? this.phase,
    );
  }
}
