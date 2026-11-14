class PostCategory {
  const PostCategory({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    required this.defaultAudience,
    required this.sortOrder,
    required this.isSystem,
  });

  factory PostCategory.fromJson(Map<String, dynamic> json) {
    return PostCategory(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      defaultAudience: json['default_audience'] as String? ?? 'group',
      sortOrder: json['sort_order'] as int? ?? 0,
      isSystem: json['is_system'] as bool? ?? false,
    );
  }

  final int id;
  final String slug;
  final String name;
  final String? description;
  final String defaultAudience;
  final int sortOrder;
  final bool isSystem;
}
