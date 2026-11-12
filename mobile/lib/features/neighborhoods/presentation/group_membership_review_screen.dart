import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/group_membership_review_controller.dart';
import '../application/neighborhood_session.dart';
import '../application/reviewable_groups_controller.dart';
import '../data/models/membership_request.dart';
import 'widgets/membership_request_status_chip.dart';
import 'widgets/neighborhood_api_error.dart';

class GroupMembershipReviewScreen extends ConsumerWidget {
  const GroupMembershipReviewScreen({required this.groupId, super.key});

  final int groupId;

  void _showDecisionFeedback(BuildContext context, ApiFailure failure) {
    final message = failure is ApiTimeoutFailure
        ? '${failure.userMessage} Comprueba el estado de la solicitud antes de decidir de nuevo.'
        : failure.userMessage;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _formatDate(DateTime? date) {
    if (date == null) {
      return null;
    }
    final d = date.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$day/$month/${d.year} $hour:$minute';
  }

  Future<String?> _promptReviewNote(BuildContext context, String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Nota de revisión (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _confirmApprove(BuildContext context, WidgetRef ref, MembershipRequest request) async {
    final epochBefore = neighborhoodSessionEpoch(ref);
    final note = await _promptReviewNote(context, 'Aprobar incorporación');
    if (note == null || !context.mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar aprobación'),
        content: Text(
          '¿Apruebas la incorporación de ${request.requesterDisplayName} '
          'a ${request.groupName}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, aprobar')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final failure = await ref
        .read(groupMembershipReviewControllerProvider(groupId).notifier)
        .approve(request, reviewNote: note);

    if (!context.mounted) {
      return;
    }
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      return;
    }

    if (failure != null) {
      _showDecisionFeedback(context, failure);
      if (failure is ApiForbiddenFailure) {
        await ref.read(reviewableGroupsControllerProvider.notifier).refresh();
        if (context.mounted) {
          context.pop();
        }
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitud aprobada.')),
    );
  }

  Future<void> _confirmReject(BuildContext context, WidgetRef ref, MembershipRequest request) async {
    final epochBefore = neighborhoodSessionEpoch(ref);
    final note = await _promptReviewNote(context, 'Rechazar solicitud');
    if (note == null || !context.mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar rechazo'),
        content: Text(
          '¿Rechazas la solicitud de ${request.requesterDisplayName} '
          'para ${request.groupName}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, rechazar')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final failure = await ref
        .read(groupMembershipReviewControllerProvider(groupId).notifier)
        .reject(request, reviewNote: note);

    if (!context.mounted) {
      return;
    }
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      return;
    }

    if (failure != null) {
      _showDecisionFeedback(context, failure);
      if (failure is ApiForbiddenFailure) {
        await ref.read(reviewableGroupsControllerProvider.notifier).refresh();
        if (context.mounted) {
          context.pop();
        }
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitud rechazada.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(groupMembershipReviewControllerProvider(groupId));
    final notifier = ref.read(groupMembershipReviewControllerProvider(groupId).notifier);
    final theme = Theme.of(context);
    final items = listAsync.valueOrNull?.items;
    final groupName = items != null && items.isNotEmpty ? items.first.groupName : 'Junta';

    return Scaffold(
      appBar: AppBar(
        title: Text('Pendientes — $groupName'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (error is ApiForbiddenFailure) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(RvSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error.userMessage, textAlign: TextAlign.center),
                    const SizedBox(height: RvSpacing.md),
                    FilledButton(
                      onPressed: () async {
                        await ref.read(reviewableGroupsControllerProvider.notifier).refresh();
                        if (context.mounted) {
                          context.go('/neighborhoods');
                        }
                      },
                      child: const Text('Volver a juntas'),
                    ),
                  ],
                ),
              ),
            );
          }
          return NeighborhoodApiError(
            title: 'No pudimos cargar las solicitudes',
            failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
            onRetry: () => ref.read(groupMembershipReviewControllerProvider(groupId).notifier).refresh(),
          );
        },
        data: (page) {
          if (page.items.isEmpty) {
            return const RvEmptyState(
              title: 'Sin solicitudes pendientes',
              message: 'No hay solicitudes de incorporación pendientes para esta junta.',
              icon: Icons.inbox_outlined,
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(groupMembershipReviewControllerProvider(groupId).notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(RvSpacing.md),
              itemCount: page.items.length + (page.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= page.items.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: RvSpacing.md),
                    child: Center(
                      child: RvPrimaryButton(
                        label: 'Cargar más',
                        icon: Icons.expand_more,
                        onPressed:
                            listAsync.isLoading || notifier.isLoadingMore ? null : () => notifier.loadMore(),
                      ),
                    ),
                  );
                }

                final request = page.items[index];
                final created = _formatDate(request.createdAt);
                final deciding = notifier.isDeciding(request.id);

                return Card(
                  margin: const EdgeInsets.only(bottom: RvSpacing.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(RvSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                request.requesterDisplayName,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            MembershipRequestStatusChip(status: request.status),
                          ],
                        ),
                        if (created != null) ...[
                          const SizedBox(height: RvSpacing.xs),
                          Text('Solicitud: $created', style: theme.textTheme.bodySmall),
                        ],
                        if (request.requestNote != null && request.requestNote!.trim().isNotEmpty) ...[
                          const SizedBox(height: RvSpacing.sm),
                          Text(request.requestNote!.trim()),
                        ],
                        const SizedBox(height: RvSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: deciding
                                    ? null
                                    : () => _confirmReject(context, ref, request),
                                child: Text(deciding ? 'Procesando…' : 'Rechazar'),
                              ),
                            ),
                            const SizedBox(width: RvSpacing.sm),
                            Expanded(
                              child: FilledButton(
                                onPressed: deciding
                                    ? null
                                    : () => _confirmApprove(context, ref, request),
                                child: Text(deciding ? 'Procesando…' : 'Aprobar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
