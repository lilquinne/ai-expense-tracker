import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A conservative photo-quality hint, not a guarantee of OCR accuracy.
String? receiptPhotoWarning(List<int> bytes) {
  img.Image? source;
  try {
    source = img.decodeImage(Uint8List.fromList(bytes));
  } catch (_) {
    return 'This photo could not be opened. Please retake it.';
  }
  if (source == null)
    return 'This photo could not be opened. Please retake it.';
  if (source.width < 600 || source.height < 600)
    return 'The photo is small. Move closer and retake it for clearer text.';
  final image = img.copyResize(source, width: 400);
  double brightness = 0, sum = 0, squares = 0;
  int count = 0;
  double gray(int x, int y) {
    final p = image.getPixel(x, y);
    return .299 * p.r + .587 * p.g + .114 * p.b;
  }

  for (var y = image.height ~/ 6; y < image.height * 5 ~/ 6; y++) {
    for (var x = image.width ~/ 6; x < image.width * 5 ~/ 6; x++) {
      final value = gray(x, y);
      final lap = gray(x - 1, y) +
          gray(x + 1, y) +
          gray(x, y - 1) +
          gray(x, y + 1) -
          4 * value;
      brightness += value;
      sum += lap;
      squares += lap * lap;
      count++;
    }
  }
  if (brightness / count > 247)
    return 'The photo looks washed out. Reduce glare and retake it.';
  if (brightness / count < 40)
    return 'This photo looks dark. Add light and avoid shadows on the receipt.';
  if (squares / count - (sum / count) * (sum / count) < 35)
    return 'The text may be blurry or too far away. Hold steady and retake it.';
  return null;
}

class ReceiptCapture {
  const ReceiptCapture(this.path, this.product);
  final String path;
  final bool product;
}

class ReceiptCameraScreen extends StatefulWidget {
  const ReceiptCameraScreen(
      {super.key, this.productMode = false, this.guidance});
  final bool productMode;
  final String? guidance;
  @override
  State<ReceiptCameraScreen> createState() => _ReceiptCameraScreenState();
}

class _ReceiptCameraScreenState extends State<ReceiptCameraScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  String? error, photo, warning;
  bool busy = false, flash = false;
  int generation = 0;
  late bool product;
  @override
  void initState() {
    super.initState();
    product = widget.productMode;
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  Future<void> start() async {
    final request = ++generation;
    try {
      final previous = camera;
      camera = null;
      if (previous != null) await previous.dispose();
      final cameras = await availableCameras();
      if (!mounted || request != generation) return;
      if (cameras.isEmpty) throw StateError('No camera');
      final device = cameras
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          cameras.first;
      final controller = CameraController(
          device, product ? ResolutionPreset.veryHigh : ResolutionPreset.max,
          enableAudio: false);
      camera = controller;
      await controller.initialize();
      if (!mounted || request != generation) {
        await controller.dispose();
        return;
      }
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setFocusPoint(const Offset(.5, .5));
        await controller.setExposurePoint(const Offset(.5, .5));
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (mounted)
        setState(() {
          error = null;
          flash = false;
        });
    } catch (_) {
      if (mounted && request == generation)
        setState(() => error =
            'Camera unavailable. Allow camera access in phone settings, then try again.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      generation++;
      camera?.dispose();
      camera = null;
    }
    if (state == AppLifecycleState.resumed && photo == null) start();
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    camera?.dispose();
    super.dispose();
  }

  Future<void> capture() async {
    final controller = camera;
    if (busy || controller == null || !controller.value.isInitialized) return;
    setState(() => busy = true);
    try {
      final image = await controller.takePicture();
      final hint = product
          ? null
          : await compute(receiptPhotoWarning, await image.readAsBytes());
      if (!mounted) return;
      if (hint == null) {
        Navigator.pop(context, ReceiptCapture(image.path, product));
        return;
      }
      setState(() {
        photo = image.path;
        warning = hint;
      });
    } catch (_) {
      if (mounted)
        setState(
            () => error = 'Could not capture the photo. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseGallery() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final image = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (mounted && image != null)
        Navigator.pop(context, ReceiptCapture(image.path, product));
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not open this photo. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggleFlash() async {
    final controller = camera;
    if (controller == null || !controller.value.isInitialized || busy) return;
    try {
      await controller.setFlashMode(flash ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => flash = !flash);
    } catch (_) {}
  }

  Widget livePreview() {
    final controller = camera!;
    final size = controller.value.previewSize!;
    final width = size.height, height = size.width;
    return ClipRect(
        child: SizedBox.expand(
            child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                    width: width,
                    height: height,
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (tap) async {
                          try {
                            final point = Offset(
                                (tap.localPosition.dx / width).clamp(0.0, 1.0),
                                (tap.localPosition.dy / height)
                                    .clamp(0.0, 1.0));
                            await controller.setFocusMode(FocusMode.auto);
                            await controller.setFocusPoint(point);
                            await controller.setExposurePoint(point);
                          } catch (_) {}
                        },
                        child: CameraPreview(controller))))));
  }

  Widget modeButton(bool mode, String label, IconData icon) => Expanded(
      child: Material(
          color: product == mode ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: busy || photo != null
                  ? null
                  : () {
                      if (mode == product) return;
                      setState(() => product = mode);
                      start();
                    },
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            size: 15,
                            color:
                                product == mode ? Colors.black : Colors.white),
                        const SizedBox(width: 6),
                        Flexible(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: product == mode
                                        ? Colors.black
                                        : Colors.white))),
                      ])))));

  Widget roundControl(String label, IconData icon, VoidCallback? action) =>
      IconButton.filledTonal(
          tooltip: label,
          onPressed: action,
          style: IconButton.styleFrom(
              backgroundColor: Colors.black45, foregroundColor: Colors.white),
          icon: Icon(icon, size: 23));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          if (photo != null)
            Image.file(File(photo!), fit: BoxFit.contain)
          else if (error != null)
            Center(
                child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white))))
          else if (camera?.value.isInitialized == true)
            livePreview()
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (photo == null && error == null)
            const IgnorePointer(
                child: Align(
                    alignment: Alignment(0, -.22),
                    child: FractionallySizedBox(
                        widthFactor: .84,
                        heightFactor: .55,
                        child: CustomPaint(painter: ReceiptCornerGuide())))),
          IgnorePointer(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                Colors.black38,
                Colors.transparent,
                Colors.transparent,
                Colors.black87
              ],
                          stops: const [
                0,
                .18,
                .6,
                1
              ])))),
          SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(children: [
                    Align(
                        alignment: Alignment.topLeft,
                        child: roundControl(
                            'Close scanner',
                            Icons.close_rounded,
                            busy ? null : () => Navigator.pop(context))),
                    const Spacer(),
                    if (widget.guidance != null || warning != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(warning ?? widget.guidance!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.5))),
                    if (photo == null) ...[
                      Text(
                          product
                              ? 'Frame one product'
                              : 'Keep the whole receipt in frame · Tap to focus',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      const SizedBox(height: 16),
                      SizedBox(
                          width: 228,
                          child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(28)),
                              child: Row(children: [
                                modeButton(false, 'Receipt',
                                    Icons.receipt_long_outlined),
                                modeButton(true, 'Product',
                                    Icons.shopping_bag_outlined),
                              ]))),
                      const SizedBox(height: 18),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            roundControl(
                                'Flash',
                                flash
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                busy ? null : toggleFlash),
                            Semantics(
                                label: 'Capture photo',
                                button: true,
                                child: SizedBox(
                                    width: 80,
                                    height: 80,
                                    child: OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : error != null
                                                ? () {
                                                    setState(
                                                        () => error = null);
                                                    start();
                                                  }
                                                : camera?.value.isInitialized ==
                                                        true
                                                    ? capture
                                                    : null,
                                        style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.all(5),
                                            shape: const CircleBorder(),
                                            side: const BorderSide(
                                                color: Colors.white, width: 2)),
                                        child: Container(
                                            decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle),
                                            alignment: Alignment.center,
                                            child: busy
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                                : error != null
                                                    ? const Icon(Icons.refresh,
                                                        color: Colors.black)
                                                    : null)))),
                            roundControl(
                                'Choose photo',
                                Icons.photo_library_outlined,
                                busy ? null : chooseGallery),
                          ]),
                    ] else
                      Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: () => setState(() {
                                      photo = null;
                                      warning = null;
                                    }),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                        color: Colors.white70)),
                                child: const Text('Retake'))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: FilledButton(
                                onPressed: () => Navigator.pop(
                                    context, ReceiptCapture(photo!, product)),
                                child: const Text('Use photo'))),
                      ]),
                  ]))),
        ]),
      );
}

class ReceiptCornerGuide extends CustomPainter {
  const ReceiptCornerGuide();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const r = 22.0, arm = 44.0;
    final path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(arm, 0)
      ..moveTo(size.width - arm, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, arm)
      ..moveTo(size.width, size.height - arm)
      ..lineTo(size.width, size.height - r)
      ..quadraticBezierTo(size.width, size.height, size.width - r, size.height)
      ..lineTo(size.width - arm, size.height)
      ..moveTo(arm, size.height)
      ..lineTo(r, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - r)
      ..lineTo(0, size.height - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ReceiptCornerGuide oldDelegate) => false;
}
