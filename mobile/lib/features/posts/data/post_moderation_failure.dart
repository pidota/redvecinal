import '../../../core/network/api_failure.dart';

/// Motivo de rechazo inválido antes de llamar a la API (alineado con validación Laravel).
const int postModerationRejectionReasonMaxLength = 2000;

/// Devuelve un fallo de validación local o `null` si el motivo es aceptable.
ApiValidationFailure? validatePostRejectionReason(String rejectionReason) {
  final trimmed = rejectionReason.trim();
  if (trimmed.isEmpty) {
    return const ApiValidationFailure({
      'rejection_reason': ['El motivo de rechazo es obligatorio.'],
    }, 'El motivo de rechazo es obligatorio.');
  }
  if (rejectionReason.length > postModerationRejectionReasonMaxLength) {
    return const ApiValidationFailure({
      'rejection_reason': [
        'El motivo no puede superar $postModerationRejectionReasonMaxLength caracteres.',
      ],
    }, 'El motivo de rechazo es demasiado largo.');
  }
  return null;
}

/// `422` con solo `message` (sin `errors` por campo) suele ser regla de dominio
/// (p. ej. revisión ya resuelta), no error de formulario.
bool isPostModerationDomainFailure(ApiFailure failure) {
  if (failure is! ApiValidationFailure) {
    return false;
  }
  if (failure.fieldErrors.isNotEmpty) {
    return false;
  }
  final message = failure.userMessage.trim();
  return message.isNotEmpty && message != 'Revisa los datos ingresados.';
}
