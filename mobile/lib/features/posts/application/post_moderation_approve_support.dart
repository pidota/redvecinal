import '../../../core/network/api_failure.dart';

bool isModerationApproveOutcomeUncertain(ApiFailure failure) {
  return isModerationDecisionOutcomeUncertain(failure);
}

bool isModerationDecisionOutcomeUncertain(ApiFailure failure) {
  return failure is ApiNetworkFailure ||
      failure is ApiTimeoutFailure ||
      failure is ApiServerFailure;
}

class PostModerationApprovePayload {
  const PostModerationApprovePayload({
    required this.postId,
    required this.pendingRevisionId,
    required this.sessionEpoch,
    required this.operationGeneration,
  });

  final int postId;
  final int pendingRevisionId;
  final int sessionEpoch;
  final int operationGeneration;
}

sealed class PostModerationApproveResult {
  const PostModerationApproveResult();
}

class PostModerationApproveSuccess extends PostModerationApproveResult {
  const PostModerationApproveSuccess();
}

class PostModerationApproveFailure extends PostModerationApproveResult {
  const PostModerationApproveFailure(this.failure);

  final ApiFailure failure;
}

class PostModerationApproveUncertain extends PostModerationApproveResult {
  const PostModerationApproveUncertain();
}

class PostModerationApproveDiscarded extends PostModerationApproveResult {
  const PostModerationApproveDiscarded();
}

class PostModerationApproveInFlight extends PostModerationApproveResult {
  const PostModerationApproveInFlight();
}

class PostModerationApproveBlocked extends PostModerationApproveResult {
  const PostModerationApproveBlocked(this.message);

  final String message;
}

sealed class PostModerationApproveReconcileResult {
  const PostModerationApproveReconcileResult();
}

class PostModerationApproveReconcileStillPending
    extends PostModerationApproveReconcileResult {
  const PostModerationApproveReconcileStillPending(this.message);

  final String message;
}

class PostModerationApproveReconcileResolved
    extends PostModerationApproveReconcileResult {
  const PostModerationApproveReconcileResolved(this.message);

  final String message;
}

class PostModerationApproveReconcileStillUncertain
    extends PostModerationApproveReconcileResult {
  const PostModerationApproveReconcileStillUncertain(this.message);

  final String message;
}

class PostModerationApproveReconcileDiscarded
    extends PostModerationApproveReconcileResult {
  const PostModerationApproveReconcileDiscarded();
}

class PostModerationApproveReconcileGetFailed
    extends PostModerationApproveReconcileResult {
  const PostModerationApproveReconcileGetFailed(this.failure);

  final ApiFailure failure;
}

sealed class PostModerationRejectResult {
  const PostModerationRejectResult();
}

class PostModerationRejectSuccess extends PostModerationRejectResult {
  const PostModerationRejectSuccess();
}

class PostModerationRejectFailure extends PostModerationRejectResult {
  const PostModerationRejectFailure(this.failure);

  final ApiFailure failure;
}

class PostModerationRejectUncertain extends PostModerationRejectResult {
  const PostModerationRejectUncertain();
}

class PostModerationRejectDiscarded extends PostModerationRejectResult {
  const PostModerationRejectDiscarded();
}

class PostModerationRejectInFlight extends PostModerationRejectResult {
  const PostModerationRejectInFlight();
}

class PostModerationRejectBlocked extends PostModerationRejectResult {
  const PostModerationRejectBlocked(this.message);

  final String message;
}

class PostModerationRejectValidationFailure extends PostModerationRejectResult {
  const PostModerationRejectValidationFailure(this.failure);

  final ApiValidationFailure failure;
}
