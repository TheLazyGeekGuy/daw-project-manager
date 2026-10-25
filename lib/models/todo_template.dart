import 'package:hive_ce/hive.dart';
import '../utils/sync_time.dart';

part 'todo_template.g.dart';

@HiveType(typeId: 9)
class TodoTemplate extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final List<String> items;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final DateTime updatedAt;

  TodoTemplate({  
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  TodoTemplate copyWith({
    String? id,
    String? name,
    List<String>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TodoTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items,
      'createdAt': syncInstant(createdAt),
      'updatedAt': syncInstant(updatedAt),
    };
  }

  factory TodoTemplate.fromJson(Map<String, dynamic> json) {
    return TodoTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      items: (json['items'] as List<dynamic>).cast<String>(),
      createdAt: parseSyncInstant(json['createdAt'] as String),
      updatedAt: parseSyncInstant(json['updatedAt'] as String),
    );
  }
}
