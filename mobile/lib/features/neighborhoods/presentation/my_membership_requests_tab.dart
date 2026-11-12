import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/my_groups_controller.dart';
import '../application/my_membership_requests_controller.dart';
import '../application/neighborhood_session.dart';
import '../data/models/membership_request.dart';
import 'widgets/membership_request_status_chip.dart';
import 'widgets/neighborhood_api_error.dart';

class MyMembershipRequestsTab extends ConsumerWidget {
  const MyMembershipRequestsTab({super.key});

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

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref, MembershipRequest request) async {
    final epochBefore = neighborhoodSessionEpoch(ref);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: const Text('¿Quieres cancelar tu solicitud de incorporación?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final failure = await ref.read(myMembershipRequestsControllerProvider.notifier).cancelRequest(request);
    if (!context.mounted) {
      return;
    }
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      return;
    }

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitud cancelada')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(myMembershipRequestsControllerProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(myMembershipRequestsControllerProvider.notifier);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => NeighborhoodApiError(
        title: 'No pudimos cargar tus solicitudes',
        failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
        onRetry: () => ref.read(myMembershipRequestsControllerProvider.notifier).refresh(),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const RvEmptyState(
            title: 'Sin solicitudes',
            message:
                'Cuando pidas incorporarte a una junta desde Explorar, '
                'verás el estado de tu solicitud aquí.',
            icon: Icons.description_outlined,
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(myMembershipRequestsControllerProvider.notifier).refresh();
            await ref.read(myGroupsControllerProvider.notifier).refresh();
          },
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
                      onPressed: requestsAsync.isLoading || notifier.isLoadingMore
                          ? null
                          : () => notifier.loadMore(),
                    ),
                  ),
                );
              }

              final request = page.items[index];
              final created = _formatDate(request.createdAt);
              final cancelling = notifier.isCancelling(request.id);

              return Card(
                margin: const EdgeInsets.only(bottom: RvSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(RvSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(request.groupName, style: theme.textTheme.titleMedium),
                          ),
                          MembershipRequestStatusChip(status: request.status),
                        ],
                      ),
                      if (request.municipalityLabel.isNotEmpty) ...[
                        const SizedBox(height: RvSpacing.xs),
                        Text(
                          request.municipalityLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (created != null) ...[
                        const SizedBox(height: RvSpacing.xs),
                        Text('Solicitada: $created', style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: RvSpacing.sm),
                      Text(membershipRequestStatusUserMessage(request.status)),
                      if (request.requestNote != null && request.requestNote!.trim().isNotEmpty) ...[
                        const SizedBox(height: RvSpacing.sm),
                        Text('Tu nota', style: theme.textTheme.labelLarge),
                        const SizedBox(height: RvSpacing.xs),
                        Text(request.requestNote!.trim()),
                      ],
                      if (request.isPending) ...[
                        const SizedBox(height: RvSpacing.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: cancelling
                                ? null
                                : () => _confirmCancel(context, ref, request),
                            icon: cancelling
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.cancel_outlined),
                            label: Text(cancelling ? 'Cancelando…' : 'Cancelar solicitud'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
