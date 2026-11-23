import 'dart:io';
import '../services/ocr_service.dart';
import '../services/receipt_notes.dart';
import '../widgets/receipt_summary.dart';
import '../widgets/receipt_review_dialog.dart';
import '../services/product_memory_service.dart';
import '../widgets/amount_keypad.dart';
import 'dart:ui';
import 'category_management_screen.dart';
import '../utils/category_icons.dart';
import '../models/split_bill.dart';
import '../widgets/split_bill_editor.dart';
import 'transfer_screen.dart';
import 'scan_receipt_screen.dart';
// lib/screens/add_transaction_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../services/ai_categorization_service.dart';
import '../services/category_learning_service.dart';
import '../services/receipt_account_matcher.dart';
import '../utils/app_theme.dart';
import '../services/merchant_service.dart';
import 'accounts_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  final TransactionType initialType;
  final TransactionModel? editTransaction;
  final String? prefilledTitle;
  final double? prefilledAmount;
  final TransactionCategory? prefilledCategory;
  final DateTime? prefilledDate;
  final String? prefilledReceiptImagePath;
  final String? prefilledNote;
  final String? receiptLearningKey;
  final String? prefilledPaymentMethod;
  final bool requireAccountSelection;
  final bool isProductScan;
  final OcrResult? receiptReview;
  final String? scanMessage;

  const AddTransactionScreen({
    super.key,
    this.initialType = TransactionType.expense,
    this.editTransaction,
    this.prefilledTitle,
    this.prefilledAmount,
    this.prefilledCategory,
    this.prefilledDate,
    this.prefilledReceiptImagePath,
    this.prefilledNote,
    this.receiptLearningKey,
    this.prefilledPaymentMethod,
    this.requireAccountSelection = false,
    this.isProductScan = false,
    this.receiptReview,
    this.scanMessage,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  late TransactionType _type;
  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  TransactionCategory? _selectedCategory;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _isRecurring = false;
  String _recurringFrequency = 'monthly';
  bool _isSaving = false;
  bool _transferMode = false;
  String _calculation = '';
  OcrResult? _receiptReview;
  int _receiptEditRevision = 0;
  final _noteFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _totalController = TextEditingController();
  bool _rememberCategory = false;
  SplitBill? _split;
  late final String _formOwner;

  // AI suggestion state
  CategoryResult? _aiSuggestion;
  bool _showAiSuggestion = false;

  @override
  void initState() {
    super.initState();
    _formOwner = context.read<ExpenseProvider>().userId;
    _receiptReview = widget.receiptReview;
    _noteFocus.addListener(_focusChanged);
    _amountFocus.addListener(_focusChanged);
    _type = widget.editTransaction?.type ?? widget.initialType;
    _split = widget.editTransaction?.split;
    _titleController = TextEditingController(
        text: widget.editTransaction?.title ?? widget.prefilledTitle ?? '');
    _amountController = TextEditingController(
      text: (_split == null
                  ? widget.editTransaction?.amount
                  : _split!.totalSen / 100)
              ?.toStringAsFixed(2) ??
          (widget.prefilledAmount != null
              ? widget.prefilledAmount!.toStringAsFixed(2)
              : ''),
    );
    _noteController = TextEditingController(
        text: widget.editTransaction?.note ??
            (widget.isProductScan
                ? widget.prefilledTitle
                : widget.prefilledNote) ??
            '');
    _totalController.text =
        _amountController.text.isEmpty ? '0.00' : _amountController.text;
    _selectedCategory =
        widget.editTransaction?.category ?? widget.prefilledCategory;
    _selectedCategoryId =
        widget.editTransaction?.categoryId ?? widget.prefilledCategory?.name;
    _selectedAccountId = widget.editTransaction?.accountId ??
        ReceiptAccountMatcher.suggest(widget.prefilledPaymentMethod,
            context.read<ExpenseProvider>().accounts);
    _selectedDate =
        widget.editTransaction?.date ?? widget.prefilledDate ?? DateTime.now();
    _isRecurring = widget.editTransaction?.isRecurring ?? false;
    _recurringFrequency =
        widget.editTransaction?.recurringFrequency ?? 'monthly';

    // Listen for title changes to trigger AI categorization
    _titleController.addListener(_onTitleChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _onTitleChanged() {
    final text = _titleController.text.trim();
    if (text.length >= 2) {
      final result = AiCategorizationService.categorize(text, _type);
      if (result.confidence > 0.05 || result.suggestions.isNotEmpty) {
        setState(() {
          _aiSuggestion = result;
          _showAiSuggestion = true;
        });
      } else {
        setState(() => _showAiSuggestion = false);
      }
    } else {
      setState(() => _showAiSuggestion = false);
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _noteFocus.dispose();
    _amountFocus.dispose();
    _totalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editTransaction != null;
    if (_transferMode)
      return Scaffold(
        appBar: AppBar(title: const Text('Add Transaction')),
        body: TransferScreen(embedded: true, header: _buildTypeToggle()),
      );
    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Transaction' : 'Add Transaction'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: AmountKeypad(
              key: ValueKey(_receiptEditRevision),
              noteEditing: _noteFocus.hasFocus ||
                  MediaQuery.viewInsetsOf(context).bottom > 0,
              onExpressionChanged: (value) {
                _amountFocus.requestFocus();
                setState(() => _calculation = value);
              },
              onTotalChanged: (value) => _totalController.value =
                  TextEditingValue(
                      text: value,
                      selection: TextSelection.collapsed(offset: value.length)),
              controller: _amountController,
              onDone: _save,
              onDate: _chooseDate,
              busy: _isSaving,
              toolbar: _entryToolbar())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTypeToggle(),
            if (_receiptReview != null) _buildScannedReceipt(),
            const SizedBox(height: 8),
            _buildCategorySelector(),
            const SizedBox(height: 12),
            if (_showAiSuggestion && _aiSuggestion != null) ...[
              const SizedBox(height: 8),
              _buildAiSuggestionBanner(),
            ],
            const SizedBox(height: 12),
            if (!widget.isProductScan &&
                (widget.prefilledTitle != null ||
                    widget.receiptLearningKey != null))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember this category',
                    style: TextStyle(fontSize: 14)),
                subtitle: Text(
                    widget.receiptLearningKey == null
                        ? 'Use my choice for this exact title next time.'
                        : 'Use my choice for this shop and item combination next time.',
                    style: const TextStyle(fontSize: 12)),
                value: _rememberCategory,
                onChanged: (value) =>
                    setState(() => _rememberCategory = value ?? false),
              ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildScannedReceipt() {
    final receipt = _receiptReview!;
    final warnings = [
      if (widget.scanMessage != null) widget.scanMessage!,
      ...receipt.reviewReasons
    ];
    return Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
            color: AppPalette.of(context).bgCard,
            borderRadius: BorderRadius.circular(18)),
        child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
                warnings.isEmpty
                    ? Icons.receipt_long_outlined
                    : Icons.info_outline_rounded,
                color: AppTheme.primary),
            title: Text(
                warnings.isEmpty
                    ? 'Scanned receipt'
                    : 'Scanned receipt · Check details',
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
                warnings.isEmpty
                    ? '${receipt.lineItems.length} items · Photo attached'
                    : warnings.first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (widget.scanMessage != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(widget.scanMessage!,
                        style: const TextStyle(fontSize: 12))),
              ReceiptSummary(receipt: receipt),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Edit scanned details'),
                    onPressed: () async {
                      final edited = await showDialog<OcrResult>(
                          context: context,
                          builder: (_) =>
                              ReceiptReviewDialog(receipt: receipt));
                      if (edited == null || !mounted) return;
                      final symbol =
                          context.read<ExpenseProvider>().currencySymbol;
                      const codes = {
                        'RM': 'MYR',
                        r'$': 'USD',
                        r'S$': 'SGD',
                        '€': 'EUR',
                        '£': 'GBP'
                      };
                      final mismatch = edited.currency != null &&
                          edited.currency != (codes[symbol] ?? symbol);
                      _titleController.text = edited.merchant ?? '';
                      _amountController.text = mismatch
                          ? ''
                          : edited.amount?.toStringAsFixed(2) ?? '';
                      _totalController.text = _amountController.text.isEmpty
                          ? '0.00'
                          : _amountController.text;
                      _noteController.text =
                          buildReceiptNote(edited, defaultCurrency: symbol) ??
                              '';
                      setState(() {
                        if (_split != null &&
                            (_amountController.text.isEmpty ||
                                _split!.totalSen !=
                                    ((double.tryParse(_amountController.text) ??
                                                0) *
                                            100)
                                        .round())) {
                          _split = null;
                        }
                        _receiptReview = edited;
                        _receiptEditRevision++;
                        _calculation = '';
                        _selectedCategory =
                            edited.suggestedCategory ?? _selectedCategory;
                        _selectedCategoryId = _selectedCategory?.name;
                        _selectedDate = edited.date ?? _selectedDate;
                      });
                    }),
                if (widget.prefilledReceiptImagePath != null)
                  TextButton.icon(
                      icon: const Icon(Icons.image_outlined, size: 17),
                      label: const Text('View photo'),
                      onPressed: () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                              child: InteractiveViewer(
                                  child: Image.file(
                                      File(widget.prefilledReceiptImagePath!),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Text(
                                                  'Photo unavailable'))))))),
              ]),
            ]));
  }

  Future<void> _editSplit() async {
    if ((_calculation.contains(' + ') || _calculation.contains(' − ')) &&
        !_calculation.contains(' = ')) {
      _showError('Tap = to calculate the bill total first.');
      return;
    }
    final value = double.tryParse(_amountController.text);
    if (value == null || !value.isFinite || value <= 0 || value > 100000000) {
      _showError('Enter the bill total first.');
      return;
    }
    final bill = await showDialog<SplitBill>(
        context: context,
        builder: (_) => SplitBillEditor(
            totalSen: (value * 100).round(),
            owner: context.read<ExpenseProvider>().userId,
            initial: _split));
    if (bill != null && mounted) setState(() => _split = bill);
  }

  Future<void> _chooseDate() async {
    var selected = _selectedDate;
    final result = await showModalBottomSheet<DateTime>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        builder: (ctx) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Select date',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  SizedBox(
                      height: 300,
                      child: CalendarDatePicker(
                          initialDate: selected,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          onDateChanged: (date) => selected = date)),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, selected),
                          child: const Text('Confirm'))),
                ]))));
    if (result != null && mounted)
      setState(() => _selectedDate = DateTime(result.year, result.month,
          result.day, _selectedDate.hour, _selectedDate.minute));
  }

  Future<void> _chooseAccount() async {
    final provider = context.read<ExpenseProvider>();
    final id = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Choose account')),
              for (final account in provider.accounts)
                ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(account.name),
                    trailing: account.id == _selectedAccountId
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(ctx, account.id)),
              ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add Account'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AddAccountScreen()));
                  }),
            ])));
    if (id != null && mounted) setState(() => _selectedAccountId = id);
  }

  Widget _entryToolbar() {
    final provider = context.watch<ExpenseProvider>();
    final account = _selectedAccountId == null
        ? null
        : provider.accountById(_selectedAccountId ?? provider.defaultAccountId);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                TextButton.icon(
                    key: const ValueKey('transaction-account-picker'),
                    onPressed: _chooseAccount,
                    icon: const Icon(Icons.account_balance_wallet_outlined,
                        size: 18),
                    label: Text(account?.name ?? 'Account',
                        style: const TextStyle(fontSize: 11))),
                if (_type == TransactionType.expense)
                  TextButton.icon(
                      onPressed: _editSplit,
                      icon: const Icon(Icons.group_outlined, size: 18),
                      label: Text(
                          _split == null
                              ? 'Split'
                              : 'Split · ${_split!.people.length}',
                          style: const TextStyle(fontSize: 11))),
                TextButton.icon(
                    onPressed: () async {
                      if (_isRecurring) {
                        setState(() => _isRecurring = false);
                        return;
                      }
                      final frequency = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (ctx) => SafeArea(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                    const ListTile(
                                        title: Text('Repeat this transaction')),
                                    for (final value in [
                                      'daily',
                                      'weekly',
                                      'monthly',
                                      'yearly'
                                    ])
                                      ListTile(
                                          title: Text(value[0].toUpperCase() +
                                              value.substring(1)),
                                          onTap: () =>
                                              Navigator.pop(ctx, value)),
                                  ])));
                      if (frequency != null && mounted)
                        setState(() {
                          _isRecurring = true;
                          _recurringFrequency = frequency;
                        });
                    },
                    icon: Icon(
                        _isRecurring
                            ? Icons.repeat_on_rounded
                            : Icons.repeat_rounded,
                        size: 18),
                    label: Text('Recurring ${_isRecurring ? 'On' : 'Off'}',
                        style: const TextStyle(fontSize: 11))),
              ]))),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_calculation.contains(' + ') ||
                _calculation.contains(' − ') ||
                _calculation.contains(' = '))
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(_calculation,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppPalette.of(context).textMuted))),
            TextField(
                controller: _totalController,
                focusNode: _amountFocus,
                readOnly: true,
                showCursor: true,
                keyboardType: TextInputType.none,
                onTap: () {
                  _noteFocus.unfocus();
                  _amountFocus.requestFocus();
                },
                style:
                    const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                    prefixText: '${provider.currencySymbol} ',
                    suffixIcon: _selectedCategory == null
                        ? null
                        : SizedBox(
                            width: 110,
                            child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                    provider
                                            .categoryById(
                                                _selectedCategoryId ?? '')
                                            ?.name ??
                                        _selectedCategory!.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppPalette.of(context)
                                            .textMuted)))),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero)),
          ])),
      Row(children: [
        Expanded(
            child: TextField(
                controller: _noteController,
                focusNode: _noteFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _noteFocus.unfocus(),
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                    hintText: 'Add a note…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10)))),
        IconButton(
            tooltip: 'Attach document',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const ScanReceiptScreen(importDocument: true))),
            icon: const Icon(Icons.attach_file_rounded, size: 20)),
        IconButton(
            tooltip: 'Scan receipt',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ScanReceiptScreen(openCamera: true))),
            icon: const Icon(Icons.photo_camera_outlined, size: 20)),
      ]),
    ]);
  }

  Widget _buildTypeToggle() => Row(children: [
        for (final mode in ['Expenses', 'Income', 'Transfer'])
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        backgroundColor: (mode == 'Expenses' &&
                                    !_transferMode &&
                                    _type == TransactionType.expense) ||
                                (mode == 'Income' &&
                                    !_transferMode &&
                                    _type == TransactionType.income) ||
                                (mode == 'Transfer' && _transferMode)
                            ? AppTheme.primary.withValues(alpha: .16)
                            : Colors.transparent),
                    onPressed: () {
                      if (mode == 'Transfer') {
                        setState(() => _transferMode = true);
                        return;
                      }
                      setState(() {
                        _transferMode = false;
                        _type = mode == 'Income'
                            ? TransactionType.income
                            : TransactionType.expense;
                        _selectedCategory = null;
                        _selectedCategoryId = null;
                        _showAiSuggestion = false;
                        if (_type == TransactionType.income) _split = null;
                      });
                    },
                    child: Text(mode,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ))),
      ]);

  void _applyAiSuggestion() {
    final suggestion = _aiSuggestion;
    if (suggestion == null) return;
    final provider = context.read<ExpenseProvider>();
    final suggestedCategory = provider.categoryById(suggestion.category.name);
    setState(() {
      _selectedCategory = suggestion.category;
      _selectedCategoryId = suggestedCategory?.id ?? suggestion.category.name;
      _showAiSuggestion = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Applied ${suggestedCategory?.name ?? suggestion.category.label}',
        ),
        backgroundColor: AppTheme.incomeColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildAiSuggestionBanner() {
    final suggestion = _aiSuggestion!;
    final provider = context.read<ExpenseProvider>();
    final suggestedCategory = provider.categoryById(suggestion.category.name);
    return GestureDetector(
      onTap: _applyAiSuggestion,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Text('🤖', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Suggested: ${suggestedCategory?.icon ?? suggestion.category.emoji} ${suggestedCategory?.name ?? suggestion.category.label}',
                style: TextStyle(
                    color: AppPalette.of(context).textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
            ElevatedButton(
              onPressed: _applyAiSuggestion,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Apply', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    final provider = context.watch<ExpenseProvider>();
    final categories = provider.categoriesForType(_type);
    final favouriteParents = categories
        .where(provider.isFavouriteCategory)
        .map((c) => c.parentCategory)
        .toSet();
    final roots = categories
        .where((c) =>
            c.id == c.parentCategory.name &&
            favouriteParents.contains(c.parentCategory))
        .toList();
    void choose(AppCategory c) => setState(() {
          if (c.id == c.parentCategory.name) {
            c = categories
                    .where((child) =>
                        child.id != c.id &&
                        child.parentCategory == c.parentCategory &&
                        provider.isFavouriteCategory(child))
                    .firstOrNull ??
                c;
          }
          _selectedCategory = c.parentCategory;
          _selectedCategoryId = c.id;
          _showAiSuggestion = false;
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
            child: Text('Category',
                style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.of(context).textSecondary))),
        TextButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CategoryManagementScreen())),
            icon: const Icon(Icons.star_outline, size: 16),
            label: const Text('Favourites')),
        IconButton(
            tooltip: 'All categories',
            onPressed: _showCategoryLibrary,
            icon: const Icon(Icons.grid_view_rounded, size: 20))
      ]),
      LayoutBuilder(
          builder: (context, box) =>
              Wrap(spacing: 8, runSpacing: 10, children: [
                for (final cat in roots)
                  SizedBox(
                      width: (box.maxWidth - 24) / 4,
                      child: Column(children: [
                        SizedBox(
                            width: 52,
                            height: 52,
                            child: Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  InkWell(
                                      onTap: () => choose(cat),
                                      borderRadius: BorderRadius.circular(24),
                                      child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 180),
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(cat.colorValue)
                                                  .withValues(
                                                      alpha: _selectedCategory ==
                                                              cat.parentCategory
                                                          ? .35
                                                          : .12),
                                              border: Border.all(
                                                  color: _selectedCategory ==
                                                          cat.parentCategory
                                                      ? Color(cat.colorValue)
                                                      : Colors.transparent,
                                                  width: 2)),
                                          child: Icon(appCategoryIcon(cat),
                                              size: 23,
                                              color: Color(cat.colorValue)))),
                                  if (categories.any((c) =>
                                      c.id != cat.id &&
                                      c.parentCategory == cat.parentCategory))
                                    Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: PopupMenuButton<AppCategory>(
                                              padding: EdgeInsets.zero,
                                              iconSize: 13,
                                              tooltip:
                                                  'Choose ${cat.name} category',
                                              icon: Container(
                                                  decoration: BoxDecoration(
                                                      color:
                                                          AppPalette.of(context)
                                                              .bgCardLight,
                                                      shape: BoxShape.circle),
                                                  padding:
                                                      const EdgeInsets.all(2),
                                                  child: const Icon(
                                                      Icons.expand_more,
                                                      size: 13)),
                                              onSelected: choose,
                                              itemBuilder: (_) => [
                                                for (final c in [
                                                  cat,
                                                  ...categories.where((c) =>
                                                      c.id != cat.id &&
                                                      c.parentCategory ==
                                                          cat.parentCategory)
                                                ])
                                                  PopupMenuItem(
                                                      value: c,
                                                      child: Row(children: [
                                                        Icon(appCategoryIcon(c),
                                                            size: 20,
                                                            color: Color(
                                                                c.colorValue)),
                                                        const SizedBox(
                                                            width: 10),
                                                        Flexible(
                                                            child: Text(c.name))
                                                      ]))
                                              ],
                                            ))),
                                ])),
                        SizedBox(
                            height: 30,
                            child: GestureDetector(
                                onTap: () => choose(cat),
                                child: Text(
                                    _selectedCategory == cat.parentCategory
                                        ? (provider
                                                .categoryById(
                                                    _selectedCategoryId ?? '')
                                                ?.name ??
                                            cat.name)
                                        : cat.id ==
                                                TransactionCategory.food.name
                                            ? 'Food'
                                            : cat.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10)))),
                      ])),
              ])),
    ]);
  }

  Future<void> _showCategoryLibrary() async {
    final selected = await showDialog<AppCategory>(
        context: context,
        barrierColor: Colors.black45,
        builder: (ctx) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Dialog(
                backgroundColor:
                    AppPalette.of(context).bgCard.withValues(alpha: .96),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26)),
                child: SizedBox(
                  width: 420,
                  height: MediaQuery.sizeOf(ctx).height * .68,
                  child: StatefulBuilder(builder: (ctx, update) {
                    return Column(children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                          child: Row(children: [
                            const Expanded(
                                child: Text('All categories',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600))),
                            IconButton(
                                tooltip: 'Close',
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close)),
                          ])),
                      Expanded(
                          child: ListView(
                              padding: const EdgeInsets.all(12),
                              children: [
                            for (final c in context
                                .read<ExpenseProvider>()
                                .categoriesForType(_type))
                              ListTile(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  leading: Icon(appCategoryIcon(c),
                                      color: Color(c.colorValue)),
                                  title: Text(c.name,
                                      style: const TextStyle(fontSize: 13)),
                                  selected: c.id == _selectedCategoryId,
                                  selectedTileColor:
                                      AppTheme.primary.withValues(alpha: .12),
                                  onTap: () => Navigator.pop(ctx, c)),
                          ])),
                    ]);
                  }),
                ),
              ),
            ));
    if (selected != null && mounted)
      setState(() {
        _selectedCategory = selected.parentCategory;
        _selectedCategoryId = selected.id;
        _showAiSuggestion = false;
      });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_formOwner != context.read<ExpenseProvider>().userId) {
      _showError("Account changed. Reopen the transaction form.");
      return;
    }
    final title = _titleController.text.trim();
    final amountStr = _amountController.text.trim();

    if (amountStr.isEmpty) {
      _showError('Please enter an amount');
      return;
    }
    final amount = double.tryParse(amountStr);
    if (amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 100000000 ||
        (amount * 100).round() <= 0) {
      _showError('Please enter a valid amount');
      return;
    }
    if (_selectedCategory == null) {
      _showError('Please select a category');
      return;
    }

    if (_split != null && _split!.totalSen != (amount * 100).round()) {
      _showError('The bill total changed. Review the split amounts again.');
      return;
    }
    final provider = context.read<ExpenseProvider>();
    final selectedCategory = provider.categoryById(_selectedCategoryId ?? '');
    if ((widget.requireAccountSelection || widget.editTransaction == null) &&
        (_selectedAccountId == null ||
            provider.accountById(_selectedAccountId!) == null)) {
      await _chooseAccount();
      if (!mounted ||
          _selectedAccountId == null ||
          provider.accountById(_selectedAccountId!) == null) return;
      return _save();
    }
    final titleToSave = title.isEmpty
        ? '${selectedCategory?.name ?? _selectedCategory!.label} ${_type == TransactionType.income ? 'Income' : 'Expense'}'
        : title;
    final note = _noteController.text.trim();
    setState(() => _isSaving = true);

    try {
      if (widget.editTransaction != null) {
        await provider.updateTransaction(widget.editTransaction!.copyWith(
          title: titleToSave,
          amount: _split == null ? amount : _split!.ownSen / 100,
          splitData: _split?.encode(),
          type: _type,
          category: _selectedCategory,
          categoryId: _selectedCategoryId,
          accountId: _selectedAccountId ?? provider.defaultAccountId,
          date: _selectedDate,
          note: note.isEmpty ? null : note,
          isRecurring: _isRecurring,
          recurringFrequency: _isRecurring ? _recurringFrequency : null,
        ));
      } else {
        await provider.addTransaction(
          title: titleToSave,
          amount: _split == null ? amount : _split!.ownSen / 100,
          splitData: _split?.encode(),
          type: _type,
          category: _selectedCategory!,
          categoryId: _selectedCategoryId,
          accountId: _selectedAccountId ?? provider.defaultAccountId,
          date: _selectedDate,
          note: note.isEmpty ? null : note,
          receiptImagePath: widget.prefilledReceiptImagePath,
          isRecurring: _isRecurring,
          recurringFrequency: _isRecurring ? _recurringFrequency : null,
        );
      }

      if (!widget.isProductScan &&
          widget.prefilledTitle != null &&
          title.isNotEmpty &&
          _type == TransactionType.expense) {
        try {
          await MerchantService.remember(widget.prefilledTitle, title);
        } catch (_) {/* The transaction remains saved. */}
      }
      if (widget.isProductScan && widget.prefilledTitle != null) {
        try {
          await ProductMemoryService.remember(
              _formOwner, widget.prefilledTitle!, _selectedCategory!);
        } catch (_) {}
      }
      if (_rememberCategory &&
          (title.isNotEmpty || widget.receiptLearningKey != null)) {
        try {
          await CategoryLearningService.remember(
              widget.receiptLearningKey ??
                  CategoryLearningService.textKey(title, _type),
              _selectedCategory!);
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Transaction saved, but the category choice could not be remembered.')));
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (error, stackTrace) {
      debugPrint('Could not save transaction: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Could not save transaction: $error');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.expenseColor),
    );
  }
}
