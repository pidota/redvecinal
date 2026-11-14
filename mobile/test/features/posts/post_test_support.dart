import 'package:dio/dio.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/models/post_category.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_post_comments.dart';
import 'package:red_vecinal/features/posts/data/models/post_attachment_upload_result.dart';
import 'package:red_vecinal/features/posts/data/models/post_comment.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/models/post_reaction.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

Map<String, dynamic> sampleCommunityPostJson({
  int id = 1,
  String title = 'Aviso de reunión',
  String body = 'Se invita a la reunión del viernes en la sede.',
}) {
  return {
    'id': id,
    'post_kind': 'community',
    'status': 'published',
    'comments_enabled': true,
    'published_at': '2026-11-14T12:00:00+00:00',
    'author': {'id': 10, 'name': 'María Vecina'},
    'neighborhood_group': {
      'id': 2,
      'name': 'Junta Centro',
      'slug': 'junta-centro',
    },
    'category': {
      'id': 2,
      'slug': 'aviso-comunitario',
      'name': 'Aviso comunitario',
    },
    'municipality': {'id': 1, 'name': 'Chépica', 'slug': 'chepica'},
    'content': {
      'revision_id': 5,
      'title': title,
      'body': body,
      'body_html': '<p>$body</p>',
      'category_id': 2,
    },
    'engagement': {
      'comments_count': 2,
      'reactions_count': 4,
      'my_reaction': {'type': 'like'},
    },
    'attachments': [
      {
        'id': 7,
        'revision_id': 5,
        'original_display_name': 'informe.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 1000,
        'download_url': '/api/v1/posts/$id/attachments/7',
      },
    ],
    'pending_attachments': [],
  };
}

Map<String, dynamic> sampleMunicipalPostJson({int id = 9}) {
  return {
    'id': id,
    'post_kind': 'municipal',
    'status': 'published',
    'comments_enabled': true,
    'published_at': '2026-11-10T09:00:00+00:00',
    'author': {'id': 3, 'name': 'Municipalidad'},
    'neighborhood_group': null,
    'category': {
      'id': 1,
      'slug': 'comunicado-municipal',
      'name': 'Comunicado municipal',
    },
    'municipality': {'id': 1, 'name': 'Chépica', 'slug': 'chepica'},
    'content': {
      'revision_id': 1,
      'title': 'Feria vecinal',
      'body': 'Información oficial.',
      'body_html': '<p>Información oficial.</p>',
      'category_id': 1,
    },
    'engagement': {
      'comments_count': 0,
      'reactions_count': 0,
      'my_reaction': null,
    },
    'attachments': [],
    'pending_attachments': [],
  };
}

FeedPost sampleCommunityPost({int id = 1}) =>
    FeedPost.fromJson(sampleCommunityPostJson(id: id));

FeedPost sampleMunicipalPost({int id = 9}) =>
    FeedPost.fromJson(sampleMunicipalPostJson(id: id));

PostDetail sampleCommunityPostDetail({int id = 1}) =>
    PostDetail.fromJson(sampleCommunityPostJson(id: id));

PostDetail sampleMunicipalPostDetail({int id = 9}) =>
    PostDetail.fromJson(sampleMunicipalPostJson(id: id));

Map<String, dynamic> sampleCommentJson({
  int id = 100,
  int postId = 1,
  String body = 'Gracias por el aviso.',
  String? authorName,
}) {
  return {
    'id': id,
    'post_id': postId,
    'municipality_id': 1,
    'author_id': 44,
    'author': {'id': 44, 'name': authorName ?? 'Pedro Vecino'},
    'body': body,
    'status': 'visible',
    'created_at': '2026-11-14T13:00:00+00:00',
    'updated_at': '2026-11-14T13:00:00+00:00',
  };
}

PostComment sampleComment({int id = 100, int postId = 1, String? body}) =>
    PostComment.fromJson(
      sampleCommentJson(
        id: id,
        postId: postId,
        body: body ?? 'Gracias por el aviso.',
      ),
    );

PostComment sampleCommentChronological({
  required int id,
  int postId = 1,
  required String createdAt,
  String? body,
}) {
  return PostComment.fromJson({
    ...sampleCommentJson(
      id: id,
      postId: postId,
      body: body ?? 'Comentario $id',
    ),
    'created_at': createdAt,
    'updated_at': createdAt,
  });
}

PaginatedPostComments sampleCommentsPage({
  List<PostComment>? items,
  int currentPage = 1,
  int lastPage = 1,
}) {
  return PaginatedPostComments(
    items: items ?? [sampleComment()],
    currentPage: currentPage,
    lastPage: lastPage,
  );
}

class FakePostGateway implements PostGateway {
  FakePostGateway({
    PaginatedFeedPosts? feedPage,
    this.feedFailure,
    this.feedFailurePage,
    this.feedDelayMs = 0,
    this.pagesByNumber,
    this.callCount = 0,
    this.detailById,
    this.detailFailureById,
    this.detailFailureAfterCalls,
    this.detailDelayMs = 0,
    this.attachmentBytesById,
    this.downloadFailure,
    this.downloadDelayMs = 0,
    this.commentsByPostId,
    this.commentsFailureByPostId,
    this.commentsDelayMs = 0,
    this.createCommentFailureByPostId,
    this.createCommentDelayMs = 0,
    this.createdCommentByPostId,
    this.commentPagesByPostId,
    this.setReactionFailureByPostId,
    this.removeReactionFailureByPostId,
    this.reactionDelayMs = 0,
    this.onSetReaction,
    this.onRemoveReaction,
    this.onCreateComment,
    this.postCategories,
    this.categoriesFailure,
    this.categoriesDelayMs = 0,
    this.createPostFailure,
    this.submitFailureByPostId,
    this.createPostDelayMs = 0,
    this.submitPostDelayMs = 0,
    this.myPostsPage,
    this.myPostsByPage,
    this.myPostsFailure,
    this.myPostsDelayMs = 0,
    this.onCreatePost,
    this.onSubmitPost,
    this.createPostThrowsRaw = false,
    this.uploadFailureByPostId,
    this.uploadThrowsUncertain = false,
    this.uploadDelayMs = 0,
  }) : feedPage =
           feedPage ??
           PaginatedFeedPosts(
             items: [sampleCommunityPost()],
             currentPage: 1,
             lastPage: 1,
           );

  final PaginatedFeedPosts feedPage;
  Object? feedFailure;
  int? feedFailurePage;
  int feedDelayMs;
  Map<int, PaginatedFeedPosts>? pagesByNumber;
  int callCount;
  Map<int, PostDetail>? detailById;
  Map<int, Object?>? detailFailureById;
  int? detailFailureAfterCalls;
  int detailDelayMs;
  Map<int, List<int>>? attachmentBytesById;
  Object? downloadFailure;
  int downloadDelayMs;
  Map<int, PaginatedPostComments>? commentsByPostId;
  Map<int, Object?>? commentsFailureByPostId;
  int commentsDelayMs;
  Map<int, Object?>? createCommentFailureByPostId;
  int createCommentDelayMs;
  Map<int, PostComment Function(String body)>? createdCommentByPostId;
  Map<int, Map<int, PaginatedPostComments>>? commentPagesByPostId;
  Map<int, Object?>? setReactionFailureByPostId;
  Map<int, Object?>? removeReactionFailureByPostId;
  int reactionDelayMs;
  void Function(int postId, String type)? onSetReaction;
  void Function(int postId)? onRemoveReaction;
  void Function(int postId, String body)? onCreateComment;
  List<PostCategory>? postCategories;
  Object? categoriesFailure;
  int categoriesDelayMs;
  Object? createPostFailure;
  Map<int, Object?>? submitFailureByPostId;
  int createPostDelayMs;
  int submitPostDelayMs;
  PaginatedFeedPosts? myPostsPage;
  Map<int, PaginatedFeedPosts>? myPostsByPage;
  Object? myPostsFailure;
  int myPostsDelayMs;
  void Function(int groupId, int categoryId, String title, String body)?
  onCreatePost;
  void Function(int postId)? onSubmitPost;
  bool createPostThrowsRaw;
  Map<int, Object?>? uploadFailureByPostId;
  bool uploadThrowsUncertain;
  int uploadDelayMs;

  int detailCallCount = 0;
  int uploadCallCount = 0;
  final List<Map<String, dynamic>> uploadPayloads = [];
  int downloadCallCount = 0;
  int listCommentsCallCount = 0;
  int createCommentCallCount = 0;
  int setReactionCallCount = 0;
  int removeReactionCallCount = 0;
  int listCategoriesCallCount = 0;
  int createPostCallCount = 0;
  int submitPostCallCount = 0;
  int listMyPostsCallCount = 0;
  final List<String> createCommentBodies = [];
  final List<Map<String, dynamic>> createPostPayloads = [];

  @override
  Future<PaginatedFeedPosts> listPosts({
    int page = 1,
    int? neighborhoodGroupId,
  }) async {
    callCount++;
    if (feedDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: feedDelayMs));
    }
    if (feedFailure != null &&
        (feedFailurePage == null || feedFailurePage == page)) {
      throw feedFailure!;
    }
    final pages = pagesByNumber;
    if (pages != null) {
      return pages[page] ??
          PaginatedFeedPosts(
            items: const [],
            currentPage: page,
            lastPage: feedPage.lastPage,
          );
    }
    if (page > 1) {
      return PaginatedFeedPosts(
        items: const [],
        currentPage: page,
        lastPage: feedPage.lastPage,
      );
    }
    return feedPage;
  }

  @override
  Future<PostDetail> getPost(int postId) async {
    detailCallCount++;
    if (detailDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: detailDelayMs));
    }
    if (detailFailureAfterCalls != null &&
        detailCallCount > detailFailureAfterCalls!) {
      throw const ApiNetworkFailure();
    }
    final failure = detailFailureById?[postId];
    if (failure != null) {
      throw failure;
    }
    final detail = detailById?[postId];
    if (detail != null) {
      return detail;
    }
    return sampleCommunityPostDetail(id: postId);
  }

  @override
  Future<List<int>> downloadAttachment({
    required int postId,
    required int attachmentId,
    String? relativePath,
  }) async {
    downloadCallCount++;
    if (downloadDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: downloadDelayMs));
    }
    if (downloadFailure != null) {
      throw downloadFailure!;
    }
    final bytes = attachmentBytesById?[attachmentId];
    if (bytes != null) {
      return bytes;
    }
    return [0x25, 0x50, 0x44, 0x46];
  }

  @override
  Future<PaginatedPostComments> listComments({
    required int postId,
    int page = 1,
  }) async {
    listCommentsCallCount++;
    if (commentsDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: commentsDelayMs));
    }
    final failure = commentsFailureByPostId?[postId];
    if (failure != null) {
      throw failure;
    }
    final pagesForPost = commentPagesByPostId?[postId];
    if (pagesForPost != null) {
      return pagesForPost[page] ??
          PaginatedPostComments(
            items: const [],
            currentPage: page,
            lastPage: pagesForPost.values.first.lastPage,
          );
    }
    final pageData = commentsByPostId?[postId];
    if (pageData != null) {
      if (page > 1) {
        return PaginatedPostComments(
          items: const [],
          currentPage: page,
          lastPage: pageData.lastPage,
        );
      }
      return pageData;
    }
    return sampleCommentsPage();
  }

  @override
  Future<PostComment> createComment({
    required int postId,
    required String body,
  }) async {
    createCommentCallCount++;
    createCommentBodies.add(body);
    if (createCommentDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: createCommentDelayMs));
    }
    final failure = createCommentFailureByPostId?[postId];
    if (failure != null) {
      throw failure;
    }
    onCreateComment?.call(postId, body);
    final factory = createdCommentByPostId?[postId];
    if (factory != null) {
      return factory(body);
    }
    return PostComment.fromJson({
      ...sampleCommentJson(
        id: 200 + createCommentCallCount,
        postId: postId,
        body: body,
      ),
    });
  }

  @override
  Future<PostReactionRecord> setReaction({
    required int postId,
    String type = 'like',
  }) async {
    setReactionCallCount++;
    if (reactionDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: reactionDelayMs));
    }
    final failure = setReactionFailureByPostId?[postId];
    if (failure != null) {
      throw failure;
    }
    onSetReaction?.call(postId, type);
    return PostReactionRecord(id: 50, postId: postId, type: type);
  }

  @override
  Future<bool> removeReaction({required int postId}) async {
    removeReactionCallCount++;
    if (reactionDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: reactionDelayMs));
    }
    final failure = removeReactionFailureByPostId?[postId];
    if (failure != null) {
      throw failure;
    }
    onRemoveReaction?.call(postId);
    return true;
  }

  @override
  Future<List<PostCategory>> listPostCategories({
    String audience = 'group',
  }) async {
    listCategoriesCallCount++;
    if (categoriesDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: categoriesDelayMs));
    }
    if (categoriesFailure != null) {
      throw categoriesFailure!;
    }
    return postCategories ??
        [
          PostCategory.fromJson({
            'id': 2,
            'slug': 'aviso-comunitario',
            'name': 'Aviso comunitario',
            'default_audience': 'group',
            'sort_order': 1,
            'is_system': true,
          }),
        ];
  }

  @override
  Future<PostDetail> createCommunityPost({
    required int neighborhoodGroupId,
    required int categoryId,
    required String title,
    required String body,
  }) async {
    createPostCallCount++;
    createPostPayloads.add({
      'neighborhood_group_id': neighborhoodGroupId,
      'category_id': categoryId,
      'title': title,
      'body': body,
    });
    if (createPostDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: createPostDelayMs));
    }
    if (createPostThrowsRaw) {
      throw Exception('red intermitente');
    }
    if (createPostFailure != null) {
      throw createPostFailure!;
    }
    onCreatePost?.call(neighborhoodGroupId, categoryId, title, body);
    final id = 900 + createPostCallCount;
    final existing = detailById?[id];
    if (existing != null &&
        (existing.status == 'draft' || existing.status == 'rejected') &&
        existing.editableRevisionId != null) {
      return existing;
    }
    return draftPostDetail(
      id: id,
      groupId: neighborhoodGroupId,
      categoryId: categoryId,
      title: title,
      body: body,
    );
  }

  @override
  Future<PostAttachmentUploadResult> uploadPostAttachment({
    required int postId,
    required int revisionId,
    required String filePath,
    required String filename,
    required String mimeType,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    uploadCallCount++;
    uploadPayloads.add({
      'postId': postId,
      'revisionId': revisionId,
      'filename': filename,
      'mimeType': mimeType,
    });
    if (uploadDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: uploadDelayMs));
    }
    if (uploadThrowsUncertain) {
      throw Exception('timeout simulado');
    }
    final failure = uploadFailureByPostId?[postId];
    if (failure != null) {
      throw failure;
    }
    final id = 7000 + uploadCallCount;
    return PostAttachmentUploadResult(
      id: id,
      revisionId: revisionId,
      originalDisplayName: filename,
      mimeType: mimeType,
      sizeBytes: 1200,
    );
  }

  @override
  Future<PostDetail> submitPost(int postId) async {
    submitPostCallCount++;
    if (submitPostDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: submitPostDelayMs));
    }
    final failure = submitFailureByPostId?[postId];
    if (failure != null) {
      throw failure;
    }
    onSubmitPost?.call(postId);
    final pending = detailById?[postId];
    if (pending != null) {
      final json = Map<String, dynamic>.from(
        sampleCommunityPostJson(id: postId),
      );
      json['status'] = 'pending';
      return PostDetail.fromJson(json);
    }
    return pendingPostDetail(id: postId);
  }

  @override
  Future<PaginatedFeedPosts> listMyPosts({int page = 1}) async {
    listMyPostsCallCount++;
    if (myPostsDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: myPostsDelayMs));
    }
    if (myPostsFailure != null) {
      throw myPostsFailure!;
    }
    final byPage = myPostsByPage?[page];
    if (byPage != null) {
      return byPage;
    }
    final pageData = myPostsPage;
    if (pageData != null) {
      return pageData;
    }
    return PaginatedFeedPosts(
      items: const [],
      currentPage: page,
      lastPage: page,
    );
  }
}

PostDetail draftPostDetail({
  required int id,
  required int groupId,
  required int categoryId,
  required String title,
  required String body,
}) {
  final json = Map<String, dynamic>.from(sampleCommunityPostJson(id: id));
  json['status'] = 'draft';
  json['neighborhood_group_id'] = groupId;
  json['category_id'] = categoryId;
  json['published_at'] = null;
  json['content'] = null;
  json['attachments'] = [];
  json['working_content'] = {
    'revision_id': id * 10,
    'title': title,
    'body': body,
  };
  return PostDetail.fromJson(json);
}

PostDetail pendingPostDetail({required int id}) {
  final json = Map<String, dynamic>.from(sampleCommunityPostJson(id: id));
  json['status'] = 'pending';
  json['published_at'] = null;
  json['working_content'] = null;
  return PostDetail.fromJson(json);
}

PostDetail detailWithEngagement({
  required int id,
  int reactionsCount = 0,
  String? myReactionType,
}) {
  final json = Map<String, dynamic>.from(sampleCommunityPostJson(id: id));
  json['engagement'] = {
    'comments_count': 0,
    'reactions_count': reactionsCount,
    'my_reaction': myReactionType == null ? null : {'type': myReactionType},
  };
  return PostDetail.fromJson(json);
}
