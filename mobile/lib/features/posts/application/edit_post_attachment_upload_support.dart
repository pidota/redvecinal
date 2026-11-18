import '../../../core/network/api_failure.dart';

bool isEditPostUploadOutcomeUncertain(ApiFailure failure) {
  return failure is ApiNetworkFailure ||
      failure is ApiTimeoutFailure ||
      failure is ApiServerFailure;
}

const editPostUncertainUploadBlockedMessage =
    'No pudimos confirmar si el archivo se guardó. No reenviaremos '
    'automáticamente ni podrás guardar el texto hasta resolverlo.';

const editPostUploadReconcileInconclusiveMessage =
    'Consultamos el servidor, pero la API no permite confirmar '
    'automáticamente una subida incierta. Solo HTTP 201 confirma el archivo.';
