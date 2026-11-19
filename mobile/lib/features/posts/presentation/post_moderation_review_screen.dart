import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../application/post_moderation_approve_support.dart';
import '../application/post_moderation_review_controller.dart';
import '../application/post_moderation_review_key.dart';
import '../application/post_detail_controller.dart';
import '../data/models/post_detail.dart' show PostAttachment, PostDetail;
import '../data/models/post_moderation_review.dart';
import '../data/models/post_moderation_review_state.dart';
import 'widgets/post_attachment_list.dart';
import 'widgets/post_moderation_reject_dialog.dart';

class PostModerationReviewScreen extends ConsumerStatefulWidget {
  const PostModerationReviewScreen({
    required this.groupId,
    required this.postId,
    this.groupName,
    super.key,
  });

  final int groupId;
  final int postId;
  final String? groupName;

  @override
  ConsumerState<PostModerationReviewScreen> createState() =>
      _PostModerationReviewScreenState();
}

class _PostModerationReviewScreenState
    extends ConsumerState<PostModerationReviewScreen> {
  PostModerationReviewKey get _key =>
      PostModerationReviewKey(groupId: widget.groupId, postId: widget.postId);

  bool _confirmInFlight = false;

  bool _canRetry(Object error) {
    if (error is ApiForbiddenFailure || error is ApiSessionExpiredFailure) {
      return false;
    }
    return true;
  }

  Future<void> _confirmAndApprove(PostModerationReviewState state) async {
    if (_confirmInFlight || state.approveInFlight || !state.canOfferApprove) {
      return;
    }
    final review = state.review;
    if (review == null) {
      return;
    }

    final body =
        review.isAmendment
            ? 'Se reemplazará la versión actualmente publicada por la '
                'modificación aprobada.'
            : '¿Deseas aprobar esta publicación? El contenido propuesto '
                'quedará publicado para los vecinos autorizados.';

    _confirmInFlight = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !state.approveInFlight,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Aprobar publicación'),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Aprobar'),
              ),
            ],
          ),
    );
    _confirmInFlight = false;

    if (confirmed != true || !mounted) {
      return;
    }

    final notifier = ref.read(
      postModerationReviewControllerProvider(_key).notifier,
    );
    final result = await notifier.approvePublication();
    if (!mounted) {
      return;
    }

    switch (result) {
      case PostModerationApproveSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Publicación aprobada correctamente.')),
        );
        Navigator.maybePop(context);
      case PostModerationApproveUncertain():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No confirmamos la aprobación. Consulta el estado actual antes '
              'de decidir de nuevo.',
            ),
          ),
        );
      case PostModerationApproveFailure(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.userMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        if (failure is ApiForbiddenFailure) {
          await notifier.refresh();
        }
      case PostModerationApproveBlocked(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case PostModerationApproveDiscarded():
      case PostModerationApproveInFlight():
        break;
    }
  }

  Future<void> _confirmAndReject(PostModerationReviewState state) async {
    if (_confirmInFlight || state.approveInFlight || !state.canOfferReject) {
      return;
    }
    final review = state.review;
    if (review == null) {
      return;
    }

    _confirmInFlight = true;
    final dialogResult = await showPostModerationRejectDialog(
      context: context,
      isAmendment: review.isAmendment,
    );
    _confirmInFlight = false;

    if (dialogResult == null ||
        !dialogResult.isConfirmed ||
        dialogResult.reason == null ||
        !mounted) {
      return;
    }

    final notifier = ref.read(
      postModerationReviewControllerProvider(_key).notifier,
    );
    final result = await notifier.rejectPublication(dialogResult.reason!);
    if (!mounted) {
      return;
    }

    switch (result) {
      case PostModerationRejectSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Publicación rechazada correctamente.')),
        );
        Navigator.maybePop(context);
      case PostModerationRejectUncertain():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No confirmamos el rechazo. Consulta el estado actual antes de '
              'decidir de nuevo.',
            ),
          ),
        );
      case PostModerationRejectValidationFailure(:final failure):
        await showPostModerationRejectDialog(
          context: context,
          isAmendment: review.isAmendment,
          initialValidationMessage: failure.userMessage,
        );
      case PostModerationRejectFailure(:final failure):
        if (failure is ApiValidationFailure &&
            failure.fieldErrors.containsKey('rejection_reason')) {
          await showPostModerationRejectDialog(
            context: context,
            isAmendment: review.isAmendment,
            initialReason: dialogResult.reason,
            initialValidationMessage: failure.userMessage,
          );
          break;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.userMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        if (failure is ApiForbiddenFailure) {
          await notifier.refresh();
        }
      case PostModerationRejectBlocked(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case PostModerationRejectDiscarded():
      case PostModerationRejectInFlight():
        break;
    }
  }

  Future<void> _reconcile() async {
    final notifier = ref.read(
      postModerationReviewControllerProvider(_key).notifier,
    );
    final result = await notifier.reconcileUncertainApprove();
    if (!mounted) {
      return;
    }

    final message = switch (result) {
      PostModerationApproveReconcileStillPending(:final message) => message,
      PostModerationApproveReconcileResolved(:final message) => message,
      PostModerationApproveReconcileStillUncertain(:final message) => message,
      PostModerationApproveReconcileGetFailed(:final failure) =>
        failure.userMessage,
      PostModerationApproveReconcileDiscarded() =>
        'La consulta se canceló por un cambio de sesión.',
    };

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final reviewAsync = ref.watch(postModerationReviewControllerProvider(_key));
    final notifier = ref.read(
      postModerationReviewControllerProvider(_key).notifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisión de moderación'),
        leading: const BackButton(),
      ),
      body: reviewAsync.when(
        loading: () => const Center(child: RvLoadingIndicator()),
        error:
            (error, _) => _ReviewErrorView(
              error: error,
              onRetry: _canRetry(error) ? () => notifier.refresh() : null,
            ),
        data:
            (state) => _ReviewBody(
              state: state,
              groupName: widget.groupName,
              viewerId: _viewerId(ref),
              onRefresh: () => notifier.refresh(),
              onDownload: notifier.downloadAttachment,
              onApprove: () => _confirmAndApprove(state),
              onReject: () => _confirmAndReject(state),
              onReconcile: _reconcile,
            ),
      ),
    );
  }

  int? _viewerId(WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is AuthAuthenticated) {
      return auth.user.id;
    }
    return null;
  }
}

class _ReviewErrorView extends StatelessWidget {
  const _ReviewErrorView({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is ApiForbiddenFailure) {
      return RvEmptyState(
        title: 'Acceso denegado',
        message: (error as ApiForbiddenFailure).userMessage,
        icon: Icons.lock_outline,
        action: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Volver'),
        ),
      );
    }

    if (error is ApiNotFoundFailure) {
      return RvEmptyState(
        title: 'Publicación no disponible',
        message: (error as ApiNotFoundFailure).userMessage,
        icon: Icons.search_off_outlined,
        action: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Volver a la cola'),
        ),
      );
    }

    if (error is ApiSessionExpiredFailure) {
      return RvEmptyState(
        title: 'Sesión finalizada',
        message: (error as ApiSessionExpiredFailure).userMessage,
        icon: Icons.lock_clock_outlined,
        action: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Volver'),
        ),
      );
    }

    return NeighborhoodApiError(
      title: 'No pudimos cargar la revisión',
      failure:
          error is ApiFailure
              ? error as ApiFailure
              : const ApiUnexpectedFailure(),
      onRetry: onRetry ?? () {},
    );
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({
    required this.state,
    required this.onRefresh,
    required this.onDownload,
    required this.onApprove,
    required this.onReject,
    required this.onReconcile,
    this.groupName,
    this.viewerId,
  });

  final PostModerationReviewState state;
  final Future<void> Function() onRefresh;
  final Future<PostAttachmentDownloadResult> Function(PostAttachment attachment)
  onDownload;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final Future<void> Function() onReconcile;
  final String? groupName;
  final int? viewerId;

  bool get _isSelfAuthored =>
      viewerId != null && viewerId == state.detail.author.id;

  bool get _showDecisionButtons =>
      state.canOfferModerationDecision && !_isSelfAuthored;

  @override
  Widget build(BuildContext context) {
    if (!state.isReady) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(RvSpacing.md),
          children: [_BlockedStateView(state: state)],
        ),
      );
    }

    final review = state.review!;
    final detail = state.detail;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(RvSpacing.md),
              children: [
                if (state.approveUncertain) ...[
                  _UncertainApproveBanner(onReconcile: onReconcile),
                  const SizedBox(height: RvSpacing.md),
                ],
                if (state.approveForbidden) ...[
                  const _ApproveForbiddenBanner(),
                  const SizedBox(height: RvSpacing.md),
                ],
                _ReviewHeader(
                  review: review,
                  detail: detail,
                  groupName: groupName,
                ),
                const SizedBox(height: RvSpacing.md),
                _PendingSection(
                  review: review,
                  detail: detail,
                  onDownload: onDownload,
                ),
                if (review.isAmendment) ...[
                  const SizedBox(height: RvSpacing.lg),
                  _PublishedSection(detail: detail, onDownload: onDownload),
                ],
                const SizedBox(height: RvSpacing.xl),
              ],
            ),
          ),
        ),
        if (_showDecisionButtons)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(RvSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.approveInFlight ? null : onReject,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Rechazar publicación'),
                    ),
                  ),
                  const SizedBox(width: RvSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: state.approveInFlight ? null : onApprove,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Aprobar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (state.approveInFlight)
          const Padding(
            padding: EdgeInsets.only(bottom: RvSpacing.md),
            child: RvLoadingIndicator(),
          ),
        if (_isSelfAuthored && state.isReady)
          Padding(
            padding: const EdgeInsets.all(RvSpacing.md),
            child: Text(
              'No puedes aprobar tu propia publicación.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _UncertainApproveBanner extends StatelessWidget {
  const _UncertainApproveBanner({required this.onReconcile});

  final Future<void> Function() onReconcile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(RvSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Decisión de moderación con resultado incierto. No reintentamos '
              'automáticamente.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: RvSpacing.sm),
            TextButton(
              onPressed: onReconcile,
              child: const Text('Consultar estado actual'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApproveForbiddenBanner extends StatelessWidget {
  const _ApproveForbiddenBanner();

  @override
  Widget build(BuildContext context) {
    return const Material(
      child: Padding(
        padding: EdgeInsets.all(RvSpacing.sm),
        child: Text(
          'El servidor indicó que no tienes permiso para moderar esta '
          'publicación.',
        ),
      ),
    );
  }
}

class _BlockedStateView extends StatelessWidget {
  const _BlockedStateView({required this.state});

  final PostModerationReviewState state;

  @override
  Widget build(BuildContext context) {
    switch (state.outcome) {
      case PostModerationReviewOutcome.resolved:
        return RvEmptyState(
          title: 'Propuesta ya resuelta',
          message:
              'Esta publicación ya no está pendiente de moderación '
              '(estado actual: ${_statusLabel(state.detail.status)}). '
              'Actualiza la cola para ver el listado vigente.',
          icon: Icons.check_circle_outline,
          action: TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Volver a la cola'),
          ),
        );
      case PostModerationReviewOutcome.wrongNeighborhoodGroup:
        return const RvEmptyState(
          title: 'Junta incorrecta',
          message:
              'La publicación no pertenece a la junta indicada en esta ruta.',
          icon: Icons.group_off_outlined,
        );
      case PostModerationReviewOutcome.notCommunityPost:
        return const RvEmptyState(
          title: 'No es una publicación comunitaria',
          message:
              'Solo se puede moderar contenido comunitario de juntas de vecinos.',
          icon: Icons.account_balance_outlined,
        );
      case PostModerationReviewOutcome.missingPendingContent:
        return RvEmptyState(
          title: 'Sin contenido pendiente',
          message:
              'El servidor no incluyó el contenido pendiente necesario para '
              'revisar esta publicación.',
          icon: Icons.fact_check_outlined,
          action: TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Volver a la cola'),
          ),
        );
      case PostModerationReviewOutcome.ready:
        return const SizedBox.shrink();
    }
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'pendiente';
    case 'published':
      return 'publicada';
    case 'rejected':
      return 'rechazada';
    case 'draft':
      return 'borrador';
    default:
      return status;
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.review,
    required this.detail,
    this.groupName,
  });

  final PostModerationReview review;
  final PostDetail detail;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kindLabel =
        review.isAmendment ? 'Modificación pendiente' : 'Nueva publicación';
    final junta =
        groupName?.trim().isNotEmpty == true
            ? groupName!.trim()
            : detail.neighborhoodGroup?.name ?? 'Junta vecinal';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kindLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: RvSpacing.sm),
        Text(detail.author.name, style: theme.textTheme.titleSmall),
        const SizedBox(height: RvSpacing.xs),
        Text(
          junta,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (detail.category != null) ...[
          const SizedBox(height: RvSpacing.xs),
          Text(
            detail.category!.name,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.review,
    required this.detail,
    required this.onDownload,
  });

  final PostModerationReview review;
  final PostDetail detail;
  final Future<PostAttachmentDownloadResult> Function(PostAttachment attachment)
  onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = detail.pendingContent!;

    return Material(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(RvSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              review.isAmendment ? 'Modificación propuesta' : 'Propuesta nueva',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: RvSpacing.sm),
            Text(pending.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: RvSpacing.sm),
            Text(pending.displayText, style: theme.textTheme.bodyLarge),
            if (detail.pendingAttachments.isNotEmpty) ...[
              const SizedBox(height: RvSpacing.md),
              Text(
                'Adjuntos de la propuesta',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: RvSpacing.sm),
              PostAttachmentList(
                attachments: detail.pendingAttachments,
                onDownload: (attachment) async {
                  return _attachmentFeedback(await onDownload(attachment));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PublishedSection extends StatelessWidget {
  const _PublishedSection({required this.detail, required this.onDownload});

  final PostDetail detail;
  final Future<PostAttachmentDownloadResult> Function(PostAttachment attachment)
  onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published = detail.content;
    if (published == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Versión actualmente publicada',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: RvSpacing.sm),
        Text(published.title, style: theme.textTheme.titleMedium),
        const SizedBox(height: RvSpacing.sm),
        Text(published.displayText, style: theme.textTheme.bodyMedium),
        if (detail.attachments.isNotEmpty) ...[
          const SizedBox(height: RvSpacing.md),
          Text(
            'Adjuntos publicados',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RvSpacing.sm),
          PostAttachmentList(
            attachments: detail.attachments,
            onDownload: (attachment) async {
              return _attachmentFeedback(await onDownload(attachment));
            },
          ),
        ],
      ],
    );
  }
}

Future<PostAttachmentDownloadFeedback> _attachmentFeedback(
  PostAttachmentDownloadResult result,
) async {
  if (result.sessionEnded) {
    return const PostAttachmentDownloadFeedback(
      message: 'La descarga se canceló porque la sesión cambió.',
      isError: true,
    );
  }
  if (result.failed || result.savedPath == null) {
    return const PostAttachmentDownloadFeedback(
      message: 'No pudimos guardar el archivo.',
      isError: true,
    );
  }
  return const PostAttachmentDownloadFeedback(
    message:
        'Archivo guardado temporalmente en la aplicación. '
        'La opción para abrirlo estará disponible próximamente.',
  );
}
