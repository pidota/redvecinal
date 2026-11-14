/// Límites alineados con `config/red_vecinal.php` (solo validación preventiva en cliente).
abstract final class PostAttachmentLimits {
  static const int maxPerRevision = 5;
  static const int maxSizeBytes = 5120 * 1024;

  static const Set<String> allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
  };

  static const Set<String> allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
  };
}
