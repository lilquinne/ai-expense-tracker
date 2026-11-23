import 'dart:convert';

class SplitPerson {
  const SplitPerson(this.id, this.name, this.sen);
  final String id, name;
  final int sen;
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'sen': sen};
}

class SplitBill {
  const SplitBill(this.totalSen, this.payer, this.people);
  final int totalSen, payer;
  final List<SplitPerson> people;
  int get ownSen => people.first.sen;
  int get cashSen => payer == 0 ? totalSen : 0;
  void validate() {
    if (totalSen <= 0 ||
        totalSen > 10000000000 ||
        people.length < 2 ||
        payer < 0 ||
        payer >= people.length ||
        people.map((p) => p.id).toSet().length != people.length ||
        people.any((p) => p.sen < 0 || p.name.trim().isEmpty || p.id.isEmpty) ||
        people.fold<int>(0, (s, p) => s + p.sen) != totalSen) {
      throw ArgumentError('Participant amounts must equal the bill total.');
    }
  }

  String encode() => jsonEncode({
        'totalSen': totalSen,
        'payer': payer,
        'people': people.map((p) => p.toMap()).toList()
      });
  factory SplitBill.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return SplitBill(
        data['totalSen'] as int,
        data['payer'] as int,
        (data['people'] as List)
            .map((p) => SplitPerson(
                p['id'] as String, p['name'] as String, p['sen'] as int))
            .toList());
  }
  static List<int> evenly(int total, int count) {
    if (total <= 0 || count < 2)
      throw ArgumentError('Enter a bill and at least two people.');
    return List.generate(
        count, (i) => total ~/ count + (i < total % count ? 1 : 0));
  }
}
