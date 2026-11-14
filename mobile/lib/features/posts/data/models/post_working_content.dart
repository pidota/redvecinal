class PostWorkingContent {
  const PostWorkingContent({
    required this.revisionId,
    required this.title,
    required this.body,
  });

  factory PostWorkingContent.fromJson(Map<String, dynamic> json) {
    return PostWorkingContent(
      revisionId: json['revision_id'] as int,
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }

  final int revisionId;
  final String title;
  final String body;
}
