import 'post_detail.dart';
import 'post_moderation_review.dart';

/// Resultado local tras validar el detalle remoto para moderación.
enum PostModerationReviewOutcome {
  /// Propuesta nueva o enmienda revisable.
  ready,

  /// Ya no está pendiente de moderación (aprobada, rechazada, etc.).
  resolved,

  /// La publicación no pertenece a la junta indicada en la ruta.
  wrongNeighborhoodGroup,

  /// Solo aplica a publicaciones comunitarias (`post_kind: community`).
  notCommunityPost,

  /// El servidor no incluye `pending_content`.
  missingPendingContent,
}

class PostModerationReviewState {
  const PostModerationReviewState({
    required this.detail,
    required this.outcome,
    this.review,
    this.approveInFlight = false,
    this.approveUncertain = false,
    this.approveForbidden = false,
  });

  final PostDetail detail;
  final PostModerationReviewOutcome outcome;
  final PostModerationReview? review;
  final bool approveInFlight;
  final bool approveUncertain;
  final bool approveForbidden;

  bool get isReady => outcome == PostModerationReviewOutcome.ready;

  bool get canOfferModerationDecision =>
      isReady && !approveInFlight && !approveUncertain && !approveForbidden;

  bool get canOfferApprove => canOfferModerationDecision;

  bool get canOfferReject => canOfferModerationDecision;

  PostModerationReviewState copyWith({
    PostDetail? detail,
    PostModerationReviewOutcome? outcome,
    PostModerationReview? review,
    bool? approveInFlight,
    bool? approveUncertain,
    bool? approveForbidden,
    bool clearApproveFlags = false,
  }) {
    return PostModerationReviewState(
      detail: detail ?? this.detail,
      outcome: outcome ?? this.outcome,
      review: review ?? this.review,
      approveInFlight:
          clearApproveFlags ? false : (approveInFlight ?? this.approveInFlight),
      approveUncertain:
          clearApproveFlags
              ? false
              : (approveUncertain ?? this.approveUncertain),
      approveForbidden:
          clearApproveFlags
              ? false
              : (approveForbidden ?? this.approveForbidden),
    );
  }

  /// Determina si el detalle remoto sigue siendo moderable.
  static bool isRemoteReviewable(PostDetail detail) {
    if (detail.pendingContent == null) {
      return false;
    }
    if (detail.status == 'pending') {
      return true;
    }
    if (detail.status == 'published' && detail.hasPendingAmendment) {
      return true;
    }
    return false;
  }

  static PostModerationReviewState fromDetail({
    required PostDetail detail,
    required int expectedGroupId,
  }) {
    if (detail.postKind != 'community') {
      return PostModerationReviewState(
        detail: detail,
        outcome: PostModerationReviewOutcome.notCommunityPost,
      );
    }

    final groupId = detail.neighborhoodGroup?.id;
    if (groupId == null || groupId != expectedGroupId) {
      return PostModerationReviewState(
        detail: detail,
        outcome: PostModerationReviewOutcome.wrongNeighborhoodGroup,
      );
    }

    if (detail.pendingContent == null) {
      if (detail.status == 'pending' || detail.hasPendingAmendment) {
        return PostModerationReviewState(
          detail: detail,
          outcome: PostModerationReviewOutcome.missingPendingContent,
        );
      }
      return PostModerationReviewState(
        detail: detail,
        outcome: PostModerationReviewOutcome.resolved,
      );
    }

    if (!isRemoteReviewable(detail)) {
      return PostModerationReviewState(
        detail: detail,
        outcome: PostModerationReviewOutcome.resolved,
      );
    }

    final review = PostModerationReview.fromPostDetail(detail);
    if (review == null) {
      return PostModerationReviewState(
        detail: detail,
        outcome: PostModerationReviewOutcome.missingPendingContent,
      );
    }

    return PostModerationReviewState(
      detail: detail,
      outcome: PostModerationReviewOutcome.ready,
      review: review,
    );
  }
}
