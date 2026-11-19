/// Catálogo local de motivos (códigos usados en backend/tests; no es enum API).
class PostReportReasonOption {
  const PostReportReasonOption({required this.code, required this.label});

  final String code;
  final String label;
}

const List<PostReportReasonOption> kPostReportReasonOptions = [
  PostReportReasonOption(code: 'spam', label: 'Spam o publicidad no deseada'),
  PostReportReasonOption(code: 'inappropriate', label: 'Contenido inapropiado'),
];

const Set<String> kPostReportReasonCodes = {'spam', 'inappropriate'};

bool isLocalPostReportReasonCode(String code) {
  return kPostReportReasonCodes.contains(code);
}
