import 'dart:async';
import 'spendly_logo.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});
  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  static const tips = [
    'Small savings today. More possibilities tomorrow.',
    'Give every ringgit a purpose.',
    'A little set aside is still a step forward.',
    'Pause before a purchase. Does it fit your priorities?',
    'Your next goal starts with one small step.',
  ];
  int index = Random().nextInt(tips.length);
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => index = (index + 1) % tips.length);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Center(
                child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SpendlyLogo(size: 112),
            const SizedBox(height: 18),
            const Text('Spendly',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            SizedBox(
                height: 80,
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    child: Text(tips[index],
                        key: ValueKey(index),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: AppPalette.of(context).textSecondary)))),
            const SizedBox(
                width: 80, child: LinearProgressIndicator(minHeight: 2)),
            const SizedBox(height: 14),
            Text('Getting your space ready',
                style: TextStyle(
                    fontSize: 11, color: AppPalette.of(context).textMuted)),
          ]),
        ))),
      );
}
