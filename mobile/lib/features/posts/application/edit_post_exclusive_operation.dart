/// Operación exclusiva en edición (PATCH vs upload); no confundir con incertidumbre.
enum EditPostExclusiveOperationKind { patch, upload, submit }

/// Posesión atómica por post/sesión; liberar solo con el mismo [token].
class EditPostOperationLease {
  const EditPostOperationLease({
    required this.token,
    required this.postId,
    required this.userId,
    required this.sessionEpoch,
    required this.kind,
  });

  final int token;
  final int postId;
  final int userId;
  final int sessionEpoch;
  final EditPostExclusiveOperationKind kind;
}
