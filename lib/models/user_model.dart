class AppUser {
  final String id;
  final String name;
  final String email;
  final String pin;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.pin,
    required this.createdAt,
    this.lastLoginAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email.toLowerCase(),
        'pin': pin,
        'createdAt': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as String,
        name: map['name'] as String,
        email: map['email'] as String,
        pin: map['pin'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        lastLoginAt: map['lastLoginAt'] == null
            ? null
            : DateTime.parse(map['lastLoginAt'] as String),
      );

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? pin,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      pin: pin ?? this.pin,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}
