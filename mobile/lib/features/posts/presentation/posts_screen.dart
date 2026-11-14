import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../application/feed_controller.dart';
import 'widgets/post_feed_card.dart';

class PostsScreen extends ConsumerWidget {
  const PostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedControllerProvider);
    final feedNotifier = ref.read(feedControllerProvider.notifier);

    return FeatureShellScaffold(
      title: 'Publicaciones',
      phaseLabel: 'Fase 5.4F',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/posts/create'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: feedAsync.when(
        loading: () => const Center(child: RvLoadingIndicator()),
        error:
            (error, _) => NeighborhoodApiError(
              title: 'No pudimos cargar el feed',
              failure:
                  error is ApiFailure ? error : const ApiUnexpectedFailure(),
              onRetry: feedNotifier.refresh,
            ),
        data: (page) {
          Widget mineEntry({bool withOuterPadding = false}) {
            final button = Align(
              alignment: Alignment.centerLeft,
              child: RvPrimaryButton(
                label: 'Mis publicaciones',
                icon: Icons.inventory_2_outlined,
                onPressed: () => context.push('/posts/mine'),
              ),
            );
            if (!withOuterPadding) {
              return button;
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                RvSpacing.md,
                RvSpacing.md,
                RvSpacing.md,
                RvSpacing.sm,
              ),
              child: button,
            );
          }

          if (page.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: feedNotifier.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(RvSpacing.md),
                children: [
                  mineEntry(),
                  const SizedBox(height: RvSpacing.lg),
                  RvEmptyState(
                    title: 'Sin publicaciones',
                    message:
                        'Todavía no hay publicaciones visibles en tus juntas o municipio. '
                        'Cuando haya novedades, aparecerán aquí.',
                    icon: Icons.article_outlined,
                    action: RvPrimaryButton(
                      label: 'Actualizar',
                      icon: Icons.refresh,
                      onPressed: feedNotifier.refresh,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: feedNotifier.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: RvSpacing.md),
              itemCount: page.items.length + 1 + (page.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return mineEntry(withOuterPadding: true);
                }
                final itemIndex = index - 1;
                if (itemIndex >= page.items.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: RvSpacing.md),
                    child: Center(
                      child: RvPrimaryButton(
                        label: 'Cargar más',
                        icon: Icons.expand_more,
                        onPressed:
                            feedAsync.isLoading || feedNotifier.isLoadingMore
                                ? null
                                : feedNotifier.loadMore,
                      ),
                    ),
                  );
                }

                final post = page.items[itemIndex];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    RvSpacing.md,
                    0,
                    RvSpacing.md,
                    RvSpacing.sm,
                  ),
                  child: PostFeedCard(
                    post: post,
                    onOpen:
                        post.status == 'published'
                            ? () => context.push('/posts/${post.id}')
                            : null,
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
