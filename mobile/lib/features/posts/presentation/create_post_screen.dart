import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../../neighborhoods/application/my_groups_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../../neighborhoods/data/models/neighborhood_group.dart';
import '../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../application/create_post_controller.dart';
import '../application/create_post_session_persistence.dart';
import '../application/draft_recovery_controller.dart';
import '../data/models/post_category.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  NeighborhoodGroup? _selectedGroup;
  PostCategory? _selectedCategory;
  bool _localSubmitting = false;
  String? _fieldError;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String? _validateForm() {
    if (_selectedGroup == null) {
      return 'Selecciona una junta vecinal.';
    }
    if (_selectedCategory == null) {
      return 'Selecciona una categoría.';
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return 'El título es obligatorio.';
    }
    if (title.length > 200) {
      return 'El título no puede superar 200 caracteres.';
    }
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      return 'El contenido es obligatorio.';
    }
    if (body.length > 50000) {
      return 'El contenido no puede superar 50000 caracteres.';
    }
    return null;
  }

  Future<void> _sendForReview() async {
    if (_localSubmitting) {
      return;
    }

    final validation = _validateForm();
    if (validation != null) {
      setState(() => _fieldError = validation);
      return;
    }

    final epochBefore = neighborhoodSessionEpoch(ref);
    if (epochBefore == null) {
      return;
    }

    setState(() {
      _fieldError = null;
      _localSubmitting = true;
    });

    final result = await ref
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: _selectedGroup!.id,
          categoryId: _selectedCategory!.id,
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
        );

    if (!mounted) {
      return;
    }

    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      ref.read(createPostControllerProvider.notifier).releaseStaleSubmitUi();
      setState(() => _localSubmitting = false);
      return;
    }

    setState(() => _localSubmitting = false);
    await _handleSendResult(context, result);
  }

  Future<void> _retrySubmit() async {
    if (_localSubmitting) {
      return;
    }

    final epochBefore = neighborhoodSessionEpoch(ref);
    if (epochBefore == null) {
      return;
    }

    setState(() => _localSubmitting = true);
    final result =
        await ref.read(createPostControllerProvider.notifier).retrySubmitOnly();

    if (!mounted) {
      return;
    }
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      ref.read(createPostControllerProvider.notifier).releaseStaleSubmitUi();
      setState(() => _localSubmitting = false);
      return;
    }

    setState(() => _localSubmitting = false);
    await _handleSendResult(context, result);
  }

  Future<void> _verifyDraftStatus() async {
    if (_localSubmitting) {
      return;
    }

    final epochBefore = neighborhoodSessionEpoch(ref);
    if (epochBefore == null) {
      return;
    }

    setState(() => _localSubmitting = true);
    final result =
        await ref
            .read(createPostControllerProvider.notifier)
            .refreshDraftStatusAndMaybeSubmit();

    if (!mounted) {
      return;
    }
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      ref.read(createPostControllerProvider.notifier).releaseStaleSubmitUi();
      setState(() => _localSubmitting = false);
      return;
    }

    setState(() => _localSubmitting = false);
    await _handleSendResult(context, result);
  }

  Future<void> _loadRecoveryPage() async {
    await ref.read(draftRecoveryControllerProvider.notifier).loadNextPage();
  }

  Future<void> _linkRecoveryCandidate(int postId) async {
    if (_localSubmitting) {
      return;
    }

    final epochBefore = neighborhoodSessionEpoch(ref);
    if (epochBefore == null) {
      return;
    }

    setState(() => _localSubmitting = true);
    final result = await ref
        .read(createPostControllerProvider.notifier)
        .linkExplicitRecoveryDraft(postId);

    if (!mounted) {
      return;
    }
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      ref.read(createPostControllerProvider.notifier).releaseStaleSubmitUi();
      setState(() => _localSubmitting = false);
      return;
    }

    setState(() => _localSubmitting = false);
    await _handleSendResult(context, result);
  }

  Future<void> _handleSendResult(
    BuildContext context,
    CreatePostSendResult result,
  ) async {
    switch (result) {
      case CreatePostSendSuccess(:final detail):
        if (detail.status == 'pending') {
          ref.read(createPostControllerProvider.notifier).resetAfterSuccess();
          await showDialog<void>(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text('Enviado a revisión'),
                  content: const Text(
                    'Tu publicación quedó pendiente de aprobación. '
                    'No aparecerá en el feed hasta que un moderador la apruebe.',
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Entendido'),
                    ),
                  ],
                ),
          );
          if (context.mounted) {
            context.pop();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'La publicación quedó en estado «${detail.status}». '
                'No hay más acciones desde este formulario.',
              ),
            ),
          );
        }
      case CreatePostSendAlreadyPending(:final detail):
        ref.read(createPostControllerProvider.notifier).resetAfterSuccess();
        await showDialog<void>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Ya en revisión'),
                content: Text(
                  'La publicación #${detail.id} ya está pendiente de moderación. '
                  'No confirmamos que corresponda a tu último intento de envío.',
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
        );
      case CreatePostSendDraftLinked(:final draftId):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Usarás el borrador #$draftId. '
              'Si no coincide con tu intento, no envíes a revisión.',
            ),
          ),
        );
      case CreatePostSendCreateFailed(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      case CreatePostSendDraftOnly(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El borrador se guardó, pero no pudimos enviarlo a revisión: '
              '${failure.userMessage}',
            ),
          ),
        );
      case CreatePostSendUncertain():
        ref.read(draftRecoveryControllerProvider.notifier).reset();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos confirmar si el servidor guardó un borrador. '
              'Revisa tus publicaciones propias antes de intentar otro envío completo.',
            ),
          ),
        );
      case CreatePostSendInFlight():
        break;
      case CreatePostSendDiscarded():
        ref.read(createPostControllerProvider.notifier).releaseStaleSubmitUi();
        break;
      case CreatePostSendNoSession():
        ref.read(createPostControllerProvider.notifier).releaseStaleSubmitUi();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(createPostControllerProvider);
    final sessionFlags = ref.watch(createPostSessionPersistenceProvider);
    final recovery = ref.watch(draftRecoveryControllerProvider);
    final groupsAsync = ref.watch(myGroupsControllerProvider);
    final categoriesAsync = ref.watch(postCategoriesProvider);
    final theme = Theme.of(context);
    final confirmedDraftId =
        sessionFlags.confirmedDraftId ?? workflow.confirmedDraftId;
    final uncertainCreate =
        sessionFlags.uncertainCreate || workflow.uncertainCreate;
    final blocksFullSend =
        sessionFlags.blocksFullSend || workflow.blocksFullSend;
    final busy =
        _localSubmitting || workflow.phase == CreatePostPhase.submitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva publicación'),
        leading: BackButton(onPressed: busy ? null : () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(RvSpacing.md),
        children: [
          if (confirmedDraftId != null) ...[
            RvCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Borrador guardado (#$confirmedDraftId)',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: RvSpacing.sm),
                  const Text(
                    'El borrador existe en el servidor, pero el envío a revisión falló o quedó pendiente.',
                  ),
                  const SizedBox(height: RvSpacing.sm),
                  Wrap(
                    spacing: RvSpacing.sm,
                    children: [
                      RvPrimaryButton(
                        label: 'Reintentar envío',
                        icon: Icons.send,
                        onPressed: busy ? null : _retrySubmit,
                      ),
                      TextButton(
                        onPressed: busy ? null : _verifyDraftStatus,
                        child: const Text('Comprobar estado'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: RvSpacing.md),
          ],
          if (uncertainCreate) ...[
            RvCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resultado incierto', style: theme.textTheme.titleSmall),
                  const SizedBox(height: RvSpacing.sm),
                  const Text(
                    'El servidor pudo haber creado un borrador o no. '
                    'Revisa tus borradores y elige uno solo si reconoces que podría ser el tuyo.',
                  ),
                  const SizedBox(height: RvSpacing.sm),
                  RvPrimaryButton(
                    label:
                        recovery.candidates.isEmpty
                            ? 'Cargar mis borradores'
                            : 'Cargar más páginas',
                    icon: Icons.library_books_outlined,
                    onPressed:
                        busy || recovery.isLoading || !recovery.hasMore
                            ? null
                            : _loadRecoveryPage,
                  ),
                  if (recovery.isLoading) ...[
                    const SizedBox(height: RvSpacing.sm),
                    const Center(child: RvLoadingIndicator()),
                  ],
                  if (recovery.failure != null) ...[
                    const SizedBox(height: RvSpacing.sm),
                    NeighborhoodApiError(
                      title: 'No pudimos consultar tus publicaciones',
                      failure:
                          recovery.failure is ApiFailure
                              ? recovery.failure! as ApiFailure
                              : const ApiUnexpectedFailure(),
                      onRetry: _loadRecoveryPage,
                    ),
                  ],
                  if (recovery.candidates.isNotEmpty) ...[
                    const SizedBox(height: RvSpacing.md),
                    const Text('Borradores encontrados (solo referencia):'),
                    const SizedBox(height: RvSpacing.sm),
                    for (final candidate in recovery.candidates)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('#${candidate.id} · ${candidate.title}'),
                        subtitle: Text('Estado: ${candidate.status}'),
                        trailing: TextButton(
                          onPressed:
                              busy
                                  ? null
                                  : () => _linkRecoveryCandidate(candidate.id),
                          child: const Text('Usar este'),
                        ),
                      ),
                  ],
                  if (!recovery.isLoading &&
                      recovery.allPagesLoaded &&
                      recovery.candidates.isEmpty) ...[
                    const SizedBox(height: RvSpacing.sm),
                    const Text(
                      'No vimos borradores en las páginas consultadas. '
                      'Aún podría existir uno en otra página si no cargaste todo.',
                    ),
                  ],
                  if (!recovery.isLoading &&
                      recovery.candidates.isEmpty &&
                      recovery.hasMore) ...[
                    const SizedBox(height: RvSpacing.sm),
                    const Text(
                      'Hay más páginas sin revisar. Carga más antes de concluir que no hay borradores.',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: RvSpacing.md),
          ],
          _GroupsField(
            groupsAsync: groupsAsync,
            selected: _selectedGroup,
            enabled: !busy,
            onChanged:
                (g) => setState(() {
                  _selectedGroup = g;
                  _fieldError = null;
                }),
          ),
          const SizedBox(height: RvSpacing.md),
          _CategoriesField(
            categoriesAsync: categoriesAsync,
            selected: _selectedCategory,
            enabled: !busy,
            onChanged:
                (c) => setState(() {
                  _selectedCategory = c;
                  _fieldError = null;
                }),
          ),
          const SizedBox(height: RvSpacing.md),
          TextField(
            controller: _titleController,
            enabled: !busy,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Título',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: RvSpacing.md),
          TextField(
            controller: _bodyController,
            enabled: !busy,
            minLines: 6,
            maxLines: 14,
            maxLength: 50000,
            decoration: const InputDecoration(
              labelText: 'Contenido',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_fieldError != null) ...[
            const SizedBox(height: RvSpacing.sm),
            Text(
              _fieldError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: RvSpacing.lg),
          if (blocksFullSend) ...[
            Text(
              'El envío completo está pausado hasta revisar tus borradores o '
              'enlazar uno existente.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: RvSpacing.sm),
          ],
          RvPrimaryButton(
            label: 'Enviar a revisión',
            icon: Icons.send,
            onPressed: busy || blocksFullSend ? null : _sendForReview,
          ),
        ],
      ),
    );
  }
}

class _GroupsField extends ConsumerWidget {
  const _GroupsField({
    required this.groupsAsync,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final AsyncValue<List<NeighborhoodGroup>> groupsAsync;
  final NeighborhoodGroup? selected;
  final bool enabled;
  final ValueChanged<NeighborhoodGroup?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return groupsAsync.when(
      loading: () => const Center(child: RvLoadingIndicator()),
      error:
          (error, _) => NeighborhoodApiError(
            title: 'No pudimos cargar tus juntas',
            failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
            onRetry:
                () => ref.read(myGroupsControllerProvider.notifier).refresh(),
          ),
      data: (groups) {
        final eligible =
            groups
                .where((g) => isNeighborhoodGroupEligibleForPosting(g.status))
                .toList();
        if (eligible.isEmpty) {
          return const RvEmptyState(
            title: 'Sin juntas disponibles',
            message:
                'Necesitas una membresía activa en una junta que admita publicaciones.',
            icon: Icons.groups_outlined,
          );
        }
        return DropdownButtonFormField<NeighborhoodGroup>(
          value:
              selected != null && eligible.any((g) => g.id == selected!.id)
                  ? selected
                  : null,
          decoration: const InputDecoration(
            labelText: 'Junta vecinal',
            border: OutlineInputBorder(),
          ),
          items:
              eligible
                  .map(
                    (g) => DropdownMenuItem(
                      value: g,
                      child: Text('${g.name} (${g.municipalityLabel})'),
                    ),
                  )
                  .toList(),
          onChanged: enabled ? onChanged : null,
        );
      },
    );
  }
}

class _CategoriesField extends ConsumerWidget {
  const _CategoriesField({
    required this.categoriesAsync,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final AsyncValue<List<PostCategory>> categoriesAsync;
  final PostCategory? selected;
  final bool enabled;
  final ValueChanged<PostCategory?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return categoriesAsync.when(
      loading: () => const Center(child: RvLoadingIndicator()),
      error:
          (error, _) => NeighborhoodApiError(
            title: 'No pudimos cargar las categorías',
            failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
            onRetry: () => ref.invalidate(postCategoriesProvider),
          ),
      data: (categories) {
        if (categories.isEmpty) {
          return const RvEmptyState(
            title: 'Sin categorías',
            message:
                'No hay categorías comunitarias disponibles para tu sesión.',
            icon: Icons.category_outlined,
          );
        }
        return DropdownButtonFormField<PostCategory>(
          value:
              selected != null && categories.any((c) => c.id == selected!.id)
                  ? selected
                  : null,
          decoration: const InputDecoration(
            labelText: 'Categoría',
            border: OutlineInputBorder(),
          ),
          items:
              categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
          onChanged: enabled ? onChanged : null,
        );
      },
    );
  }
}
