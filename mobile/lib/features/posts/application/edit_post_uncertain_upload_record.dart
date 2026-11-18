/// Subida sin HTTP 201 confirmado; aislada por post/revisión/sesión de edición.
class EditPostUncertainUploadRecord {
  const EditPostUncertainUploadRecord({
    required this.userId,
    required this.sessionEpoch,
    required this.postId,
    required this.revisionId,
    required this.clientId,
    required this.displayName,
    required this.sizeBytes,
    required this.mimeType,
    this.localPath,
  });

  final int userId;
  final int sessionEpoch;
  final int postId;
  final int revisionId;
  final String clientId;
  final String displayName;
  final int sizeBytes;
  final String mimeType;
  final String? localPath;
}
