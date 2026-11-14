/// Subida sin respuesta HTTP 201 confirmada; persiste entre remounts por sessionEpoch.
class CreatePostUncertainUploadRecord {
  const CreatePostUncertainUploadRecord({
    required this.clientId,
    required this.displayName,
    required this.sizeBytes,
    required this.mimeType,
    this.localPath,
  });

  final String clientId;
  final String displayName;
  final int sizeBytes;
  final String mimeType;
  final String? localPath;

  CreatePostUncertainUploadRecord copyWith({String? localPath}) {
    return CreatePostUncertainUploadRecord(
      clientId: clientId,
      displayName: displayName,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      localPath: localPath ?? this.localPath,
    );
  }
}
