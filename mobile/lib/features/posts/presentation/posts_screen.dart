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
      phaseLabel: 'Fase 5.4C',
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
          if (page.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: feedNotifier.refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: RvEmptyState(
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
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: feedNotifier.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
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
                            feedAsync.isLoading || feedNotifier.isLoadingMore
                                ? null
                                : feedNotifier.loadMore,
                      ),
                    ),
                  );
                }

                final post = page.items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: RvSpacing.sm),
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
