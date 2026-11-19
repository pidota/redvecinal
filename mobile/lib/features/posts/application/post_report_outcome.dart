import '../data/post_report_idempotency.dart';

enum PostReportOutcomeStatus {
  confirming,
  inFlight,
  confirmed,
  uncertain,
  persistBlocked,
  conflict,
}

class PostReportOutcomeRecord {
  const PostReportOutcomeRecord({
    required this.userId,
    required this.postId,
    required this.status,
    required this.generation,
    required this.recordedAtMillis,
    this.idempotencyKey,
    this.reasonCode,
    this.details,
    this.reportId,
  });

  final int userId;
  final int postId;
  final PostReportOutcomeStatus status;
  final int generation;
  final int recordedAtMillis;
  final String? idempotencyKey;
  final String? reasonCode;
  final String? details;
  final int? reportId;

  String get storageKey => '$userId:$postId';

  bool get hasRecoverableAttempt =>
      idempotencyKey != null &&
      isPostReportUuidV4(idempotencyKey!) &&
      reasonCode != null &&
      reasonCode!.isNotEmpty;

  bool get isRecoverableUncertain =>
      status == PostReportOutcomeStatus.uncertain && hasRecoverableAttempt;

  bool get isLegacyUncertain =>
      status == PostReportOutcomeStatus.uncertain && !hasRecoverableAttempt;

  PostReportOutcomeRecord copyWith({
    PostReportOutcomeStatus? status,
    int? generation,
    int? recordedAtMillis,
    String? idempotencyKey,
    String? reasonCode,
    String? details,
    int? reportId,
    bool clearPayload = false,
  }) {
    return PostReportOutcomeRecord(
      userId: userId,
      postId: postId,
      status: status ?? this.status,
      generation: generation ?? this.generation,
      recordedAtMillis: recordedAtMillis ?? this.recordedAtMillis,
      idempotencyKey:
          clearPayload ? null : idempotencyKey ?? this.idempotencyKey,
      reasonCode: clearPayload ? null : reasonCode ?? this.reasonCode,
      details: clearPayload ? null : details ?? this.details,
      reportId: reportId ?? this.reportId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'postId': postId,
      'status': status.name,
      'generation': generation,
      'recordedAt': recordedAtMillis,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      if (reasonCode != null) 'reasonCode': reasonCode,
      if (details != null) 'details': details,
      if (reportId != null) 'reportId': reportId,
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

    final rawKey = json['idempotencyKey'];
    final idempotencyKey =
        rawKey is String && rawKey.isNotEmpty ? rawKey : null;
    final rawReason = json['reasonCode'];
    final reasonCode =
        rawReason is String && rawReason.isNotEmpty ? rawReason : null;
    final rawDetails = json['details'];
    final details = rawDetails is String ? rawDetails : null;

    return PostReportOutcomeRecord(
      userId: userId,
      postId: postId,
      status: status,
      generation: generation,
      recordedAtMillis: recordedAt,
      idempotencyKey: idempotencyKey,
      reasonCode: reasonCode,
      details: details,
      reportId: _jsonInt(json['reportId']),
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

class PostReportSubmitConflict extends PostReportSubmitResult {
  const PostReportSubmitConflict();
}

class PostReportSubmitFailure extends PostReportSubmitResult {
  const PostReportSubmitFailure(this.failure);

  final Object failure;
}
