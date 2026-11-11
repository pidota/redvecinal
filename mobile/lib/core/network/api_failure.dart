/// Errores normalizados del cliente API (sin datos sensibles).
sealed class ApiFailure {
  const ApiFailure(this.userMessage);

  final String userMessage;
}

final class ApiNetworkFailure extends ApiFailure {
  const ApiNetworkFailure() : super('No hay conexión con el servidor. Revisa tu red e inténtalo de nuevo.');
}

final class ApiTimeoutFailure extends ApiFailure {
  const ApiTimeoutFailure() : super('La solicitud tardó demasiado. Inténtalo de nuevo.');
}

final class ApiServerFailure extends ApiFailure {
  const ApiServerFailure() : super('El servidor no está disponible por el momento. Inténtalo más tarde.');
}

final class ApiInvalidCredentialsFailure extends ApiFailure {
  const ApiInvalidCredentialsFailure() : super('Las credenciales proporcionadas no son correctas.');
}

final class ApiSessionExpiredFailure extends ApiFailure {
  const ApiSessionExpiredFailure() : super('Tu sesión ya no es válida. Inicia sesión nuevamente.');
}

final class ApiForbiddenFailure extends ApiFailure {
  const ApiForbiddenFailure([String? detail])
      : super(detail ?? 'No tienes permiso para realizar esta acción.');
}

final class ApiValidationFailure extends ApiFailure {
  const ApiValidationFailure(this.fieldErrors)
      : super('Revisa los datos ingresados.');

  final Map<String, List<String>> fieldErrors;
}

final class ApiRateLimitedFailure extends ApiFailure {
  const ApiRateLimitedFailure({this.retryAfter})
      : super('Demasiados intentos. Espera un momento antes de volver a intentar.');

  final Duration? retryAfter;
}

final class ApiUnexpectedFailure extends ApiFailure {
  const ApiUnexpectedFailure() : super('Ocurrió un error inesperado. Inténtalo de nuevo.');
}

final class ApiNotConfiguredFailure extends ApiFailure {
  const ApiNotConfiguredFailure()
      : super('Configura API_BASE_URL al ejecutar la app (ver mobile/README.md).');
}
