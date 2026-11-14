class PostAttachmentUploadResult {
  const PostAttachmentUploadResult({
    required this.id,
    required this.revisionId,
    required this.originalDisplayName,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory PostAttachmentUploadResult.fromJson(Map<String, dynamic> json) {
    return PostAttachmentUploadResult(
      id: json['id'] as int,
      revisionId: json['revision_id'] as int,
      originalDisplayName: json['original_display_name'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: json['size_bytes'] as int? ?? 0,
    );
  }

  final int id;
  final int revisionId;
  final String originalDisplayName;
  final String mimeType;
  final int sizeBytes;
}
