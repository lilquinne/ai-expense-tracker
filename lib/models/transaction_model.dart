import 'split_bill.dart';
// lib/models/transaction_model.dart

enum TransactionType { income, expense }

enum AccountKind { asset, liability, lending, other }

enum AccountSubtype {
  bank,
  eWallet,
  cash,
  investment,
  carLoan,
  mortgage,
  creditCard,
  personalLoan,
  lend,
  borrow,
  other,
}

extension AccountKindExtension on AccountKind {
  String get label {
    switch (this) {
      case AccountKind.asset:
        return 'Assets';
      case AccountKind.liability:
        return 'Liabilities';
      case AccountKind.lending:
        return 'Lend / Borrow';
      case AccountKind.other:
        return 'Others';
    }
  }
}

extension AccountSubtypeExtension on AccountSubtype {
  String get label {
    switch (this) {
      case AccountSubtype.bank:
        return 'Bank';
      case AccountSubtype.eWallet:
        return 'E-wallet';
      case AccountSubtype.cash:
        return 'Cash';
      case AccountSubtype.investment:
        return 'Investment';
      case AccountSubtype.carLoan:
        return 'Car Loan';
      case AccountSubtype.mortgage:
        return 'Mortgage';
      case AccountSubtype.creditCard:
        return 'Credit Card';
      case AccountSubtype.personalLoan:
        return 'Personal Loan';
      case AccountSubtype.lend:
        return 'Lend to';
      case AccountSubtype.borrow:
        return 'Borrow from';
      case AccountSubtype.other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case AccountSubtype.bank:
        return '🏦';
      case AccountSubtype.eWallet:
        return '📱';
      case AccountSubtype.cash:
        return '💵';
      case AccountSubtype.investment:
        return '📈';
      case AccountSubtype.carLoan:
        return '🚗';
      case AccountSubtype.mortgage:
        return '🏠';
      case AccountSubtype.creditCard:
        return '💳';
      case AccountSubtype.personalLoan:
        return '📄';
      case AccountSubtype.lend:
        return '🤝';
      case AccountSubtype.borrow:
        return '↩️';
      case AccountSubtype.other:
        return '◽';
    }
  }
}

enum TransactionCategory {
  // Expense categories
  food,
  transport,
  shopping,
  entertainment,
  health,
  utilities,
  education,
  travel,
  groceries,
  subscriptions,
  rent,
  other,

  // Income categories
  salary,
  freelance,
  investment,
  gift,
  refund,
  incomeOther,
  // Append new values: existing category indexes are stored in the database.
  homeAppliances,
}

extension TransactionCategoryExtension on TransactionCategory {
  bool get isIncomeCategory {
    return [
      TransactionCategory.salary,
      TransactionCategory.freelance,
      TransactionCategory.investment,
      TransactionCategory.gift,
      TransactionCategory.refund,
      TransactionCategory.incomeOther,
    ].contains(this);
  }

  String get label {
    switch (this) {
      case TransactionCategory.homeAppliances:
        return 'Home appliances';
      case TransactionCategory.food:
        return 'Food & Dining';
      case TransactionCategory.transport:
        return 'Transport';
      case TransactionCategory.shopping:
        return 'Shopping';
      case TransactionCategory.entertainment:
        return 'Entertainment';
      case TransactionCategory.health:
        return 'Health';
      case TransactionCategory.utilities:
        return 'Utilities';
      case TransactionCategory.education:
        return 'Education';
      case TransactionCategory.travel:
        return 'Travel';
      case TransactionCategory.groceries:
        return 'Groceries';
      case TransactionCategory.subscriptions:
        return 'Subscriptions';
      case TransactionCategory.rent:
        return 'Rent';
      case TransactionCategory.other:
        return 'Other';
      case TransactionCategory.salary:
        return 'Salary';
      case TransactionCategory.freelance:
        return 'Freelance';
      case TransactionCategory.investment:
        return 'Investment';
      case TransactionCategory.gift:
        return 'Gift';
      case TransactionCategory.refund:
        return 'Refund';
      case TransactionCategory.incomeOther:
        return 'Other Income';
    }
  }

  String get emoji {
    switch (this) {
      case TransactionCategory.homeAppliances:
        return '🏡';
      case TransactionCategory.food:
        return '🍽️';
      case TransactionCategory.transport:
        return '🚗';
      case TransactionCategory.shopping:
        return '🛍️';
      case TransactionCategory.entertainment:
        return '🎬';
      case TransactionCategory.health:
        return '💊';
      case TransactionCategory.utilities:
        return '⚡';
      case TransactionCategory.education:
        return '📚';
      case TransactionCategory.travel:
        return '✈️';
      case TransactionCategory.groceries:
        return '🛒';
      case TransactionCategory.subscriptions:
        return '📱';
      case TransactionCategory.rent:
        return '🏠';
      case TransactionCategory.other:
        return '💳';
      case TransactionCategory.salary:
        return '💼';
      case TransactionCategory.freelance:
        return '💻';
      case TransactionCategory.investment:
        return '📈';
      case TransactionCategory.gift:
        return '🎁';
      case TransactionCategory.refund:
        return '↩️';
      case TransactionCategory.incomeOther:
        return '💰';
    }
  }

  int get colorValue {
    switch (this) {
      case TransactionCategory.homeAppliances:
        return 0xFF45B7A0;
      case TransactionCategory.food:
        return 0xFFFF6B6B;
      case TransactionCategory.transport:
        return 0xFF4ECDC4;
      case TransactionCategory.shopping:
        return 0xFFFFBE0B;
      case TransactionCategory.entertainment:
        return 0xFF9B5DE5;
      case TransactionCategory.health:
        return 0xFF00BBF9;
      case TransactionCategory.utilities:
        return 0xFFFF9F1C;
      case TransactionCategory.education:
        return 0xFF2EC4B6;
      case TransactionCategory.travel:
        return 0xFFFF006E;
      case TransactionCategory.groceries:
        return 0xFF8AC926;
      case TransactionCategory.subscriptions:
        return 0xFF6A4C93;
      case TransactionCategory.rent:
        return 0xFF1982C4;
      case TransactionCategory.other:
        return 0xFF6D6875;
      case TransactionCategory.salary:
        return 0xFF06D6A0;
      case TransactionCategory.freelance:
        return 0xFF118AB2;
      case TransactionCategory.investment:
        return 0xFF073B4C;
      case TransactionCategory.gift:
        return 0xFFEF476F;
      case TransactionCategory.refund:
        return 0xFF26A96C;
      case TransactionCategory.incomeOther:
        return 0xFF588157;
    }
  }
}

class TransactionModel {
  final String id;
  final String title;
  final double amount;
  final TransactionType type;
  final TransactionCategory category;
  final String categoryId;
  final String accountId;
  final DateTime date;
  final String? note;
  final String? receiptImagePath;
  final bool isRecurring;
  final String? recurringFrequency;
  final String? splitData;
  SplitBill? get split =>
      splitData == null ? null : SplitBill.decode(splitData!);

  TransactionModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    String? categoryId,
    String? accountId,
    required this.date,
    this.note,
    this.receiptImagePath,
    this.isRecurring = false,
    this.recurringFrequency,
    this.splitData,
  })  : categoryId = categoryId ?? category.name,
        accountId = accountId ?? AppAccount.defaultId;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'type': type.index,
      'category': category.index,
      'categoryId': categoryId,
      'accountId': accountId,
      'date': date.toIso8601String(),
      'note': note,
      'receiptImagePath': receiptImagePath,
      'isRecurring': isRecurring ? 1 : 0,
      'recurringFrequency': recurringFrequency,
      'splitData': splitData,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as String,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.values[(map['type'] as num).toInt()],
      category: TransactionCategory.values[(map['category'] as num).toInt()],
      categoryId: map['categoryId'] as String?,
      accountId: map['accountId'] as String?,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String?,
      receiptImagePath: map['receiptImagePath'] as String?,
      isRecurring: (map['isRecurring'] as num? ?? 0).toInt() == 1,
      recurringFrequency: map['recurringFrequency'] as String?,
      splitData: map['splitData'] as String?,
    );
  }

  TransactionModel copyWith({
    String? id,
    String? title,
    double? amount,
    TransactionType? type,
    TransactionCategory? category,
    String? categoryId,
    String? accountId,
    DateTime? date,
    String? note,
    String? receiptImagePath,
    bool? isRecurring,
    String? recurringFrequency,
    String? splitData,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      date: date ?? this.date,
      note: note ?? this.note,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringFrequency: recurringFrequency ?? this.recurringFrequency,
      splitData: splitData ?? this.splitData,
    );
  }
}

class AppAccount {
  static const defaultId = 'cash';

  final String id;
  final String name;
  final AccountKind kind;
  final AccountSubtype subtype;
  final double openingBalance;
  final double currentBalance;
  final String icon;
  final int colorValue;
  final bool isDefault;
  final bool includeInNetWorth;
  final bool includeInBalance;
  final String? counterpartyName;
  final String? linkedAccountId;

  const AppAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.subtype,
    required this.openingBalance,
    required this.currentBalance,
    required this.icon,
    required this.colorValue,
    this.isDefault = false,
    this.includeInNetWorth = true,
    this.includeInBalance = true,
    this.counterpartyName,
    this.linkedAccountId,
  });

  bool get affectsNetWorth => includeInNetWorth && kind != AccountKind.other;
  bool get isLiability => kind == AccountKind.liability;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.index,
        'subtype': subtype.index,
        'openingBalance': openingBalance,
        'currentBalance': currentBalance,
        'icon': icon,
        'colorValue': colorValue,
        'isDefault': isDefault ? 1 : 0,
        'includeInNetWorth': includeInNetWorth ? 1 : 0,
        'includeInBalance': includeInBalance ? 1 : 0,
        'counterpartyName': counterpartyName,
        'linkedAccountId': linkedAccountId,
      };

  factory AppAccount.fromMap(Map<String, dynamic> map) => AppAccount(
        id: map['id'] as String,
        name: map['name'] as String,
        kind: AccountKind.values[(map['kind'] as num).toInt()],
        subtype: AccountSubtype.values[(map['subtype'] as num).toInt()],
        openingBalance: (map['openingBalance'] as num).toDouble(),
        currentBalance: (map['currentBalance'] as num).toDouble(),
        icon: map['icon'] as String,
        colorValue: (map['colorValue'] as num).toInt(),
        isDefault: (map['isDefault'] as num? ?? 0).toInt() == 1,
        includeInNetWorth: (map['includeInNetWorth'] as num? ?? 1).toInt() == 1,
        includeInBalance: (map['includeInBalance'] as num? ?? 1).toInt() == 1,
        counterpartyName: map['counterpartyName'] as String?,
        linkedAccountId: map['linkedAccountId'] as String?,
      );

  AppAccount copyWith({
    String? id,
    String? name,
    AccountKind? kind,
    AccountSubtype? subtype,
    double? openingBalance,
    double? currentBalance,
    String? icon,
    int? colorValue,
    bool? isDefault,
    bool? includeInNetWorth,
    bool? includeInBalance,
    String? counterpartyName,
    String? linkedAccountId,
  }) {
    return AppAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      subtype: subtype ?? this.subtype,
      openingBalance: openingBalance ?? this.openingBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      icon: icon ?? this.icon,
      colorValue: colorValue ?? this.colorValue,
      isDefault: isDefault ?? this.isDefault,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      includeInBalance: includeInBalance ?? this.includeInBalance,
      counterpartyName: counterpartyName ?? this.counterpartyName,
      linkedAccountId: linkedAccountId ?? this.linkedAccountId,
    );
  }

  static List<AppAccount> get defaults => const [
        AppAccount(
          id: defaultId,
          name: 'Cash',
          kind: AccountKind.asset,
          subtype: AccountSubtype.cash,
          openingBalance: 0,
          currentBalance: 0,
          icon: '💵',
          colorValue: 0xFF06D6A0,
          isDefault: true,
        ),
      ];
}

class BudgetModel {
  final String id;
  final TransactionCategory category;
  final double limit;
  final DateTime month;

  BudgetModel({
    required this.id,
    required this.category,
    required this.limit,
    required this.month,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category.index,
        'limit': limit,
        'month': month.toIso8601String(),
      };

  factory BudgetModel.fromMap(Map<String, dynamic> map) => BudgetModel(
        id: map['id'] as String,
        category: TransactionCategory.values[(map['category'] as num).toInt()],
        limit: (map['limit'] as num).toDouble(),
        month: DateTime.parse(map['month'] as String),
      );
}

class AppCategory {
  final String id;
  final String name;
  final TransactionType type;
  final TransactionCategory parentCategory;
  final String icon;
  final int colorValue;
  final String? parentId;
  final bool isDefault;

  const AppCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.parentCategory,
    required this.icon,
    required this.colorValue,
    this.parentId,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type.index,
        'parentCategory': parentCategory.index,
        'icon': icon,
        'colorValue': colorValue,
        'parentId': parentId,
        'isDefault': isDefault ? 1 : 0,
      };

  factory AppCategory.fromMap(Map<String, dynamic> map) => AppCategory(
        id: map['id'] as String,
        name: map['name'] as String,
        type: TransactionType.values[(map['type'] as num).toInt()],
        parentCategory:
            TransactionCategory.values[(map['parentCategory'] as num).toInt()],
        icon: map['icon'] as String,
        colorValue: (map['colorValue'] as num).toInt(),
        parentId: map['parentId'] as String?,
        isDefault: (map['isDefault'] as num? ?? 0).toInt() == 1,
      );

  static List<AppCategory> get defaults => [
        for (final category in TransactionCategory.values)
          AppCategory(
            id: category.name,
            name: category.label,
            type: category.isIncomeCategory
                ? TransactionType.income
                : TransactionType.expense,
            parentCategory: category,
            icon: category.emoji,
            colorValue: category.colorValue,
            isDefault: true,
          ),
        for (final item in const {
          'breakfast': 'Breakfast',
          'lunch': 'Lunch',
          'dinner': 'Dinner',
          'snacks': 'Snacks'
        }.entries)
          AppCategory(
              id: 'food_${item.key}',
              name: item.value,
              type: TransactionType.expense,
              parentCategory: TransactionCategory.food,
              parentId: 'food',
              icon: item.key == 'breakfast'
                  ? '🍳'
                  : item.key == 'snacks'
                      ? '🍿'
                      : '🍽️',
              colorValue: TransactionCategory.food.colorValue,
              isDefault: true),
        for (final group in const <TransactionCategory, List<String>>{
          TransactionCategory.transport: [
            'Fuel',
            'Parking',
            'Tolls',
            'Public transport',
            'Taxi & ride hailing',
            'Vehicle maintenance'
          ],
          TransactionCategory.groceries: [
            'Fresh produce',
            'Meat & seafood',
            'Household supplies',
            'Personal care'
          ],
          TransactionCategory.shopping: [
            'Clothing',
            'Shoes',
            'Electronics',
            'Beauty',
            'Accessories'
          ],
          TransactionCategory.entertainment: [
            'Movies',
            'Gaming',
            'Music',
            'Sports & fitness',
            'Hobbies'
          ],
          TransactionCategory.health: [
            'Clinic',
            'Dental',
            'Pharmacy',
            'Health insurance'
          ],
          TransactionCategory.utilities: [
            'Electricity',
            'Water',
            'Internet',
            'Mobile plan'
          ],
          TransactionCategory.education: [
            'Tuition',
            'Books',
            'Courses',
            'School supplies'
          ],
          TransactionCategory.travel: [
            'Flights',
            'Hotels',
            'Activities',
            'Travel insurance'
          ],
          TransactionCategory.subscriptions: [
            'Streaming',
            'Software',
            'Memberships'
          ],
          TransactionCategory.rent: ['Home rent', 'Office rent'],
          TransactionCategory.homeAppliances: [
            'Furniture',
            'Kitchen appliances',
            'Home repairs'
          ],
          TransactionCategory.other: [
            'Pets',
            'Donations',
            'Childcare',
            'Taxes',
            'Fees'
          ],
          TransactionCategory.salary: ['Monthly salary', 'Bonus', 'Overtime'],
          TransactionCategory.freelance: ['Client work', 'Side business'],
          TransactionCategory.investment: [
            'Dividends',
            'Interest',
            'Capital gains'
          ],
        }.entries)
          for (final name in group.value)
            AppCategory(
              id: '${group.key.name}_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
              name: name,
              type: group.key.isIncomeCategory
                  ? TransactionType.income
                  : TransactionType.expense,
              parentCategory: group.key,
              parentId: group.key.name,
              icon: group.key.emoji,
              colorValue: group.key.colorValue,
              isDefault: true,
            ),
      ];
}
