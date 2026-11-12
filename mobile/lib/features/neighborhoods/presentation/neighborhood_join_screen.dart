import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/group_join_controller.dart';
import '../application/my_groups_controller.dart';
import '../application/neighborhood_session.dart';
import '../data/models/membership_request.dart';
import 'widgets/group_status_chip.dart';
import 'widgets/membership_request_status_chip.dart';
import 'widgets/neighborhood_api_error.dart';

class NeighborhoodJoinScreen extends ConsumerStatefulWidget {
  const NeighborhoodJoinScreen({required this.groupId, super.key});

  final int groupId;

  @override
  ConsumerState<NeighborhoodJoinScreen> createState() => _NeighborhoodJoinScreenState();
}

class _NeighborhoodJoinScreenState extends ConsumerState<NeighborhoodJoinScreen> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final epochBefore = neighborhoodSessionEpoch(ref);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitar incorporación'),
        content: const Text('¿Quieres solicitar incorporarte a esta junta de vecinos?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, solicitar')),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final failure = await ref.read(groupJoinControllerProvider(widget.groupId).notifier).submit(
          requestNote: _noteController.text,
        );

    if (!mounted) {
      return;
    }
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      return;
    }

    if (failure != null) {
      final message = failure is ApiConflictFailure
          ? (failure.userMessage.contains('pendiente')
              ? failure.userMessage
              : 'No pudimos crear una solicitud nueva. ${failure.userMessage}')
          : failure.userMessage;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final afterSubmit = ref.read(groupJoinControllerProvider(widget.groupId)).valueOrNull;
    if (afterSubmit?.existingRequest?.isPending == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud enviada. Estará pendiente de revisión.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final joinAsync = ref.watch(groupJoinControllerProvider(widget.groupId));
    final theme = Theme.of(context);
    final notifier = ref.read(groupJoinControllerProvider(widget.groupId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incorporación a la junta'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: joinAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (error is ApiForbiddenFailure) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(RvSpacing.lg),
                child: Text(error.userMessage, textAlign: TextAlign.center),
              ),
            );
          }
          return NeighborhoodApiError(
            title: 'No pudimos cargar la información',
            failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
            onRetry: () => ref.read(groupJoinControllerProvider(widget.groupId).notifier).refresh(),
          );
        },
        data: (data) {
          final group = data.group;
          final request = data.existingRequest;
          final canSubmit = request == null ||
              request.status == 'rejected' ||
              request.status == 'cancelled';
          final isSubmitting = notifier.isSubmitting;

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(groupJoinControllerProvider(widget.groupId).notifier).refresh();
              await ref.read(myGroupsControllerProvider.notifier).refresh();
            },
            child: ListView(
              padding: const EdgeInsets.all(RvSpacing.md),
              children: [
                RvCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(group.name, style: theme.textTheme.headlineSmall)),
                          GroupStatusChip(status: group.status),
                        ],
                      ),
                      const SizedBox(height: RvSpacing.sm),
                      Text(
                        group.municipalityLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (group.address != null && group.address!.trim().isNotEmpty) ...[
                        const SizedBox(height: RvSpacing.md),
                        Text('Dirección', style: theme.textTheme.labelLarge),
                        const SizedBox(height: RvSpacing.xs),
                        Text(group.address!.trim()),
                      ],
                      if (group.description != null && group.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: RvSpacing.md),
                        Text('Descripción', style: theme.textTheme.labelLarge),
                        const SizedBox(height: RvSpacing.xs),
                        Text(group.description!.trim()),
                      ],
                    ],
                  ),
                ),
                if (request != null) ...[
                  const SizedBox(height: RvSpacing.md),
                  RvCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Tu solicitud', style: theme.textTheme.titleMedium),
                            ),
                            MembershipRequestStatusChip(status: request.status),
                          ],
                        ),
                        const SizedBox(height: RvSpacing.sm),
                        Text(membershipRequestStatusUserMessage(request.status)),
                      ],
                    ),
                  ),
                ],
                if (canSubmit && group.status == 'active') ...[
                  const SizedBox(height: RvSpacing.lg),
                  TextField(
                    controller: _noteController,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Nota opcional',
                      hintText: 'Puedes contar por qué quieres unirte',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: RvSpacing.md),
                  RvPrimaryButton(
                    label: isSubmitting ? 'Enviando…' : 'Solicitar incorporación',
                    icon: Icons.how_to_reg_outlined,
                    onPressed: isSubmitting ? null : _submit,
                  ),
                ],
                if (request?.status == 'approved') ...[
                  const SizedBox(height: RvSpacing.md),
                  Text(
                    'Si aún no ves la junta en «Mis juntas», desliza hacia abajo para actualizar.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
