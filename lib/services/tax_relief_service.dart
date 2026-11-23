import '../models/transaction_model.dart';

class TaxReliefMatch {
  const TaxReliefMatch(this.transaction, this.group, this.reason);
  final TransactionModel transaction;
  final String group, reason;
}

/// Local filing hints only. No claim amounts, eligibility or tax savings are
/// inferred from a transaction category or an entire mixed receipt.
class TaxReliefService {
  static const verifiedReferenceYear = 2025;
  static const referenceUrl =
      'https://www.hasil.gov.my/media/muob0jyz/tax-relief-ya-2025.pdf';
  static List<TaxReliefMatch> find(Iterable<TransactionModel> rows, int year,
      {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final output = <TaxReliefMatch>[];
    for (final t in rows) {
      if (t.type != TransactionType.expense ||
          t.date.year != year ||
          t.date.isAfter(now) ||
          t.amount <= 0 ||
          !t.amount.isFinite) continue;
      final text = '${t.title} ${t.note ?? ''}'.toLowerCase();
      bool has(String pattern) =>
          RegExp(pattern, caseSensitive: false).hasMatch(text);
      void add(String group, String reason) =>
          output.add(TaxReliefMatch(t, group, reason));
      if (has(
          r'\b(gym membership|sports training|badminton|tennis racket|sports equipment|swimming lesson|sports facility|court rental|sports competition)\b')) {
        add('Sports',
            'Sports equipment, facility or training wording. Check the sport, provider and eligible receipt lines.');
      }
      if (has(
          r'\b(books?|ebooks?|reading materials?|newspapers?|magazines?)\b')) {
        add('Reading materials',
            'Reading-material wording. Check the publication and personal-use conditions.');
      }
      if (has(r'\b(laptop|smartphone|tablet|personal computer|internet subscription|broadband|fibre internet)\b') &&
          !has(r'\b(repair|accessories|case|screen protector)\b') &&
          t.category != TransactionCategory.health) {
        add('Devices & internet',
            'Device or internet wording. Check purchase type, bill holder and personal use; accessories are not automatically included.');
      }
      if (has(
          r'\b(dental examination|dental check|vaccination|health screening|medical check[- ]?up|mental health consultation|fertility treatment)\b')) {
        add('Medical checks & treatment',
            'Specific medical-service wording. Check the eligible treatment, provider, beneficiary and yearly conditions.');
      }
      if (has(
          r'\b(tuition fees?|university fees?|education fees?|skills course|self[- ]development course)\b')) {
        add('Education & courses',
            'Education-fee wording. Check the student, course level and recognised provider; ordinary school spending is not automatically eligible.');
      }
      if (has(
          r'\b(medical insurance|education insurance|life insurance|private retirement scheme|prs contribution|socso contribution)\b')) {
        add('Insurance & contributions',
            'Policy or contribution wording. Use the annual provider statement to check the qualifying amount.');
      }
      if (has(r'\b(taska|tadika|kindergarten fees?|registered childcare)\b')) {
        add('Childcare',
            'Childcare wording. Check the child’s age, centre registration and which parent claims.');
      }
    }
    output.sort((a, b) {
      final group = a.group.compareTo(b.group);
      return group != 0
          ? group
          : b.transaction.date.compareTo(a.transaction.date);
    });
    return output;
  }
}
