import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';

class QuickTutorialScreen extends StatefulWidget {
  const QuickTutorialScreen({super.key, required this.userId});
  final String userId;
  @override
  State<QuickTutorialScreen> createState() => _QuickTutorialScreenState();
}

class _QuickTutorialScreenState extends State<QuickTutorialScreen> {
  int step = 0;
  static const steps = <(IconData, String, String)>[
    (
      Icons.document_scanner_outlined,
      '1. Start with a receipt',
      'Tap the glowing Scan button at the bottom of Home. The camera opens directly. You can also use the camera icon beside a transaction note.'
    ),
    (
      Icons.center_focus_strong,
      '2. Make the text clear',
      'Keep the whole receipt in the guide. Tap the text to focus, avoid glare and hold steady. If the photo looks dark or blurry, use Retake.'
    ),
    (
      Icons.fact_check_outlined,
      '3. Review the OCR result',
      'Check the merchant, date and final total. OCR can make mistakes. Correct anything that looks wrong before continuing.'
    ),
    (
      Icons.account_balance_wallet_outlined,
      '4. Choose how it was paid',
      'Choose a category and the paying account. Use Split for shared bills. The keypad supports calculations: tap = for the total, then Done to save.'
    ),
    (
      Icons.insights_outlined,
      '5. Follow your progress',
      'Analytics summarises saved spending. More contains Budget Tracker and other tools. Your daily budget guide is also available in Notifications.'
    ),
  ];
  Future<void> finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quick_tutorial_v1:${widget.userId}', true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Quick tutorial'), actions: [
          TextButton(onPressed: finish, child: const Text('Skip'))
        ]),
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  LinearProgressIndicator(
                      value: (step + 1) / steps.length,
                      borderRadius: BorderRadius.circular(8)),
                  Expanded(
                      child: SingleChildScrollView(
                          child: Column(children: [
                    const SizedBox(height: 48),
                    Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(28)),
                        child: Icon(steps[step].$1,
                            size: 64, color: AppTheme.primary)),
                    const SizedBox(height: 28),
                    Text(steps[step].$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 18),
                    Text(steps[step].$3,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.7)),
                  ]))),
                  Row(children: [
                    if (step > 0)
                      TextButton(
                          onPressed: () => setState(() => step--),
                          child: const Text('Back')),
                    const Spacer(),
                    FilledButton(
                        onPressed: step == steps.length - 1
                            ? finish
                            : () => setState(() => step++),
                        child: Text(
                            step == steps.length - 1 ? 'Get started' : 'Next'))
                  ]),
                ]))),
      );
}
