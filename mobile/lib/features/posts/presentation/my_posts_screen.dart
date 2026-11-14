import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../application/my_posts_controller.dart';
import 'widgets/my_post_list_card.dart';

class MyPostsScreen extends ConsumerWidget {
  const MyPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(myPostsControllerProvider);
    final notifier = ref.read(myPostsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis publicaciones'),
        leading: const BackButton(),
      ),
      body: listAsync.when(
        loading: () => const Center(child: RvLoadingIndicator()),
        error:
            (error, _) => NeighborhoodApiError(
              title: 'No pudimos cargar tus publicaciones',
              failure:
                  error is ApiFailure ? error : const ApiUnexpectedFailure(),
              onRetry: notifier.refresh,
            ),
        data: (page) {
          if (page.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: notifier.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(RvSpacing.md),
                children: [
                  RvEmptyState(
                    title: 'Sin publicaciones propias',
                    message:
                        'Cuando crees publicaciones en tus juntas, aparecerán aquí '
                        'con su estado actual.',
                    icon: Icons.inventory_2_outlined,
                    action: RvPrimaryButton(
                      label: 'Actualizar',
                      icon: Icons.refresh,
                      onPressed: notifier.refresh,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: notifier.refresh,
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
                            listAsync.isLoading || notifier.isLoadingMore
                                ? null
                                : notifier.loadMore,
                      ),
                    ),
                  );
                }

                final post = page.items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: RvSpacing.sm),
                  child: MyPostListCard(
                    post: post,
                    onOpen: () => _openDetail(context, ref, post.id),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    WidgetRef ref,
    int postId,
  ) async {
    await context.push('/posts/$postId');
  }
}
