import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../services/receipt_gate.dart';
import '../services/receipt_scan_draft.dart';
import '../services/product_scan_service.dart';
import '../services/ocr_service.dart';
import '../services/ai_receipt_service.dart';
import '../services/receipt_notes.dart';
import '../services/category_learning_service.dart';
import '../utils/app_theme.dart';
import 'receipt_camera_screen.dart';
import 'add_transaction_screen.dart';

class ScanReceiptScreen extends StatefulWidget {
  const ScanReceiptScreen(
      {super.key,
      this.openCamera = true,
      this.importDocument = false,
      this.productMode = false,
      this.receiptReader,
      this.receiptEnhancer,
      this.directoryProvider});
  final bool openCamera, importDocument, productMode;
  final Future<OcrResult> Function(File)? receiptReader;
  final Future<AiReceiptOutcome> Function(OcrResult)? receiptEnhancer;
  final Future<Directory> Function()? directoryProvider;
  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen> {
  final _ocr = OcrService();
  final _ai = AiReceiptService();
  bool _busy = false;
  late bool _product;
  String? _message;
  File? _photo;
  static const _documents = MethodChannel('spendly/documents');
  @override
  void initState() {
    super.initState();
    _product = widget.productMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.importDocument) {
        _importPdf();
      } else if (widget.openCamera) {
        _capture();
      }
    });
  }

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  Future<Directory> _directory() =>
      (widget.directoryProvider ?? getApplicationDocumentsDirectory)();

  Future<void> _capture() async {
    if (_busy) return;
    String? guidance;
    try {
      while (mounted) {
        final capture = await Navigator.push<ReceiptCapture>(
            context,
            MaterialPageRoute(
                builder: (_) => ReceiptCameraScreen(
                    productMode: _product, guidance: guidance)));
        if (!mounted) return;
        if (capture == null) {
          Navigator.pop(context);
          return;
        }
        _product = capture.product;
        try {
          if (_product) {
            await _processProduct(File(capture.path));
          } else {
            await _processPages([capture.path]);
          }
          return;
        } on FormatException {
          if (!mounted) return;
          setState(() => _busy = false);
          guidance = _product
              ? 'No clear product found. Frame one product and tap to focus.'
              : 'No readable receipt found. Keep the whole receipt in frame and tap the text to focus.';
        }
      }
    } catch (_) {
      _error();
    }
  }

  Future<void> _importPdf() async {
    if (_busy) return;
    try {
      final picked = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (!mounted) return;
      final path = picked?.files.single.path;
      if (path == null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _busy = true;
        _message = 'Opening your document…';
      });
      final pages = await _documents
          .invokeListMethod<String>('renderPdf', {'path': path});
      if (pages == null || pages.isEmpty)
        throw const FormatException('No readable PDF pages');
      await _processPages(pages);
    } catch (_) {
      _error();
    }
  }

  void _error() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = _product
          ? 'Could not identify this product. Try another photo.'
          : 'Could not read this photo. Try a clearer receipt photo or an unlocked PDF.';
    });
  }

  Future<void> _processProduct(File photo) async {
    final provider = context.read<ExpenseProvider>();
    final owner = provider.userId;
    setState(() {
      _busy = true;
      _photo = photo;
      _message = 'Recognising your product…';
    });
    final suggestion = await ProductScanService()
        .identify(photo, readLabel: () => _ocr.readLabel(photo));
    final directory = await _directory();
    final saved = await photo.copy(
        '${directory.path}/product-${DateTime.now().microsecondsSinceEpoch}.jpg');
    if (!mounted || provider.userId != owner) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => AddTransactionScreen(
                prefilledTitle: suggestion.name,
                isProductScan: true,
                prefilledCategory: suggestion.category,
                requireAccountSelection: true,
                prefilledNote: suggestion.name,
                prefilledReceiptImagePath: saved.path)));
  }

  Future<void> _processPages(List<String> paths) async {
    final provider = context.read<ExpenseProvider>();
    final owner = provider.userId;
    setState(() {
      _busy = true;
      _photo = File(paths.first);
      _message = 'Reading your receipt…';
    });
    final folder = await (await _directory()).createTemp('receipt-');
    final saved = <File>[];
    final reads = <OcrResult>[];
    for (var i = 0; i < paths.length; i++) {
      final source = File(paths[i]);
      final page = await Future.wait<Object>([
        source.copy('${folder.path}/page-${i + 1}.jpg'),
        (widget.receiptReader ?? _ocr.scanReceipt)(source),
      ]);
      saved.add(page[0] as File);
      reads.add(page[1] as OcrResult);
      if (!mounted || provider.userId != owner) return;
    }
    final local = reads.length == 1
        ? reads.single
        : OcrService.parseText(reads.map((r) => r.rawText).join('\n'));
    if (!ReceiptGate.canReview(local))
      throw const FormatException('Not a readable receipt');
    final outcome = reads.length == 1 && receiptReadyLocally(local)
        ? AiReceiptOutcome(local)
        : await (widget.receiptEnhancer ?? _ai.enhance)(local);
    if (!mounted || provider.userId != owner) return;
    final draft = prepareReceiptDraft(local, outcome.result);
    final currency = provider.currencySymbol;
    const codes = {
      'RM': 'MYR',
      r'$': 'USD',
      r'S$': 'SGD',
      '€': 'EUR',
      '£': 'GBP',
      '¥': 'JPY',
      r'A$': 'AUD',
      r'C$': 'CAD'
    };
    final mismatch = draft.currency != null &&
        draft.currency != (codes[currency] ?? currency);
    final notice = [
      if (mismatch)
        'Receipt currency differs from your account. Enter a converted amount.',
      if (outcome.message != null) outcome.message!
    ].join(' ');
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => AddTransactionScreen(
                  prefilledTitle: draft.merchant,
                  receiptLearningKey: CategoryLearningService.receiptKey(
                      draft.merchant, draft.items),
                  prefilledAmount: mismatch ? null : draft.amount,
                  prefilledCategory: draft.suggestedCategory,
                  prefilledPaymentMethod: draft.paymentMethod,
                  requireAccountSelection: true,
                  prefilledDate: draft.date,
                  prefilledReceiptImagePath: saved.first.path,
                  prefilledNote:
                      buildReceiptNote(draft, defaultCurrency: currency),
                  receiptReview: draft,
                  scanMessage: notice.isEmpty ? null : notice,
                )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          if (_photo != null)
            Opacity(
                opacity: .3, child: Image.file(_photo!, fit: BoxFit.contain)),
          SafeArea(
              child: Column(children: [
            Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                    tooltip: 'Close scanner',
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded))),
            Expanded(
                child: Center(
                    child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                            color: AppPalette.of(context)
                                .bgCard
                                .withValues(alpha: .95),
                            borderRadius: BorderRadius.circular(24)),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          if (_busy) ...[
                            const CircularProgressIndicator(strokeWidth: 2),
                            const SizedBox(height: 18)
                          ],
                          Text(_message ?? 'Ready to scan',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppPalette.of(context).textPrimary)),
                          if (!_busy) ...[
                            const SizedBox(height: 18),
                            FilledButton.icon(
                                onPressed: _capture,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Open camera')),
                            TextButton.icon(
                                onPressed: _importPdf,
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('Import PDF')),
                          ],
                        ])))),
          ])),
        ]),
      );
}
