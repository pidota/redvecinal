import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';

import 'neighborhood_test_support.dart';

void main() {
  test('append evita duplicados por id', () {
    final first = PaginatedNeighborhoodGroups(
      items: [
        sampleNeighborhoodGroup(id: 1),
        sampleNeighborhoodGroup(id: 2, name: 'Junta Norte'),
      ],
      currentPage: 1,
      lastPage: 2,
    );
    final second = PaginatedNeighborhoodGroups(
      items: [
        sampleNeighborhoodGroup(id: 2, name: 'Junta Norte'),
        sampleNeighborhoodGroup(id: 3, name: 'Junta Sur'),
      ],
      currentPage: 2,
      lastPage: 2,
    );

    final merged = first.append(second);
    expect(merged.items.map((g) => g.id), [1, 2, 3]);
    expect(merged.currentPage, 2);
    expect(merged.hasMore, isFalse);
  });
}
