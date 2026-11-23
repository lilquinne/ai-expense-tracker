import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:expense_tracker/screens/scan_receipt_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:expense_tracker/screens/receipt_camera_screen.dart';

void main() {
  testWidgets(
      'scan opens one camera directly and cancellation returns to the caller',
      (tester) async {
    const cameraChannel = MethodChannel('plugins.flutter.io/camera');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, (_) async => []);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, null));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ScanReceiptScreen())),
                    child: const Text('Open scanner'))))));
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptCameraScreen), findsOneWidget);
    expect(find.byTooltip('Choose photo'), findsOneWidget);
    expect(find.byTooltip('Flash'), findsOneWidget);
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Gallery'), findsNothing);
    expect(find.text('Manual'), findsNothing);
    expect(find.text('Auto'), findsNothing);
    await tester.tap(find.byTooltip('Close scanner').last);
    await tester.pumpAndSettle();
    expect(find.text('Open scanner'), findsOneWidget);
    expect(find.byType(ScanReceiptScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('unreadable, dark and low-resolution photos receive retake guidance',
      () {
    expect(receiptPhotoWarning([1, 2, 3]), contains('retake'));
    final small = img.Image(width: 200, height: 300);
    expect(receiptPhotoWarning(img.encodeJpg(small)), contains('small'));
    final dark = img.Image(width: 800, height: 1000);
    expect(receiptPhotoWarning(img.encodeJpg(dark)), contains('dark'));
  });
  test('sharp high-contrast text-like edges pass the photo hint', () {
    final image = img.Image(width: 800, height: 1000);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final text = y % 32 < 5 && x > 100 && x < 700;
        final value = text ? 30 : 225;
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    expect(receiptPhotoWarning(img.encodeJpg(image, quality: 95)), isNull);
  });
}
