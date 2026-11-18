import '../data/models/post_detail.dart';

/// GET de reconciliación válido para una adopción explícita posterior.
class EditPostReconcileObservation {
  const EditPostReconcileObservation({
    required this.remote,
    required this.operationGeneration,
    required this.reconcileGeneration,
    required this.contentMatchesPending,
  });

  final PostDetail remote;
  final int operationGeneration;
  final int reconcileGeneration;
  final bool contentMatchesPending;
}
