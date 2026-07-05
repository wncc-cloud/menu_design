class SectionModel {
  final String id;
  final String name;
  final String icon;
  final int sortOrder;

  const SectionModel({
    required this.id,
    required this.name,
    this.icon = '',
    this.sortOrder = 0,
  });

  factory SectionModel.fromJson(Map<String, dynamic> json) {
    return SectionModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'sortOrder': sortOrder,
      };
}
