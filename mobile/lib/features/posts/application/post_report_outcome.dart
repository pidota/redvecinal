enum PostReportOutcomeStatus {
  confirming,
  inFlight,
  confirmed,
  uncertain,
  persistBlocked,
}

class PostReportOutcomeRecord {
  const PostReportOutcomeRecord({
    required this.userId,
    required this.postId,
    required this.status,
    required this.generation,
    required this.recordedAtMillis,
  });

  final int userId;
  final int postId;
  final PostReportOutcomeStatus status;
  final int generation;
  final int recordedAtMillis;

  String get storageKey => '$userId:$postId';

  PostReportOutcomeRecord copyWith({
    PostReportOutcomeStatus? status,
    int? generation,
    int? recordedAtMillis,
  }) {
    return PostReportOutcomeRecord(
      userId: userId,
      postId: postId,
      status: status ?? this.status,
      generation: generation ?? this.generation,
      recordedAtMillis: recordedAtMillis ?? this.recordedAtMillis,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'postId': postId,
      'status': status.name,
      'generation': generation,
      'recordedAt': recordedAtMillis,
    };
  }

  static PostReportOutcomeRecord? fromJson(Map<String, dynamic> json) {
    final userId = _jsonInt(json['userId']);
    final postId = _jsonInt(json['postId']);
    final statusName = json['status'];
    final generation = _jsonInt(json['generation']);
    final recordedAt = _jsonInt(json['recordedAt']);
    if (userId == null ||
        postId == null ||
        statusName is! String ||
        generation == null ||
        recordedAt == null) {
      return null;
    }
    final status =
        PostReportOutcomeStatus.values
            .where((value) => value.name == statusName)
            .firstOrNull;
    if (status == null ||
        status == PostReportOutcomeStatus.confirming ||
        status == PostReportOutcomeStatus.persistBlocked) {
      return null;
    }
    return PostReportOutcomeRecord(
      userId: userId,
      postId: postId,
      status: status,
      generation: generation,
      recordedAtMillis: recordedAt,
    );
  }

  static int? _jsonInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}

sealed class PostReportSubmitResult {
  const PostReportSubmitResult();
}

class PostReportSubmitValidationFailed extends PostReportSubmitResult {
  const PostReportSubmitValidationFailed();
}

class PostReportSubmitBlocked extends PostReportSubmitResult {
  const PostReportSubmitBlocked(this.message);

  final String message;
}

class PostReportSubmitDiscarded extends PostReportSubmitResult {
  const PostReportSubmitDiscarded();
}

class PostReportSubmitSuccess extends PostReportSubmitResult {
  const PostReportSubmitSuccess();
}

class PostReportSubmitUncertain extends PostReportSubmitResult {
  const PostReportSubmitUncertain();
}

class PostReportSubmitFailure extends PostReportSubmitResult {
  const PostReportSubmitFailure(this.failure);

  final Object failure;
}
