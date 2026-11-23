import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/models/transaction_model.dart';
import 'package:expense_tracker/services/receipt_parser.dart';
import 'package:expense_tracker/services/ocr_service.dart';
import 'package:expense_tracker/services/ai_categorization_service.dart';
import 'package:expense_tracker/services/category_learning_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CategoryLearningService.load('test-user');
  });
  test('total takes precedence over subtotal, cash and change', () {
    expect(
        ReceiptParser.extractAmount(
            'BATARAS\nChicken 12.00\nSub Total 12.00\nTax 0.72\nGrand Total 12.72\nCash 100.00\nChange 87.28'),
        12.72);
    expect(
        ReceiptParser.extractAmount(
            'Total items 12\nTOTAL\nRM 1,234.50\nCASH 2000.00'),
        1234.50);
    expect(ReceiptParser.extractAmount('TOTAL RM 12,50'), 12.5);
    expect(ReceiptParser.extractAmount('TOTAL RM 1O.OO'), 10);
    expect(
        ReceiptParser.extractAmount('Chicken 12.00\nCash 50.00\nChange 38.00'),
        isNull);
  });
  test('items retain word boundaries, split prices and duplicate purchases',
      () {
    final items = ReceiptParser.extractItems(
        'MR DIY\nJalan Example\nTAXI TOY 5.00\nWET TISSUE\n2.50\nWET TISSUE 2.50\nSubtotal 10.00\nCash 20.00');
    expect(items.map((i) => i.name), ['TAXI TOY', 'WET TISSUE', 'WET TISSUE']);
    expect(items.map((i) => i.amount), [5, 2.5, 2.5]);
  });
  test('validates calendar dates and supports ISO and named months', () {
    expect(ReceiptParser.extractDate('2026-10-07 14:25'),
        DateTime(2026, 10, 7, 14, 25));
    expect(ReceiptParser.extractDate('07/10/26 14:25'),
        DateTime(2026, 10, 7, 14, 25));
    expect(ReceiptParser.extractDate('7 OCT 2026'), DateTime(2026, 10, 7));
    expect(ReceiptParser.extractDate('31/02/2026'), isNull);
    expect(ReceiptParser.extractDate('07/10/2026 25:90'), isNull);
  });
  final shops = {
    'Bataras': TransactionCategory.groceries,
    'Jaya Grocer': TransactionCategory.groceries,
    'Ninso': TransactionCategory.shopping,
    'MR. DIY': TransactionCategory.shopping,
    'KKV': TransactionCategory.shopping,
    'Watson': TransactionCategory.health,
    'Watsons': TransactionCategory.health,
    'Guardian': TransactionCategory.health,
  };
  for (final shop in shops.entries) {
    test('recognizes ${shop.key}', () {
      expect(
          AiCategorizationService.categorize(shop.key, TransactionType.expense)
              .category,
          shop.value);
    });
  }
  for (final item in ['chicken', 'ayam', 'rice', 'beras']) {
    test('recognizes grocery item $item', () {
      expect(
          AiCategorizationService.categorize(item, TransactionType.expense)
              .category,
          TransactionCategory.groceries);
    });
  }
  test('items distinguish household supplies from pharmacy and prepared dishes',
      () {
    expect(
        AiCategorizationService.categorizeReceipt(
                merchant: 'GUARDIAN',
                items: ['wet tissue'],
                rawText: 'VISA CARD')
            .category,
        TransactionCategory.homeAppliances);
    expect(
        AiCategorizationService.categorizeReceipt(
                merchant: 'WATSONS', items: ['PANADOL'], rawText: '')
            .category,
        TransactionCategory.health);
    expect(
        AiCategorizationService.categorizeReceipt(
                merchant: 'KFC', items: ['CHICKEN'], rawText: '')
            .category,
        TransactionCategory.food);
    expect(
        AiCategorizationService.categorize('nasi ayam', TransactionType.expense)
            .category,
        TransactionCategory.food);
    expect(
        AiCategorizationService.categorize(
                'chicken rice', TransactionType.expense)
            .category,
        TransactionCategory.food);
  });
  test('mixed receipt uses item values and expresses ambiguity', () {
    final mixed = AiCategorizationService.categorizeReceipt(
        merchant: 'KKV',
        items: ['wet tissue', 'lipstick'],
        itemAmounts: [5, 40],
        rawText: 'visa card');
    expect(mixed.category, TransactionCategory.shopping);
    expect(mixed.suggestions, contains(TransactionCategory.homeAppliances));
    final tie = AiCategorizationService.categorizeReceipt(
        merchant: 'KKV',
        items: ['wet tissue', 'lipstick'],
        itemAmounts: [5, 5],
        rawText: '');
    expect(tie.confidence, lessThan(.65));
  });
  test(
      'unknown words do not acquire confident categories from substrings or priors',
      () {
    final result = AiCategorizationService.categorize(
        'scarab xyzzy qwerty', TransactionType.expense);
    expect(result.category, TransactionCategory.other);
    expect(result.confidence, 0);
  });
  test(
      'confirmed choices persist and are separated by user and transaction type',
      () async {
    final key =
        CategoryLearningService.textKey('Wet tissue', TransactionType.expense);
    await CategoryLearningService.remember(key, TransactionCategory.shopping);
    await CategoryLearningService.load('test-user');
    expect(
        AiCategorizationService.categorize(
                'Wet tissue', TransactionType.expense)
            .category,
        TransactionCategory.shopping);
    expect(CategoryLearningService.lookup(key, TransactionType.income), isNull);
    await CategoryLearningService.load('another-user');
    expect(
        AiCategorizationService.categorize(
                'Wet tissue', TransactionType.expense)
            .category,
        TransactionCategory.homeAppliances);
  });
  test('learning a mixed basket does not relabel each individual item',
      () async {
    await CategoryLearningService.remember(
        CategoryLearningService.receiptKey('KKV', ['wet tissue', 'lipstick']),
        TransactionCategory.shopping);
    expect(
        AiCategorizationService.categorizeReceipt(
                merchant: 'KKV', items: ['lipstick', 'wet tissue'], rawText: '')
            .confidence,
        .98);
    expect(
        AiCategorizationService.categorize(
                'wet tissue', TransactionType.expense)
            .category,
        TransactionCategory.homeAppliances);
  });
  test('end to end receipt parsing for the user’s shop and item examples', () {
    final result = OcrService.parseText(
        'RECEIPT\nBATARAS SDN BHD\n07/10/2026\nWET TISSUE 2.50\nAYAM 12.00\nBERAS 25.00\nSUBTOTAL 39.50\nTOTAL 39.50\nCASH 50.00');
    expect(result.merchant, 'Bataras');
    expect(result.items, ['WET TISSUE', 'AYAM', 'BERAS']);
    expect(result.amount, 39.5);
    expect(result.suggestedCategory, TransactionCategory.groceries);
  });
  test('readable receipt with unknown items defaults to Other', () {
    final result = OcrService.parseText(
        'RECEIPT\nXYZ SDN BHD\n31/10/2026\nZXQ123 12.00\nTOTAL 12.00\nCASH 12.00');
    expect(result.amount, 12);
    expect(result.suggestedCategory, TransactionCategory.other);
  });
  test('Ninso receipt keeps invoice, date, total and debit payment separate',
      () {
    final result =
        OcrService.parseText('''NINSO GLOBAL SDN BHD 200801004331 (805614-T)
LOT 12-16/FIRST & 2ND FLOOR
GS PLAZA, JALAN MOHD SALLEH
Invoice No: S2LB98202609290073    29/09/26
NINSO WET KITCHEN TOWEL 18X20CM 60SHEETS
74075300 2.80 1 2.80
Item 1
Qty 1
Total Saving 0.00
Total 2.80
Rounding 0.00
Total 2.80
MYDEBIT 4788 APP: 123100 2.80
Change 0.00''');
    expect(result.merchant, 'Ninso');
    expect(result.receiptNumber, 'S2LB98202609290073');
    expect(result.date, DateTime(2026, 9, 29));
    expect(result.items, ['Ninso Wet Tissue']);
    expect(result.amount, 2.8);
    expect(result.suggestedCategory, TransactionCategory.homeAppliances);
    expect(result.paymentMethod, 'Debit card / bank');
  });
}
