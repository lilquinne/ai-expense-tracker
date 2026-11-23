class TreasureJar {
  const TreasureJar(
      {required this.id,
      required this.name,
      required this.accountId,
      required this.targetCents,
      required this.savedCents,
      this.deadline});
  final String id, name, accountId;
  final int targetCents, savedCents;
  final DateTime? deadline;
  double get progress => (savedCents / targetCents).clamp(0.0, 1.0);
  factory TreasureJar.fromMap(Map<String, dynamic> row) => TreasureJar(
      id: row['id'] as String,
      name: row['name'] as String,
      accountId: row['accountId'] as String,
      targetCents: row['targetCents'] as int,
      savedCents: row['savedCents'] as int,
      deadline: row['deadline'] == null
          ? null
          : DateTime.parse(row['deadline'] as String));
}
