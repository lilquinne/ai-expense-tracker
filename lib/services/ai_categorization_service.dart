// lib/services/ai_categorization_service.dart
// AI-powered categorization using keyword matching + ML-like scoring

import 'dart:math' as math;

import '../models/transaction_model.dart';
import 'category_learning_service.dart';
import 'receipt_parser.dart';
import 'receipt_item_cleanup.dart';

class AiCategorizationService {
  static const _merchants = <String, TransactionCategory>{
    'bataras': TransactionCategory.groceries,
    'jaya grocer': TransactionCategory.groceries,
    'jaya grocers': TransactionCategory.groceries,
    'village grocer': TransactionCategory.groceries,
    '99 speedmart': TransactionCategory.groceries,
    'lotuss': TransactionCategory.groceries,
    'ninso': TransactionCategory.shopping,
    'mr diy': TransactionCategory.shopping,
    'mrdiy': TransactionCategory.shopping,
    'kkv': TransactionCategory.shopping,
    'watson': TransactionCategory.health,
    'watsons': TransactionCategory.health,
    'guardian': TransactionCategory.health,
    'kfc': TransactionCategory.food,
    'mcdonalds': TransactionCategory.food,
    'zus coffee': TransactionCategory.food,
    'starbucks': TransactionCategory.food,
  };

  static TransactionCategory? merchantCategory(String text) {
    final normalized = _normalize(text);
    for (final entry in _merchants.entries) {
      if (_matches(normalized, entry.key)) return entry.value;
    }
    return null;
  }

  static bool _matches(String text, String keyword) =>
      RegExp('(^| )${RegExp.escape(_normalize(keyword))}( |\$)').hasMatch(text);

  static CategoryResult _known(TransactionCategory category,
          [double confidence = .9]) =>
      CategoryResult(
          category: category, confidence: confidence, suggestions: [category]);
  // Keyword maps for intelligent categorization
  static const Map<TransactionCategory, List<String>> _categoryKeywords = {
    TransactionCategory.food: [
      'restaurant',
      'cafe',
      'coffee',
      'pizza',
      'burger',
      'mcdonalds',
      'kfc',
      'subway',
      'sushi',
      'dinner',
      'lunch',
      'breakfast',
      'bistro',
      'kitchen',
      'grill',
      'food',
      'eat',
      'meal',
      'snack',
      'bakery',
      'noodle',
      'rice',
      'starbucks',
      'mamak',
      'kopitiam',
      'hawker',
      'makan',
      'nasi',
      'mee',
      'mi',
      'bihun',
      'teh',
      'kopi',
      'ayam goreng',
      'roti canai',
      'laksa',
      'satay',
      'ramen',
      'donut',
      'cake',
      'pastry',
      'chicken rice',
      'warung',
      'restoran',
      'burger king',
      'domino',
      'pizza hut',
      'secret recipe',
      'oldtown',
      'zus coffee',
      'coffee bean',
      'familymart'
    ],
    TransactionCategory.transport: [
      'grab',
      'uber',
      'taxi',
      'bus',
      'train',
      'mrt',
      'lrt',
      'petrol',
      'fuel',
      'parking',
      'toll',
      'commute',
      'transport',
      'car',
      'bike',
      'flight',
      'airasia',
      'malindo',
      'malaysia airlines',
      'rapidkl',
      'gas station',
      'shell',
      'petronas',
      'petron',
      'bhp',
      'caltex',
      'ron95',
      'ron97',
      'diesel',
      'touch n go',
      'tng',
      'myrapid',
      'ktm',
      'ets',
      'parking fee'
    ],
    TransactionCategory.shopping: [
      'amazon',
      'lazada',
      'shopee',
      'zara',
      'h&m',
      'uniqlo',
      'shopping',
      'mall',
      'store',
      'shop',
      'purchase',
      'buy',
      'clothes',
      'fashion',
      'electronics',
      'gadget',
      'online',
      'retail',
      'aeon',
      'parkson',
      'mr diy',
      'daiso',
      'padini',
      'cotton on',
      'nike',
      'adidas',
      'puma',
      'watsons',
      'guardian',
      'bookxcess',
      'popular',
      'senheng',
      'senq',
      'courts',
      'harvey norman',
      'ikea',
      'satin',
      'ribbon',
      'craft',
      'gift wrap',
      'wrapping',
      'card',
      'sheet card',
      'writedown',
      'write down',
      'party',
      'stationery'
    ],
    TransactionCategory.groceries: [
      'grocery',
      'supermarket',
      'tesco',
      'giant',
      'cold storage',
      'mydin',
      'village grocer',
      'jaya grocer',
      'market',
      'vegetables',
      'fruits',
      'milk',
      'bread',
      'eggs',
      'chicken',
      'fish',
      'beef',
      'household',
      'cleaning',
      'detergent',
      'lotus',
      'lotuss',
      'lotus\'s',
      'nsK',
      'econsave',
      '99 speedmart',
      'speedmart',
      'kk mart',
      '711',
      '7-eleven',
      'hero market',
      'ben independent grocer',
      'big',
      'mercato',
      'cs fresh',
      'fresh',
      'sayur',
      'buah',
      'ayam',
      'daging',
      'telur',
      'susu',
      'roti',
      'beras',
      'minyak',
      'gula',
      'garam',
      'tepung',
      'ikan',
      'udang',
      'sotong',
      'yogurt',
      'cheese',
      'butter',
      'cereal',
      'oats',
      'milo',
      'nescafe',
      'maggi',
      'indomie',
      'biskut',
      'tisu',
      'toilet roll',
      'sabun',
      'shampoo',
      'toothpaste',
      'diaper',
      'lampin',
      'wet tissue',
      'wet tissues',
      'tissues',
      'tissue',
      'wipes',
      'wet wipes',
      'beras',
      'raw chicken',
      'fresh chicken',
      'rice',
      'bataras',
      'jaya grocer'
    ],
    TransactionCategory.entertainment: [
      'netflix',
      'spotify',
      'cinema',
      'movie',
      'youtube',
      'disney',
      'hbo',
      'game',
      'entertainment',
      'concert',
      'ticket',
      'event',
      'karaoke',
      'bowling',
      'escape room',
      'theme park',
      'tgv',
      'gsc',
      'viu',
      'steam',
      'playstation',
      'xbox',
      'nintendo',
      'cinema ticket',
      'popcorn'
    ],
    TransactionCategory.health: [
      'pharmacy',
      'hospital',
      'clinic',
      'doctor',
      'medicine',
      'health',
      'gym',
      'fitness',
      'dental',
      'optician',
      'medical',
      'watson',
      'guardian',
      'supplement',
      'vitamin',
      'insurance',
      'lab test',
      'panadol',
      'ubat',
      'farmasi',
      'pharma',
      'caring',
      'alpro',
      'bp lab',
      'glove',
      'mask',
      'toothbrush'
    ],
    TransactionCategory.utilities: [
      'tnb',
      'electricity',
      'water',
      'syabas',
      'indah water',
      'internet',
      'wifi',
      'broadband',
      'unifi',
      'maxis',
      'celcom',
      'digi',
      'telco',
      'bill',
      'utilities',
      'gas',
      'postpaid',
      'prepaid',
      'phone bill',
      'astro',
      'umobile',
      'u mobile',
      'yes',
      'webe',
      'air selangor',
      'saj',
      'sesb'
    ],
    TransactionCategory.education: [
      'school',
      'university',
      'college',
      'tuition',
      'course',
      'class',
      'education',
      'book',
      'textbook',
      'stationery',
      'workshop',
      'training',
      'udemy',
      'coursera',
      'study',
      'exam',
      'certification',
      'pen',
      'pencil',
      'notebook',
      'exercise book',
      'yuran',
      'fee sekolah'
    ],
    TransactionCategory.travel: [
      'hotel',
      'airbnb',
      'agoda',
      'booking',
      'flight',
      'vacation',
      'holiday',
      'travel',
      'trip',
      'tour',
      'resort',
      'visa',
      'passport',
      'luggage',
      'klook',
      'expedia',
      'trivago',
      'traveloka',
      'airline',
      'homestay'
    ],
    TransactionCategory.subscriptions: [
      'netflix',
      'spotify',
      'apple',
      'google',
      'microsoft',
      'adobe',
      'subscription',
      'monthly',
      'annual',
      'membership',
      'premium',
      'prime',
      'icloud',
      'dropbox',
      'notion',
      'canva',
      'chatgpt',
      'openai',
      'github',
      'domain',
      'hosting'
    ],
    TransactionCategory.rent: [
      'rent',
      'rental',
      'landlord',
      'property',
      'apartment',
      'condo',
      'house',
      'deposit',
      'maintenance',
      'strata',
      'management fee'
    ],
    // Income categories
    TransactionCategory.salary: [
      'salary',
      'payroll',
      'wages',
      'pay',
      'income',
      'epf',
      'pcb',
      'bonus',
      'allowance',
      'gaji'
    ],
    TransactionCategory.freelance: [
      'freelance',
      'project',
      'client',
      'invoice',
      'consulting',
      'service',
      'contract',
      'gig',
      'upwork',
      'fiverr'
    ],
    TransactionCategory.investment: [
      'dividend',
      'interest',
      'investment',
      'stock',
      'amanah saham',
      'unit trust',
      'property income',
      'rental income',
      'return',
      'profit',
      'capital gain',
      'asnb',
      'bursa'
    ],
  };

  static const List<_TrainingSample> _mlTrainingSamples = [
    // Malaysian receipt vocabulary, including household items in mixed shops.
    _TrainingSample('bataras supermarket ayam beras wet tissue',
        TransactionCategory.groceries),
    _TrainingSample('jaya grocer fresh chicken rice wet wipes',
        TransactionCategory.groceries),
    _TrainingSample('tisu basah wet tissue household cleaning',
        TransactionCategory.groceries),
    _TrainingSample(
        'ninso mr diy kkv ribbon storage box', TransactionCategory.shopping),
    _TrainingSample('watson watsons guardian panadol medicine vitamin',
        TransactionCategory.health),
    _TrainingSample('guardian watsons lipstick mascara cosmetics',
        TransactionCategory.shopping),
    // Food & dining
    _TrainingSample(
        'nasi lemak teh ais restoran mamak', TransactionCategory.food),
    _TrainingSample('kfc chicken burger fries pepsi', TransactionCategory.food),
    _TrainingSample('mcdonalds burger nugget coffee', TransactionCategory.food),
    _TrainingSample('pizza hut domino pizza pasta', TransactionCategory.food),
    _TrainingSample('kopitiam kopi roti bakar mee', TransactionCategory.food),
    _TrainingSample('starbucks latte cake pastry', TransactionCategory.food),
    _TrainingSample('familymart oden coffee snack', TransactionCategory.food),
    _TrainingSample('sushi ramen bento restaurant', TransactionCategory.food),

    // Groceries
    _TrainingSample(
        'susu roti telur ayam beras', TransactionCategory.groceries),
    _TrainingSample(
        'milk bread egg chicken rice', TransactionCategory.groceries),
    _TrainingSample(
        'sayur buah ikan daging pasar', TransactionCategory.groceries),
    _TrainingSample('lotus supermarket grocery detergent tissue complex drink',
        TransactionCategory.groceries),
    _TrainingSample(
        '99 speedmart maggi milo biscuit', TransactionCategory.groceries),
    _TrainingSample('mydin minyak gula tepung susu kubis meat apple',
        TransactionCategory.groceries),
    _TrainingSample(
        'jaya grocer yogurt cheese butter oats hot sweet spicy sour',
        TransactionCategory.groceries),
    _TrainingSample('econsave vegetable fruit household cleaning',
        TransactionCategory.groceries),

    // Transport
    _TrainingSample('grab ride taxi fare toll', TransactionCategory.transport),
    _TrainingSample(
        'petronas ron95 petrol fuel', TransactionCategory.transport),
    _TrainingSample(
        'shell diesel parking touch n go', TransactionCategory.transport),
    _TrainingSample('rapidkl mrt lrt bus train', TransactionCategory.transport),
    _TrainingSample(
        'airasia flight ticket airport', TransactionCategory.transport),
    _TrainingSample(
        'parking fee toll tng reload', TransactionCategory.transport),

    // Shopping
    _TrainingSample('shopee lazada online shopping watson guardian mall',
        TransactionCategory.shopping),
    _TrainingSample(
        'uniqlo zara clothes fashion', TransactionCategory.shopping),
    _TrainingSample(
        'mr diy tools household item', TransactionCategory.shopping),
    _TrainingSample(
        'senheng phone laptop electronics', TransactionCategory.shopping),
    _TrainingSample('ikea furniture home decor', TransactionCategory.shopping),
    _TrainingSample('nike adidas shoes bag', TransactionCategory.shopping),
    _TrainingSample(
        'satin ribbon craft gift wrap', TransactionCategory.shopping),
    _TrainingSample(
        'writedown sheet card stationery', TransactionCategory.shopping),

    // Entertainment
    _TrainingSample(
        'gsc tgv cinema movie popcorn', TransactionCategory.entertainment),
    _TrainingSample(
        'concert ticket karaoke bowling', TransactionCategory.entertainment),
    _TrainingSample(
        'steam game playstation xbox', TransactionCategory.entertainment),
    _TrainingSample(
        'theme park escape room event', TransactionCategory.entertainment),

    // Health
    _TrainingSample(
        'panadol vitamin pharmacy medicine', TransactionCategory.health),
    _TrainingSample(
        'clinic doctor dental hospital', TransactionCategory.health),
    _TrainingSample('supplement mask', TransactionCategory.health),
    _TrainingSample('alpro caring farmasi ubat', TransactionCategory.health),
    _TrainingSample(
        'gym fitness membership health', TransactionCategory.health),

    // Utilities
    _TrainingSample(
        'tnb electricity bill utility', TransactionCategory.utilities),
    _TrainingSample('air selangor water bill', TransactionCategory.utilities),
    _TrainingSample(
        'unifi internet broadband wifi', TransactionCategory.utilities),
    _TrainingSample(
        'maxis celcom digi phone bill', TransactionCategory.utilities),
    _TrainingSample(
        'astro subscription utility bill', TransactionCategory.utilities),

    // Education
    _TrainingSample('tuition class school fee', TransactionCategory.education),
    _TrainingSample('book textbook notebook stationery paper card',
        TransactionCategory.education),
    _TrainingSample(
        'udemy coursera course certification', TransactionCategory.education),
    _TrainingSample(
        'college university exam workshop', TransactionCategory.education),

    // Travel
    _TrainingSample('hotel agoda booking room', TransactionCategory.travel),
    _TrainingSample(
        'airbnb homestay resort vacation', TransactionCategory.travel),
    _TrainingSample(
        'traveloka flight luggage passport', TransactionCategory.travel),
    _TrainingSample('klook tour ticket holiday', TransactionCategory.travel),

    // Subscriptions
    _TrainingSample('netflix spotify monthly subscription',
        TransactionCategory.subscriptions),
    _TrainingSample(
        'icloud google storage premium', TransactionCategory.subscriptions),
    _TrainingSample(
        'adobe canva microsoft annual plan', TransactionCategory.subscriptions),
    _TrainingSample(
        'chatgpt openai github hosting', TransactionCategory.subscriptions),

    // Rent
    _TrainingSample('house rent landlord apartment', TransactionCategory.rent),
    _TrainingSample(
        'condo rental maintenance strata', TransactionCategory.rent),
    _TrainingSample('room rent deposit property', TransactionCategory.rent),

    // Income
    _TrainingSample(
        'salary payroll wages gaji bonus', TransactionCategory.salary),
    _TrainingSample(
        'freelance client project invoice', TransactionCategory.freelance),
    _TrainingSample(
        'dividend interest stock investment', TransactionCategory.investment),
    _TrainingSample('gift duit raya present', TransactionCategory.gift),
    _TrainingSample(
        'refund cashback reimbursement return', TransactionCategory.refund),
    _TrainingSample(
        'side income allowance other income', TransactionCategory.incomeOther),
  ];

  static final _NaiveBayesTextModel _mlModel =
      _NaiveBayesTextModel.train(_mlTrainingSamples);

  /// AI-based categorization: returns best matching category + confidence score
  static CategoryResult categorize(String text, TransactionType type) {
    final learned = CategoryLearningService.lookup(
        CategoryLearningService.textKey(text, type), type);
    if (learned != null) return _known(learned, .98);
    if (type == TransactionType.expense) {
      if (ReceiptParser.isHouseholdSupply(text)) {
        return _known(TransactionCategory.homeAppliances);
      }
      final merchant = merchantCategory(text);
      if (merchant != null && _normalize(text).split(' ').length <= 4) {
        return _known(merchant);
      }
      final item = _specificItem(text);
      if (item != null) return _known(item);
    }
    final mlResult = _mlModel.predict(text, type);
    final ruleResult = _categorizeWeighted({text: 1}, type);
    return _selectBestResult(mlResult, ruleResult);
  }

  /// OCR categorization weighs item names highest because receipt headers often
  /// contain merchant names that are less specific than the purchased items.
  static CategoryResult categorizeReceipt({
    String? merchant,
    required List<String> items,
    required String rawText,
    List<double?> itemAmounts = const [],
  }) {
    final learned = CategoryLearningService.lookup(
        CategoryLearningService.receiptKey(merchant, items),
        TransactionType.expense);
    if (learned != null) return _known(learned, .98);
    final merchantResult = merchantCategory(merchant ?? '');
    final scores = <TransactionCategory, double>{};
    var known = 0;
    // Only use prices if all rows have valid prices, avoiding mixed weight units.
    final priced = itemAmounts.length == items.length &&
        itemAmounts.every((a) => a != null && a.isFinite && a > 0);
    for (var i = 0; i < items.length; i++) {
      if (ReceiptItemCleanup.clean(items[i]) == null) continue;
      var result = categorize(items[i], TransactionType.expense);
      if (merchantResult == TransactionCategory.food &&
          result.category == TransactionCategory.groceries &&
          RegExp(r'\b(chicken|ayam|rice|roti)\b', caseSensitive: false)
              .hasMatch(items[i]) &&
          !RegExp(r'\b(raw|fresh|kg|beras)\b', caseSensitive: false)
              .hasMatch(items[i])) {
        result = _known(TransactionCategory.food);
      }
      if (result.confidence < .45 ||
          result.category == TransactionCategory.other) {
        continue;
      }
      known++;
      scores.update(result.category, (s) => s + (priced ? itemAmounts[i]! : 1),
          ifAbsent: () => priced ? itemAmounts[i]! : 1);
    }
    if (scores.isEmpty) {
      // Readable product words still help when OCR cannot pair names and prices.
      // Use explicit item rules only, avoiding guesses from receipt boilerplate.
      final fragments = rawText.split('\n').where((line) =>
          line.trim() != merchant &&
          !RegExp(r'\b(total|payment|cashier|address|jalan|thank|points|member)\b',
                  caseSensitive: false)
              .hasMatch(line));
      final fragmentCategories = fragments
          .map((line) => ReceiptParser.isHouseholdSupply(line)
              ? TransactionCategory.homeAppliances
              : _specificItem(line))
          .whereType<TransactionCategory>()
          .toList();
      if (fragmentCategories.isNotEmpty) {
        final counts = <TransactionCategory, int>{};
        for (final category in fragmentCategories) {
          counts.update(category, (n) => n + 1, ifAbsent: () => 1);
        }
        final ranked = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return _known(ranked.first.key,
            .7 * ranked.first.value / fragmentCategories.length);
      }
      if (merchantResult != null) {
        return _known(merchantResult, items.isEmpty ? .8 : .6);
      }
      return categorize(merchant ?? '', TransactionType.expense);
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = scores.values.fold(0.0, (a, b) => a + b);
    final share = sorted.first.value / total;
    return CategoryResult(
        category: sorted.first.key,
        confidence: (share * (known / items.length) * .9).clamp(0.0, .9),
        suggestions: sorted.take(3).map((e) => e.key).toList());
  }

  static TransactionCategory? _specificItem(String text) {
    final normalized = _normalize(text);
    bool any(List<String> words) =>
        words.any((word) => _matches(normalized, word));
    if (any(['rice cooker', 'chicken feed']))
      return TransactionCategory.shopping;
    if (any([
      'chicken rice',
      'nasi ayam',
      'nasi lemak',
      'fried rice',
      'nasi goreng',
      'ayam goreng',
      'roti canai',
      'cooked rice'
    ])) {
      return TransactionCategory.food;
    }
    if (any([
      'wet tissue',
      'wet tissues',
      'tissue',
      'tissues',
      'wet wipes',
      'wipes',
      'chicken',
      'ayam',
      'rice',
      'beras',
      'milk',
      'susu',
      'eggs',
      'mushroom',
      'mushrooms',
      'cendawan',
      'avocado',
      'apple',
      'apples',
      'carrot',
      'lobak',
      'tauhu',
      'telur',
      'detergent',
      'tisu basah',
      'tisu',
      'egg',
      'beef',
      'fish',
      'ikan',
      'daging',
      'vegetables',
      'sayur',
      'fruit',
      'fruits',
      'buah',
      'flour',
      'tepung',
      'sugar',
      'gula',
      'salt',
      'garam',
      'cooking oil',
      'minyak masak'
    ])) {
      return TransactionCategory.groceries;
    }
    if (any([
      'panadol',
      'paracetamol',
      'medicine',
      'ubat',
      'vitamin',
      'supplement'
    ])) {
      return TransactionCategory.health;
    }
    if (any([
      'lipstick',
      'makeup',
      'cosmetics',
      'mascara',
      'screwdriver',
      'storage box',
      'ribbon'
    ])) {
      return TransactionCategory.shopping;
    }
    return null;
  }

  static CategoryResult _selectBestResult(
    CategoryResult mlResult,
    CategoryResult ruleResult,
  ) {
    if (ruleResult.confidence >= .6) return ruleResult;
    if (mlResult.confidence >= 0.65) return mlResult;
    if (ruleResult.confidence > mlResult.confidence + 0.18) {
      return ruleResult;
    }
    return ruleResult;
  }

  static CategoryResult _categorizeWeighted(
    Map<String, int> weightedText,
    TransactionType type,
  ) {
    final Map<TransactionCategory, int> scores = {};

    for (final textEntry in weightedText.entries) {
      final normalized = _normalize(textEntry.key);
      if (normalized.isEmpty) continue;
      final weight = textEntry.value;

      for (final entry in _categoryKeywords.entries) {
        int score = 0;
        for (final keyword in entry.value) {
          final normalizedKeyword = _normalize(keyword);
          if (_matches(normalized, normalizedKeyword)) {
            final exactPattern = RegExp(
              '(^| )${RegExp.escape(normalizedKeyword)}( |\$)',
              caseSensitive: false,
            );
            score += exactPattern.hasMatch(normalized) ? 4 : 2;
          }
        }
        if (score > 0) {
          scores[entry.key] = (scores[entry.key] ?? 0) + (score * weight);
        }
      }
    }

    // Filter categories by transaction type
    final relevantCategories = scores.entries.where((e) {
      final isIncomeCategory = [
        TransactionCategory.salary,
        TransactionCategory.freelance,
        TransactionCategory.investment,
        TransactionCategory.gift,
        TransactionCategory.refund,
        TransactionCategory.incomeOther,
      ].contains(e.key);
      return type == TransactionType.income
          ? isIncomeCategory
          : !isIncomeCategory;
    });

    if (relevantCategories.isEmpty) {
      return CategoryResult(
        category: type == TransactionType.income
            ? TransactionCategory.incomeOther
            : TransactionCategory.other,
        confidence: 0.0,
        suggestions: [],
      );
    }

    // Sort by score
    final sorted = relevantCategories.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topScore = sorted.first.value;
    final runnerUp = sorted.length > 1 ? sorted[1].value : 0;
    final confidence =
        (.45 + .4 * (topScore - runnerUp) / topScore).clamp(0.0, .85);

    return CategoryResult(
      category: sorted.first.key,
      confidence: confidence,
      suggestions: sorted.take(3).map((e) => e.key).toList(),
    );
  }

  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[’']"), '')
        .replaceAll(RegExp(r'\bmr[.]?\s*diy\b'), 'mr diy')
        .replaceAll(RegExp(r"[^a-z0-9&\s'-]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double? extractAmount(String text) =>
      ReceiptParser.extractAmount(text);
  static String? extractMerchant(String text) =>
      ReceiptParser.extractMerchant(text);

  /// Generate smart spending insights
  static List<String> generateInsights({
    required Map<TransactionCategory, double> categoryBreakdown,
    required double totalIncome,
    required double totalExpense,
    required List<Map<String, dynamic>> monthlyTrend,
  }) {
    final insights = <String>[];

    // Savings rate
    if (totalIncome > 0) {
      final savingsRate = ((totalIncome - totalExpense) / totalIncome * 100);
      if (savingsRate < 20) {
        insights.add(
            '⚠️ Your savings rate is ${savingsRate.toStringAsFixed(1)}%. Aim for at least 20%.');
      } else {
        insights.add(
            '✅ Great job! You\'re saving ${savingsRate.toStringAsFixed(1)}% of your income.');
      }
    }

    // Top spending category
    if (categoryBreakdown.isNotEmpty) {
      final top =
          categoryBreakdown.entries.reduce((a, b) => a.value > b.value ? a : b);
      final pct = totalExpense > 0
          ? (top.value / totalExpense * 100).toStringAsFixed(0)
          : '0';
      insights.add(
          '📊 ${top.key.label} is your biggest expense at $pct% of spending.');
    }

    // Overspending warning
    if (totalExpense > totalIncome && totalIncome > 0) {
      insights.add(
          '🔴 You\'re spending more than you earn this month. Review your expenses!');
    }

    return insights;
  }
}

class CategoryResult {
  final TransactionCategory category;
  final double confidence; // 0.0 to 1.0
  final List<TransactionCategory> suggestions;

  CategoryResult({
    required this.category,
    required this.confidence,
    required this.suggestions,
  });
}

class _TrainingSample {
  final String text;
  final TransactionCategory category;

  const _TrainingSample(this.text, this.category);
}

class _NaiveBayesTextModel {
  final Map<TransactionCategory, Map<String, int>> tokenCounts;
  final Map<TransactionCategory, int> tokenTotals;
  final Map<TransactionCategory, int> documentCounts;
  final Set<String> vocabulary;
  final int documentTotal;

  const _NaiveBayesTextModel({
    required this.tokenCounts,
    required this.tokenTotals,
    required this.documentCounts,
    required this.vocabulary,
    required this.documentTotal,
  });

  factory _NaiveBayesTextModel.train(List<_TrainingSample> samples) {
    final tokenCounts = <TransactionCategory, Map<String, int>>{};
    final tokenTotals = <TransactionCategory, int>{};
    final documentCounts = <TransactionCategory, int>{};
    final vocabulary = <String>{};

    for (final sample in samples) {
      documentCounts[sample.category] =
          (documentCounts[sample.category] ?? 0) + 1;
      final categoryTokens =
          tokenCounts.putIfAbsent(sample.category, () => <String, int>{});

      for (final token in _tokenize(sample.text)) {
        vocabulary.add(token);
        categoryTokens[token] = (categoryTokens[token] ?? 0) + 1;
        tokenTotals[sample.category] = (tokenTotals[sample.category] ?? 0) + 1;
      }
    }

    return _NaiveBayesTextModel(
      tokenCounts: tokenCounts,
      tokenTotals: tokenTotals,
      documentCounts: documentCounts,
      vocabulary: vocabulary,
      documentTotal: samples.length,
    );
  }

  CategoryResult predict(String text, TransactionType type) {
    final tokens = _tokenize(text).where(vocabulary.contains).toList();
    final categories = TransactionCategory.values
        .where((category) =>
            category.isIncomeCategory == (type == TransactionType.income))
        .toList();

    if (tokens.isEmpty) {
      return CategoryResult(
        category: type == TransactionType.income
            ? TransactionCategory.incomeOther
            : TransactionCategory.other,
        confidence: 0,
        suggestions: const [],
      );
    }

    final logScores = <TransactionCategory, double>{};
    for (final category in categories) {
      final categoryDocCount = documentCounts[category] ?? 0;
      if (categoryDocCount == 0) continue;

      final prior = math.log(categoryDocCount / documentTotal);
      final categoryTokenCounts =
          tokenCounts[category] ?? const <String, int>{};
      final totalTokens = tokenTotals[category] ?? 0;
      final denominator = totalTokens + vocabulary.length;
      var score = prior;

      for (final token in tokens) {
        final count = categoryTokenCounts[token] ?? 0;
        score += math.log((count + 1) / denominator);
      }

      logScores[category] = score;
    }

    if (logScores.isEmpty) {
      return CategoryResult(
        category: type == TransactionType.income
            ? TransactionCategory.incomeOther
            : TransactionCategory.other,
        confidence: 0,
        suggestions: const [],
      );
    }

    final maxLog = logScores.values.reduce(math.max);
    final probabilities = logScores.map(
      (category, score) => MapEntry(category, math.exp(score - maxLog)),
    );
    final sum = probabilities.values.fold(0.0, (total, value) => total + value);
    final normalized = probabilities.map(
      (category, value) => MapEntry(category, value / sum),
    );
    final sorted = normalized.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return CategoryResult(
      category: sorted.first.key,
      confidence: sorted.first.value.clamp(0.0, 1.0).toDouble(),
      suggestions: sorted.take(3).map((entry) => entry.key).toList(),
    );
  }

  static List<String> _tokenize(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9&\s'-]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];
    return normalized
        .split(' ')
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toList();
  }

  static const Set<String> _stopWords = {
    'the',
    'and',
    'for',
    'with',
    'rm',
    'myr',
    'qty',
    'pcs',
    'unit',
    'no',
    'resit',
    'receipt',
  };
}
