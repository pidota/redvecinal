import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
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

class FakePostGateway implements PostGateway {
  FakePostGateway({
    PaginatedFeedPosts? feedPage,
    this.feedFailure,
    this.feedFailurePage,
    this.feedDelayMs = 0,
    this.pagesByNumber,
    this.callCount = 0,
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
}
