import '../../../../core/network/api_failure.dart';

/// Resultado mínimo de `POST /posts/{id}/reports` (201).
class PostReportResult {
  const PostReportResult({required this.id, required this.status});

  factory PostReportResult.fromJson(Map<String, dynamic> json) {
    final id = _parseInt(json['id']);
    final status = json['status'];
    if (id == null || status is! String || status.trim().isEmpty) {
      throw const ApiUnexpectedFailure();
    }
    return PostReportResult(id: id, status: status);
  }

  final int id;
  final String status;

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
