import 'dart:math';

enum CreatePostAttachmentState {
  selected,
  uploading,
  uploaded,
  failed,
  uncertain,
}

class CreatePostLocalAttachment {
  CreatePostLocalAttachment({
    required this.clientId,
    required this.path,
    required this.displayName,
    required this.sizeBytes,
    required this.mimeType,
    this.state = CreatePostAttachmentState.selected,
    this.serverAttachmentId,
    this.userMessage,
    this.uploadProgress,
  });

  final String clientId;
  final String path;
  final String displayName;
  final int sizeBytes;
  final String mimeType;
  CreatePostAttachmentState state;
  int? serverAttachmentId;
  String? userMessage;
  double? uploadProgress;

  bool get isOnServer =>
      state == CreatePostAttachmentState.uploaded && serverAttachmentId != null;

  bool get blocksSubmit =>
      state == CreatePostAttachmentState.uncertain ||
      state == CreatePostAttachmentState.uploading;

  bool get canRetry =>
      state == CreatePostAttachmentState.failed ||
      state == CreatePostAttachmentState.selected;

  bool get canRemoveLocally =>
      state == CreatePostAttachmentState.selected ||
      state == CreatePostAttachmentState.failed;

  CreatePostLocalAttachment copyWith({
    CreatePostAttachmentState? state,
    int? serverAttachmentId,
    String? userMessage,
    double? uploadProgress,
    bool clearUserMessage = false,
    bool clearProgress = false,
  }) {
    return CreatePostLocalAttachment(
      clientId: clientId,
      path: path,
      displayName: displayName,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      state: state ?? this.state,
      serverAttachmentId: serverAttachmentId ?? this.serverAttachmentId,
      userMessage: clearUserMessage ? null : (userMessage ?? this.userMessage),
      uploadProgress:
          clearProgress ? null : (uploadProgress ?? this.uploadProgress),
    );
  }

  static String newClientId() {
    final random = Random();
    return 'att-${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }
}
