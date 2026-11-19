import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rv_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../application/post_report_coordinator.dart';
import '../application/post_report_form_controller.dart';
import '../application/post_report_outcome.dart';
import '../data/post_report_reasons.dart';
import '../data/post_report_validation.dart';

class PostReportScreen extends ConsumerStatefulWidget {
  const PostReportScreen({required this.postId, super.key});

  final int postId;

  @override
  ConsumerState<PostReportScreen> createState() => _PostReportScreenState();
}

class _PostReportScreenState extends ConsumerState<PostReportScreen> {
  late final TextEditingController _detailsController;

  static const _uncertainMessage =
      'No pudimos confirmar si el reporte fue recibido. Para evitar '
      'duplicados, no lo enviaremos nuevamente desde esta aplicación por ahora.';

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(postReportCoordinatorProvider.notifier).ensureHydrated();
    });
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _onSendPressed() async {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return;
    }
    final notifier = ref.read(
      postReportFormControllerProvider(widget.postId).notifier,
    );
    if (!notifier.validateFields()) {
      return;
    }

    final coordinator = ref.read(postReportCoordinatorProvider.notifier);
    await coordinator.ensureHydrated();
    final existing = coordinator.recordFor(auth.user.id, widget.postId);
    if (existing != null &&
        existing.status != PostReportOutcomeStatus.confirming) {
      return;
    }
    if (!coordinator.tryBeginConfirming(
      userId: auth.user.id,
      postId: widget.postId,
    )) {
      return;
    }

    if (!mounted) {
      coordinator.cancelConfirming(userId: auth.user.id, postId: widget.postId);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirmar reporte'),
            content: const Text(
              'Se enviará un reporte sobre esta publicación. El envío no se '
              'puede deshacer desde la aplicación.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar envío'),
              ),
            ],
          ),
    );

    if (confirmed != true) {
      coordinator.cancelConfirming(userId: auth.user.id, postId: widget.postId);
      return;
    }

    final originalUserId = auth.user.id;
    final result = await notifier.submitConfirmed();
    if (!mounted) {
      return;
    }
    final current = ref.read(authControllerProvider);
    if (result is PostReportSubmitSuccess &&
        current is AuthAuthenticated &&
        current.user.id == originalUserId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reporte recibido')));
      if (context.mounted && context.canPop()) {
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reportar publicación'),
          leading: BackButton(onPressed: () => context.pop()),
        ),
        body: const Center(
          child: Text('Inicia sesión para reportar contenido.'),
        ),
      );
    }

    final form = ref.watch(postReportFormControllerProvider(widget.postId));
    final notifier = ref.read(
      postReportFormControllerProvider(widget.postId).notifier,
    );
    final coordinatorState = ref.watch(postReportCoordinatorProvider);
    final outcome = coordinatorState.recordFor(auth.user.id, widget.postId);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is! AuthAuthenticated) {
        notifier.resetForSession();
        _detailsController.clear();
        return;
      }
      if (previous is AuthAuthenticated && previous.user.id != next.user.id) {
        notifier.resetForSession();
        _detailsController.clear();
      }
    });

    final theme = Theme.of(context);
    final inFlight = outcome?.status == PostReportOutcomeStatus.inFlight;
    final confirming = outcome?.status == PostReportOutcomeStatus.confirming;
    final confirmed = outcome?.status == PostReportOutcomeStatus.confirmed;
    final persistBlocked =
        outcome?.status == PostReportOutcomeStatus.persistBlocked ||
        coordinatorState.persistUnavailable;
    final uncertain =
        outcome?.status == PostReportOutcomeStatus.uncertain ||
        form.submitUncertain;
    final blocked =
        confirmed || uncertain || inFlight || confirming || persistBlocked;
    final canEdit = !blocked;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar publicación'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(RvSpacing.md),
        children: [
          Text(
            'Tu reporte se revisará de forma confidencial. No compartimos tu '
            'identidad con otros vecinos.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RvSpacing.md),
          Text('Motivo', style: theme.textTheme.titleSmall),
          const SizedBox(height: RvSpacing.xs),
          ...kPostReportReasonOptions.map((option) {
            return Semantics(
              label: option.label,
              child: RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(option.label),
                value: option.code,
                groupValue: form.selectedReasonCode,
                onChanged:
                    canEdit
                        ? (value) {
                          if (value != null) {
                            notifier.selectReason(value);
                          }
                        }
                        : null,
              ),
            );
          }),
          if (form.reasonError != null) ...[
            Text(
              form.reasonError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: RvSpacing.xs),
          ],
          const SizedBox(height: RvSpacing.md),
          Text('Detalles (opcional)', style: theme.textTheme.titleSmall),
          const SizedBox(height: RvSpacing.xs),
          Semantics(
            label: 'Detalles del reporte',
            child: TextField(
              controller: _detailsController,
              enabled: canEdit,
              maxLength: postReportDetailsMaxLength,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Describe brevemente el problema',
                errorText: form.detailsError,
                border: const OutlineInputBorder(),
              ),
              onChanged: canEdit ? notifier.setDetails : null,
            ),
          ),
          if (inFlight) ...[
            const SizedBox(height: RvSpacing.md),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: RvSpacing.sm),
            const Text('Enviando reporte…'),
          ],
          if (confirmed) ...[
            const SizedBox(height: RvSpacing.md),
            Text(
              'Ya enviaste un reporte de esta publicación desde esta aplicación.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (uncertain) ...[
            const SizedBox(height: RvSpacing.md),
            Text(_uncertainMessage, style: theme.textTheme.bodyMedium),
          ],
          if (persistBlocked && !uncertain) ...[
            const SizedBox(height: RvSpacing.md),
            Text(
              'No pudimos registrar el envío de forma segura. Para evitar '
              'duplicados, no lo enviaremos ahora.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (form.submitMessage != null) ...[
            const SizedBox(height: RvSpacing.md),
            Text(
              form.submitMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: RvSpacing.lg),
          FilledButton(
            onPressed: blocked ? null : _onSendPressed,
            child: const Text('Enviar reporte'),
          ),
          const SizedBox(height: RvSpacing.md),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
