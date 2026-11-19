import '../../../core/network/api_failure.dart';
import 'post_report_idempotency.dart';

/// Alineado con validación Laravel en `PostReportController`.
const int postReportReasonCodeMaxLength = 60;

const int postReportDetailsMaxLength = 2000;

/// `reason_code` es texto libre (máx. 60). En el repo aparecen ejemplos como
/// `spam` e `inappropriate`; no hay enum backend.
///
/// Validación local:
/// - [reasonCode] no puede quedar vacío tras quitar espacios al inicio/final.
/// - La longitud máxima de 60 se aplica al valor enviado tal cual (sin recortar).
/// - [details] es opcional; si se envía, máx. 2000 caracteres sin truncar.
ApiValidationFailure? validatePostReportInput({
  required String reasonCode,
  String? details,
}) {
  if (reasonCode.trim().isEmpty) {
    return const ApiValidationFailure({
      'reason_code': ['El motivo del reporte es obligatorio.'],
    }, 'El motivo del reporte es obligatorio.');
  }
  if (reasonCode.length > postReportReasonCodeMaxLength) {
    return const ApiValidationFailure({
      'reason_code': [
        'El motivo no puede superar $postReportReasonCodeMaxLength caracteres.',
      ],
    }, 'El motivo del reporte es demasiado largo.');
  }
  if (details != null && details.length > postReportDetailsMaxLength) {
    return const ApiValidationFailure({
      'details': [
        'Los detalles no pueden superar $postReportDetailsMaxLength caracteres.',
      ],
    }, 'Los detalles del reporte son demasiado largos.');
  }
  return null;
}

/// Tras despachar el POST, timeout, red, 5xx, 429 o 201 malformado no demuestran
/// que el servidor haya rechazado la creación. No reintentar automáticamente.
bool isPostReportOutcomeUncertain(ApiFailure failure) {
  return failure is ApiNetworkFailure ||
      failure is ApiTimeoutFailure ||
      failure is ApiServerFailure ||
      failure is ApiUnexpectedFailure ||
      failure is ApiRateLimitedFailure;
}

const Set<String> kPostReportTrustedValidationFields = {
  'reason_code',
  'details',
  kPostReportIdempotencyHeader,
};

/// Rechazo **antes** de crear el reporte, con evidencia estructural — no solo el código HTTP.
///
/// Laravel 422 de cuerpo trae `errors.reason_code` / `errors.details`.
/// Clave inválida: campo `Idempotency-Key` o el mensaje fijo del backend.
/// 401/403/404 ocurren antes del INSERT. Cualquier otra forma (422 genérico, 429, proxy) es incierta.
bool isPostReportPreCreateRejection(ApiFailure failure) {
  if (failure is ApiSessionExpiredFailure ||
      failure is ApiForbiddenFailure ||
      failure is ApiNotFoundFailure) {
    return true;
  }
  if (failure is! ApiValidationFailure) {
    return false;
  }
  final keys = failure.fieldErrors.keys.toSet();
  if (keys.isEmpty) {
    return _isKnownInvalidIdempotencyKeyMessage(failure.userMessage);
  }
  return keys.every(kPostReportTrustedValidationFields.contains);
}

bool _isKnownInvalidIdempotencyKeyMessage(String message) {
  final normalized = message.toLowerCase();
  if (!normalized.contains('idempotency-key')) {
    return false;
  }
  return normalized.contains('uuid v4') ||
      normalized.contains('una sola vez') ||
      normalized.contains('inválid');
}
