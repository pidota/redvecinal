import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/data/models/municipality_membership.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/neighborhood_group.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

NeighborhoodGroup sampleNeighborhoodGroup({
  int id = 1,
  String name = 'Junta Centro',
  String status = 'active',
  MunicipalitySummary? municipality,
  String? description,
  String? address,
}) {
  return NeighborhoodGroup(
    id: id,
    municipalityId: municipality?.id ?? 10,
    name: name,
    slug: 'junta-centro',
    status: status,
    description: description ?? 'Descripción breve',
    address: address,
    municipality: municipality ??
        const MunicipalitySummary(id: 10, name: 'Chépica', slug: 'chepica'),
  );
}

Map<String, dynamic> sampleGroupJson({
  int id = 1,
  String status = 'active',
  bool includeMunicipality = true,
  String? description,
}) {
  return {
    'id': id,
    'municipality_id': 10,
    'name': 'Junta Centro',
    'slug': 'junta-centro',
    'description': description ?? 'Descripción breve',
    'address': null,
    'status': status,
    if (includeMunicipality)
      'municipality': {
        'id': 10,
        'name': 'Chépica',
        'slug': 'chepica',
      },
  };
}

class FakeNeighborhoodGateway implements NeighborhoodGateway {
  FakeNeighborhoodGateway({
    this.groups = const [],
    this.failure,
    this.callCount = 0,
    PaginatedNeighborhoodGroups? explorePage,
    this.exploreFailure,
    this.exploreFailurePage,
    this.exploreListDelayMs = 0,
    this.pagesByNumber,
    this.detailFailure,
    this.detailDelayMs = 0,
    Map<int, NeighborhoodGroup>? details,
  })  : explorePage = explorePage ??
            PaginatedNeighborhoodGroups(
              items: groups,
              currentPage: 1,
              lastPage: 1,
            ),
        details = details ?? {for (final g in groups) g.id: g};

  List<NeighborhoodGroup> groups;
  Object? failure;
  int callCount;
  PaginatedNeighborhoodGroups explorePage;
  Object? exploreFailure;
  int? exploreFailurePage;
  int exploreListDelayMs;
  Map<int, PaginatedNeighborhoodGroups>? pagesByNumber;
  Object? detailFailure;
  int detailDelayMs;
  final Map<int, NeighborhoodGroup> details;

  @override
  Future<List<NeighborhoodGroup>> myGroups() async {
    callCount++;
    if (failure != null) {
      throw failure!;
    }
    return groups;
  }

  @override
  Future<PaginatedNeighborhoodGroups> listGroups({int page = 1}) async {
    callCount++;
    if (exploreListDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: exploreListDelayMs));
    }
    if (exploreFailure != null && (exploreFailurePage == null || exploreFailurePage == page)) {
      throw exploreFailure!;
    }
    final pages = pagesByNumber;
    if (pages != null) {
      return pages[page] ??
          PaginatedNeighborhoodGroups(
            items: const [],
            currentPage: page,
            lastPage: explorePage.lastPage,
          );
    }
    if (page > 1) {
      return PaginatedNeighborhoodGroups(items: const [], currentPage: page, lastPage: explorePage.lastPage);
    }
    return explorePage;
  }

  @override
  Future<NeighborhoodGroup> groupDetail(int groupId) async {
    callCount++;
    if (detailDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: detailDelayMs));
    }
    if (detailFailure != null) {
      throw detailFailure!;
    }
    final match = details[groupId];
    if (match == null) {
      throw const ApiNotFoundFailure();
    }
    return match;
  }
}
