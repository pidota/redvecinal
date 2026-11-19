import 'post_moderation_approve_support.dart';

enum PostModerationDecisionKind { approve, reject }

enum PostModerationUncertainApprovePhase { inFlight, outcomeUncertain }

class PostModerationUncertainApproveRecord {
  const PostModerationUncertainApproveRecord({
    required this.userId,
    required this.sessionEpoch,
    required this.postId,
    required this.pendingRevisionId,
    required this.operationGeneration,
    required this.phase,
    required this.decisionKind,
  });

  final int userId;
  final int sessionEpoch;
  final int postId;
  final int pendingRevisionId;
  final int operationGeneration;
  final PostModerationUncertainApprovePhase phase;
  final PostModerationDecisionKind decisionKind;

  PostModerationApprovePayload toPayload() {
    return PostModerationApprovePayload(
      postId: postId,
      pendingRevisionId: pendingRevisionId,
      sessionEpoch: sessionEpoch,
      operationGeneration: operationGeneration,
    );
  }

  PostModerationUncertainApproveRecord copyWith({
    PostModerationUncertainApprovePhase? phase,
    PostModerationDecisionKind? decisionKind,
  }) {
    return PostModerationUncertainApproveRecord(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      pendingRevisionId: pendingRevisionId,
      operationGeneration: operationGeneration,
      phase: phase ?? this.phase,
      decisionKind: decisionKind ?? this.decisionKind,
    );
  }
}
