import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Branch extends Equatable {
  final String id;
  final String name;
  final String? code;
  final String? address;
  final bool isActive;
  final DateTime createdAt;

  const Branch({
    required this.id,
    required this.name,
    this.code,
    this.address,
    this.isActive = true,
    required this.createdAt,
  });

  factory Branch.create({
    required String name,
    String? code,
    String? address,
  }) {
    return Branch(
      id: const Uuid().v4(),
      name: name,
      code: code,
      address: address,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'address': address,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Branch.fromMap(Map<String, dynamic> map) => Branch(
        id: map['id'] as String,
        name: map['name'] as String,
        code: map['code'] as String?,
        address: map['address'] as String?,
        isActive: map['isActive'] as bool? ?? true,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  @override
  List<Object?> get props => [id, name];
}