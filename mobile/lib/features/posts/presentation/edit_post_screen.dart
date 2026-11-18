import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../application/edit_post_attachments_controller.dart';
import '../application/edit_post_controller.dart';
import '../application/edit_post_patch_support.dart';
import '../application/edit_post_uncertain_patch_record.dart';
import 'edit_post_adopt_dialog.dart';
import '../data/models/post_category.dart';
import '../data/post_repository.dart';
import 'widgets/edit_post_attachment_section.dart';

class EditPostScreen extends ConsumerStatefulWidget {
  const EditPostScreen({required this.postId, super.key});

  final int postId;

  @override
  ConsumerState<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends ConsumerState<EditPostScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  PostCategory? _selectedCategory;
  List<PostCategory> _categories = const [];
  bool _categoriesLoading = true;
  Object? _categoriesError;
  bool _formHydrated = false;
  String? _fieldError;
  int _lastSuccessTick = 0;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    try {
      final items = await ref
          .read(postRepositoryProvider)
          .listPostCategories(audience: 'group');
      if (!mounted) {
        return;
      }
      setState(() {
        _categories = items;
        _categoriesLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _categoriesError = e;
        _categoriesLoading = false;
      });
    }
  }

  void _hydrateForm(
    EditPostSnapshot snapshot, {
    EditPostPatchPayload? uncertainAttempt,
  }) {
    if (!snapshot.editable) {
      _formHydrated = false;
      return;
    }
    final working = snapshot.detail.workingContent!;
    final title = uncertainAttempt?.title ?? working.title;
    final body = uncertainAttempt?.body ?? working.body;
    _titleController.text = title;
    _bodyController.text = body;
    final categoryId =
        uncertainAttempt?.categoryId ?? snapshot.detail.category?.id;
    PostCategory? match;
    if (categoryId != null) {
      for (final c in _categories) {
        if (c.id == categoryId) {
          match = c;
          break;
        }
      }
      match ??=
          snapshot.detail.category == null
              ? null
              : PostCategory(
                id: categoryId,
                slug: snapshot.detail.category!.slug,
                name: snapshot.detail.category!.name,
                defaultAudience: 'group',
                sortOrder: 0,
                isSystem: false,
              );
    }
    _selectedCategory = match;
    _formHydrated = true;
  }

  String? _validateForm() {
    if (!_formHydrated) {
      return 'Aún no pudimos cargar el contenido editable.';
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

  String _screenTitle(String status) {
    if (status == 'rejected') {
      return 'Corregir publicación';
    }
    return 'Editar borrador';
  }

  Future<void> _save(EditPostController notifier) async {
    final validation = _validateForm();
    if (validation != null) {
      setState(() => _fieldError = validation);
      return;
    }

    setState(() => _fieldError = null);
    final result = await notifier.save(
      categoryId: _selectedCategory!.id,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case EditPostSaveSuccess():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cambios guardados.')));
      case EditPostSaveFailure(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      case EditPostSaveUncertain():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No confirmamos si el servidor guardó los cambios. '
              'Verifica en el servidor antes de guardar otra vez.',
            ),
          ),
        );
      case EditPostSaveBlocked(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case EditPostSaveDiscarded():
        break;
      case EditPostSaveInFlight():
        break;
    }
  }

  Future<void> _confirmSubmit(EditPostController notifier) async {
    final validation = _validateForm();
    if (validation != null) {
      setState(() => _fieldError = validation);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Enviar a moderación'),
            content: const Text(
              '¿Enviar esta publicación a revisión por los moderadores del grupo? '
              'No se publicará hasta que sea aprobada.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enviar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _submit(notifier);
  }

  Future<void> _submit(EditPostController notifier) async {
    setState(() => _fieldError = null);
    final result = await notifier.submitToModeration(
      categoryId: _selectedCategory!.id,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case EditPostSubmitSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enviada a moderación. Te avisaremos cuando haya novedades.',
            ),
          ),
        );
      case EditPostSubmitFailure(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      case EditPostSubmitUncertain():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No confirmamos si el servidor recibió el envío. '
              'Verifica el estado antes de reenviar.',
            ),
          ),
        );
      case EditPostSubmitBlocked(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case EditPostSubmitDiscarded():
      case EditPostSubmitInFlight():
        break;
    }
  }

  Future<void> _reconcileSubmit(EditPostController notifier) async {
    final result = await notifier.reconcileUncertainSubmit();
    if (!mounted) {
      return;
    }
    switch (result) {
      case EditPostSubmitReconcileObservedPending(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case EditPostSubmitReconcileStillUncertain(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case EditPostSubmitReconcileGetFailed(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      case EditPostSubmitReconcileDiscarded():
        break;
    }
  }

  Future<void> _reconcile(EditPostController notifier) async {
    final result = await notifier.reconcileUncertainPatch();
    if (!mounted) {
      return;
    }
    switch (result) {
      case EditPostReconcileObservableMatch(:final message):
        await _showAdoptOfferDialog(
          notifier: notifier,
          intro: message,
          conflict: false,
        );
      case EditPostReconcileRemoteChanged(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case EditPostReconcileRemoteConflict(:final message):
        await _showAdoptOfferDialog(
          notifier: notifier,
          intro: message,
          conflict: true,
        );
      case EditPostReconcileStillUncertain(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case EditPostReconcileDiscarded():
        break;
    }
  }

  Future<void> _showAdoptOfferDialog({
    required EditPostController notifier,
    required String intro,
    required bool conflict,
  }) async {
    final pending = notifier.pendingUncertainPayload;
    final observation = notifier.lastReconcileObservation;
    final remote = observation?.remote.workingContent;
    if (pending == null || remote == null) {
      return;
    }

    final adopt = await showEditPostAdoptOfferDialog(
      context: context,
      intro: intro,
      conflict: conflict,
      pending: pending,
      remoteTitle: remote.title,
      remoteBody: remote.body,
    );

    if (adopt != true || !mounted) {
      return;
    }

    final adoptResult = notifier.adoptObservedServerState();
    if (!mounted) {
      return;
    }
    switch (adoptResult) {
      case EditPostAdoptSuccess(:final detail):
        setState(() {
          _formHydrated = false;
        });
        final snap = EditPostSnapshot.fromDetail(detail);
        setState(() => _hydrateForm(snap));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Formulario actualizado con el estado observado del servidor.',
            ),
          ),
        );
      case EditPostAdoptBlocked(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case EditPostAdoptDiscarded():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(editPostControllerProvider(widget.postId));
    final notifier = ref.read(
      editPostControllerProvider(widget.postId).notifier,
    );

    ref.listen(editPostControllerProvider(widget.postId), (previous, next) {
      final prevTick = previous?.valueOrNull?.saveSuccessTick ?? 0;
      final nextTick = next.valueOrNull?.saveSuccessTick ?? 0;
      if (nextTick > prevTick && next.hasValue) {
        final snap = next.value!.snapshot;
        if (snap.editable && mounted) {
          _hydrateForm(snap);
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          sessionAsync.valueOrNull?.snapshot.detail.status == 'rejected'
              ? 'Corregir publicación'
              : 'Editar borrador',
        ),
        leading: const BackButton(),
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: RvLoadingIndicator()),
        error:
            (error, _) =>
                _EditLoadError(error: error, onRetry: notifier.reload),
        data: (session) {
          final uncertainAttempt =
              session.patchUncertain ? notifier.pendingUncertainPayload : null;
          if (!_formHydrated && session.snapshot.editable) {
            if (_categories.isEmpty && _categoriesLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadCategories().then((_) {
                  if (mounted) {
                    setState(() {
                      _hydrateForm(
                        session.snapshot,
                        uncertainAttempt: uncertainAttempt,
                      );
                      ref
                          .read(
                            editPostAttachmentsControllerProvider(
                              widget.postId,
                            ).notifier,
                          )
                          .hydrateFromEditableRevision(
                            revisionId: session.snapshot.editableRevisionId!,
                            serverAttachments:
                                session.snapshot.readOnlyAttachments,
                          );
                    });
                  }
                });
              });
            } else if (!_categoriesLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(
                    () => _hydrateForm(
                      session.snapshot,
                      uncertainAttempt: uncertainAttempt,
                    ),
                  );
                }
              });
            }
          }

          if (!session.snapshot.editable) {
            final pendingNote =
                session.patchUncertain &&
                        notifier.pendingUncertainPayload != null
                    ? '\n\nTu último guardado sigue sin confirmación HTTP. '
                        'Revisa el contenido en el servidor antes de asumir '
                        'que se aplicó.'
                    : '';
            return RvEmptyState(
              title: 'No editable',
              message:
                  (session.snapshot.blockMessage ??
                      'Esta publicación no puede editarse desde la app.') +
                  pendingNote,
              icon: Icons.lock_outline,
              action: TextButton(
                onPressed: () => context.pop(),
                child: const Text('Volver'),
              ),
            );
          }

          final snap = session.snapshot;
          final status = snap.detail.status;
          final attachmentsState = ref.watch(
            editPostAttachmentsControllerProvider(widget.postId),
          );
          final attachBusy =
              attachmentsState.uploadInFlight ||
              attachmentsState.reconcileInFlight;
          final submitBusy = session.submitInFlight;
          final moderationBlocked =
              session.patchUncertain ||
              session.submitUncertain ||
              attachBusy ||
              submitBusy;
          if (_lastSuccessTick != session.saveSuccessTick) {
            _lastSuccessTick = session.saveSuccessTick;
          }

          return RefreshIndicator(
            onRefresh: notifier.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(RvSpacing.md),
              children: [
                if (session.submitUncertain) ...[
                  MaterialBanner(
                    forceActionsBelow: true,
                    content: const Text(
                      'El último envío a revisión quedó incierto. '
                      'No repetiremos el envío automáticamente. '
                      'Usa «Verificar estado del envío».',
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            submitBusy
                                ? null
                                : () => _reconcileSubmit(notifier),
                        child: const Text('Verificar estado del envío'),
                      ),
                    ],
                  ),
                  const SizedBox(height: RvSpacing.md),
                ],
                if (session.patchUncertain) ...[
                  MaterialBanner(
                    forceActionsBelow: true,
                    content: Text(
                      session.uncertainPhase ==
                              EditPostUncertainPatchPhase.inFlight
                          ? 'Hay un intento de guardado registrado que podría '
                              'seguir en curso o haberse enviado. No repetiremos '
                              'el PATCH automáticamente. Verifica en el servidor.'
                          : 'El último guardado quedó incierto (incluso si cerraste '
                              'esta pantalla). No repetiremos el envío automáticamente. '
                              'Usa «Verificar en servidor».',
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            session.saveInFlight
                                ? null
                                : () => _reconcile(notifier),
                        child: const Text('Verificar en servidor'),
                      ),
                    ],
                  ),
                  const SizedBox(height: RvSpacing.md),
                ],
                RvCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _screenTitle(status),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: RvSpacing.sm),
                      Text(
                        snap.detail.neighborhoodGroup?.name ?? 'Junta vecinal',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: RvSpacing.xs),
                      Text(
                        'El grupo no puede cambiarse al editar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: RvSpacing.md),
                if (_categoriesLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: RvSpacing.md),
                    child: Center(child: RvLoadingIndicator()),
                  )
                else if (_categoriesError != null)
                  NeighborhoodApiError(
                    title: 'No pudimos cargar categorías',
                    failure:
                        _categoriesError is ApiFailure
                            ? _categoriesError! as ApiFailure
                            : const ApiUnexpectedFailure(),
                    onRetry: _loadCategories,
                  )
                else ...[
                  DropdownButtonFormField<PostCategory>(
                    isExpanded: true,
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged:
                        session.saveInFlight || moderationBlocked
                            ? null
                            : (value) =>
                                setState(() => _selectedCategory = value),
                  ),
                  const SizedBox(height: RvSpacing.md),
                  TextField(
                    controller: _titleController,
                    enabled: !session.saveInFlight && !moderationBlocked,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 200,
                  ),
                  const SizedBox(height: RvSpacing.sm),
                  TextField(
                    controller: _bodyController,
                    enabled: !session.saveInFlight && !moderationBlocked,
                    decoration: const InputDecoration(
                      labelText: 'Contenido',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 8,
                    maxLength: 50000,
                  ),
                  if (_fieldError != null) ...[
                    const SizedBox(height: RvSpacing.sm),
                    Text(
                      _fieldError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: RvSpacing.lg),
                  RvPrimaryButton(
                    label: 'Guardar cambios',
                    icon: Icons.save_outlined,
                    onPressed:
                        session.saveInFlight ||
                                moderationBlocked ||
                                attachmentsState.blocksContentSave
                            ? null
                            : () => _save(notifier),
                  ),
                  const SizedBox(height: RvSpacing.md),
                  RvPrimaryButton(
                    label:
                        status == 'rejected'
                            ? 'Reenviar a revisión'
                            : 'Enviar a revisión',
                    icon: Icons.send_outlined,
                    onPressed:
                        moderationBlocked || attachmentsState.blocksContentSave
                            ? null
                            : () => _confirmSubmit(notifier),
                  ),
                  const SizedBox(height: RvSpacing.lg),
                  EditPostAttachmentSection(
                    postId: widget.postId,
                    busy: session.saveInFlight || moderationBlocked,
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

class _EditLoadError extends StatelessWidget {
  const _EditLoadError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is ApiNotFoundFailure) {
      return RvEmptyState(
        title: 'Publicación no encontrada',
        message: 'No encontramos esta publicación o ya no tienes acceso.',
        icon: Icons.article_outlined,
        action: TextButton(
          onPressed: () => context.pop(),
          child: const Text('Volver'),
        ),
      );
    }
    if (error is ApiSessionExpiredFailure) {
      return RvEmptyState(
        title: 'Sesión finalizada',
        message: (error as ApiSessionExpiredFailure).userMessage,
        icon: Icons.lock_clock_outlined,
        action: TextButton(
          onPressed: () => context.pop(),
          child: const Text('Volver'),
        ),
      );
    }

    return NeighborhoodApiError(
      title: 'No pudimos cargar la publicación',
      failure:
          error is ApiFailure
              ? error as ApiFailure
              : const ApiUnexpectedFailure(),
      onRetry: onRetry,
    );
  }
}
