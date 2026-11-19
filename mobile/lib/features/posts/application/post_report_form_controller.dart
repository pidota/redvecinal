import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/post_report_reasons.dart';
import '../data/post_report_validation.dart';
import '../data/post_repository.dart';
import 'post_report_coordinator.dart';
import 'post_report_outcome.dart';

class PostReportFormState {
  const PostReportFormState({
    this.selectedReasonCode,
    this.details = '',
    this.reasonError,
    this.detailsError,
    this.boundSessionEpoch,
    this.submitMessage,
    this.submitUncertain = false,
  });

  factory PostReportFormState.initial({int? epoch}) {
    return PostReportFormState(boundSessionEpoch: epoch);
  }

  final String? selectedReasonCode;
  final String details;
  final String? reasonError;
  final String? detailsError;
  final int? boundSessionEpoch;
  final String? submitMessage;
  final bool submitUncertain;

  PostReportFormState copyWith({
    String? selectedReasonCode,
    String? details,
    String? reasonError,
    String? detailsError,
    int? boundSessionEpoch,
    String? submitMessage,
    bool? submitUncertain,
    bool clearReasonError = false,
    bool clearDetailsError = false,
    bool clearSubmitMessage = false,
  }) {
    return PostReportFormState(
      selectedReasonCode: selectedReasonCode ?? this.selectedReasonCode,
      details: details ?? this.details,
      reasonError: clearReasonError ? null : reasonError ?? this.reasonError,
      detailsError:
          clearDetailsError ? null : detailsError ?? this.detailsError,
      boundSessionEpoch: boundSessionEpoch ?? this.boundSessionEpoch,
      submitMessage:
          clearSubmitMessage ? null : submitMessage ?? this.submitMessage,
      submitUncertain: submitUncertain ?? this.submitUncertain,
    );
  }

  String? get detailsForValidation {
    final trimmed = details.trim();
    return trimmed.isEmpty ? null : details;
  }
}

class PostReportFormController
    extends AutoDisposeFamilyNotifier<PostReportFormState, int> {
  @override
  PostReportFormState build(int postId) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return PostReportFormState.initial();
    }
    return PostReportFormState.initial(epoch: epoch);
  }

  int? _authenticatedUserId() {
    try {
      final auth = ref.read(authControllerProvider);
      if (auth is! AuthAuthenticated) {
        return null;
      }
      return auth.user.id;
    } on Object {
      return null;
    }
  }

  void resetForSession() {
    final epoch = neighborhoodSessionEpoch(ref);
    state = PostReportFormState.initial(epoch: epoch);
  }

  void selectReason(String code) {
    if (!isLocalPostReportReasonCode(code)) {
      return;
    }
    state = state.copyWith(selectedReasonCode: code, clearReasonError: true);
  }

  void setDetails(String value) {
    state = state.copyWith(details: value, clearDetailsError: true);
  }

  /// Valida con [validatePostReportInput]; actualiza errores en pantalla.
  bool validateFields() {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      state = PostReportFormState.initial();
      return false;
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null || state.boundSessionEpoch != epoch) {
      state = PostReportFormState.initial(epoch: epoch);
      return false;
    }

    final code = state.selectedReasonCode ?? '';
    if (!isLocalPostReportReasonCode(code)) {
      const msg = 'El motivo del reporte es obligatorio.';
      state = state.copyWith(reasonError: msg, clearDetailsError: true);
      return false;
    }
    final failure = validatePostReportInput(
      reasonCode: code,
      details: state.detailsForValidation,
    );
    if (failure == null) {
      state = state.copyWith(clearReasonError: true, clearDetailsError: true);
      return true;
    }

    final reasonMsg = failure.fieldErrors['reason_code']?.first;
    final detailsMsg = failure.fieldErrors['details']?.first;
    state = state.copyWith(reasonError: reasonMsg, detailsError: detailsMsg);
    return false;
  }

  Future<PostReportSubmitResult> submitConfirmed() async {
    final coordinator = ref.read(postReportCoordinatorProvider.notifier);
    await coordinator.ensureHydrated();

    final userId = _authenticatedUserId();
    final epoch = neighborhoodSessionEpoch(ref);
    if (userId == null || epoch == null || state.boundSessionEpoch != epoch) {
      return const PostReportSubmitDiscarded();
    }

    if (!validateFields()) {
      coordinator.cancelConfirming(userId: userId, postId: arg);
      return const PostReportSubmitValidationFailed();
    }

    final existing = coordinator.recordFor(userId, arg);
    if (existing?.status == PostReportOutcomeStatus.confirmed) {
      return const PostReportSubmitBlocked(
        'Ya enviaste un reporte de esta publicación desde esta aplicación.',
      );
    }
    if (existing?.status == PostReportOutcomeStatus.uncertain) {
      return const PostReportSubmitBlocked(
        'No pudimos confirmar si el reporte fue recibido. Para evitar '
        'duplicados, no lo enviaremos nuevamente desde esta aplicación por ahora.',
      );
    }
    if (existing?.status == PostReportOutcomeStatus.inFlight) {
      return const PostReportSubmitBlocked(
        'El reporte se está enviando. Espera a que termine.',
      );
    }
    if (existing?.status == PostReportOutcomeStatus.persistBlocked) {
      return const PostReportSubmitBlocked(
        'No pudimos registrar el envío de forma segura. Para evitar '
        'duplicados, no lo enviaremos ahora.',
      );
    }
    if (ref.read(postReportCoordinatorProvider).persistUnavailable) {
      return const PostReportSubmitBlocked(
        'No pudimos registrar el envío de forma segura. Para evitar '
        'duplicados, no lo enviaremos ahora.',
      );
    }

    final reasonCode = state.selectedReasonCode!;
    final details = state.detailsForValidation;
    final generation = await coordinator.beginInFlight(
      userId: userId,
      postId: arg,
    );
    if (generation == null) {
      final blocked = coordinator.recordFor(userId, arg);
      if (blocked?.status == PostReportOutcomeStatus.persistBlocked) {
        return const PostReportSubmitBlocked(
          'No pudimos registrar el envío de forma segura. Para evitar '
          'duplicados, no lo enviaremos ahora.',
        );
      }
      return const PostReportSubmitBlocked(
        'No pudimos iniciar el envío de forma exclusiva.',
      );
    }

    final keepAliveLink = ref.keepAlive();
    var postDispatched = false;
    try {
      if (!_sameSession(userId: userId, epoch: epoch)) {
        return const PostReportSubmitDiscarded();
      }
      await ref
          .read(postRepositoryProvider)
          .reportPost(postId: arg, reasonCode: reasonCode, details: details);
      postDispatched = true;

      if (!coordinator.matchesGeneration(
        userId: userId,
        postId: arg,
        generation: generation,
      )) {
        await coordinator.markUncertain(
          userId: userId,
          postId: arg,
          generation: generation,
        );
        return const PostReportSubmitDiscarded();
      }

      final persisted = await coordinator.markConfirmed(
        userId: userId,
        postId: arg,
        generation: generation,
      );
      if (!persisted) {
        _applyIfSameSession(
          userId: userId,
          epoch: epoch,
          next: state.copyWith(submitUncertain: true),
        );
        return const PostReportSubmitUncertain();
      }
      if (!_sameSession(userId: userId, epoch: epoch)) {
        return const PostReportSubmitDiscarded();
      }
      _applyIfSameSession(
        userId: userId,
        epoch: epoch,
        next: state.copyWith(clearSubmitMessage: true, submitUncertain: false),
      );
      return const PostReportSubmitSuccess();
    } on ApiFailure catch (e) {
      if (!coordinator.matchesGeneration(
        userId: userId,
        postId: arg,
        generation: generation,
      )) {
        return const PostReportSubmitDiscarded();
      }

      if (isPostReportOutcomeUncertain(e)) {
        await coordinator.markUncertain(
          userId: userId,
          postId: arg,
          generation: generation,
        );
        _applyIfSameSession(
          userId: userId,
          epoch: epoch,
          next: state.copyWith(submitUncertain: true),
        );
        return const PostReportSubmitUncertain();
      }

      await coordinator.releaseInFlight(
        userId: userId,
        postId: arg,
        generation: generation,
      );

      if (e is ApiValidationFailure) {
        _applyIfSameSession(
          userId: userId,
          epoch: epoch,
          next: state.copyWith(
            reasonError: e.fieldErrors['reason_code']?.first,
            detailsError: e.fieldErrors['details']?.first,
            submitMessage: e.userMessage,
          ),
        );
      } else {
        _applyIfSameSession(
          userId: userId,
          epoch: epoch,
          next: state.copyWith(submitMessage: _messageForFailure(e)),
        );
      }
      return PostReportSubmitFailure(e);
    } catch (_) {
      final existing = coordinator.recordFor(userId, arg);
      if (existing?.status == PostReportOutcomeStatus.confirmed) {
        return const PostReportSubmitDiscarded();
      }
      if (!coordinator.matchesGeneration(
        userId: userId,
        postId: arg,
        generation: generation,
      )) {
        return const PostReportSubmitDiscarded();
      }
      if (postDispatched ||
          existing?.status == PostReportOutcomeStatus.inFlight) {
        await coordinator.markUncertain(
          userId: userId,
          postId: arg,
          generation: generation,
        );
        return const PostReportSubmitUncertain();
      }
      return const PostReportSubmitDiscarded();
    } finally {
      keepAliveLink.close();
    }
  }

  bool _sameSession({required int userId, required int epoch}) {
    try {
      return _authenticatedUserId() == userId &&
          neighborhoodSessionEpoch(ref) == epoch;
    } on Object {
      return false;
    }
  }

  void _applyIfSameSession({
    required int userId,
    required int epoch,
    required PostReportFormState next,
  }) {
    if (!_sameSession(userId: userId, epoch: epoch)) {
      return;
    }
    state = next;
  }

  String _messageForFailure(ApiFailure failure) {
    if (failure is ApiForbiddenFailure) {
      return 'No tienes autorización para reportar esta publicación.';
    }
    if (failure is ApiNotFoundFailure) {
      return 'Esta publicación no está disponible.';
    }
    if (failure is ApiSessionExpiredFailure) {
      return failure.userMessage;
    }
    return failure.userMessage;
  }
}

final postReportFormControllerProvider = NotifierProvider.autoDispose
    .family<PostReportFormController, PostReportFormState, int>(
      PostReportFormController.new,
    );
