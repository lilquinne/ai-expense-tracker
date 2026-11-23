// lib/screens/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  final _nameController = TextEditingController();
  String _selectedCurrency = 'RM';

  static const _currencies = ['RM', 'USD', 'EUR', 'SGD', 'GBP'];

  static const _pages = [
    _OnboardingPage(
        emoji: '📷',
        title: 'A receipt becomes a record',
        subtitle:
            'Tap Scan to open the camera straight away. Keep the receipt flat, well lit and inside the guide.'),
    _OnboardingPage(
        emoji: '🔍',
        title: 'Clear text, better results',
        subtitle:
            'Tap the receipt text to focus. Retake dark, blurry or washed-out photos before reading them.'),
    _OnboardingPage(
        emoji: '🧾',
        title: 'Review before you save',
        subtitle:
            'OCR suggests the merchant, amount and date. Check the total, choose the right category and paying account, then save once.'),
    _OnboardingPage(
        emoji: '✨',
        title: 'See where your money goes',
        subtitle:
            'Your saved receipts feed your charts and budget guide. Star favourite categories, split bills and reserve savings in jars.'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length;

    return Scaffold(
      backgroundColor: AppPalette.of(context).bgDark,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  ..._pages.map((p) => _buildPage(p)),
                  _buildSetupPage(),
                ],
              ),
            ),
            _buildBottomControls(isLastPage),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(page.emoji, style: const TextStyle(fontSize: 80)),
          const SizedBox(height: 32),
          Text(
            page.title,
            style: TextStyle(
                color: AppPalette.of(context).textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.subtitle,
            style: TextStyle(
                color: AppPalette.of(context).textSecondary,
                fontSize: 15,
                height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSetupPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👋', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 20),
          Text("Let's set up your account",
              style: TextStyle(
                  color: AppPalette.of(context).textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text("Quick setup — 30 seconds",
              style: TextStyle(
                  color: AppPalette.of(context).textMuted, fontSize: 14)),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            style: TextStyle(color: AppPalette.of(context).textPrimary),
            decoration: InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_rounded,
                  color: AppPalette.of(context).textMuted),
            ),
          ),
          const SizedBox(height: 24),
          Text('Currency',
              style: TextStyle(
                  color: AppPalette.of(context).textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: _currencies.map((c) {
              final isSelected = _selectedCurrency == c;
              return GestureDetector(
                onTap: () => setState(() => _selectedCurrency = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha: 0.15)
                        : AppPalette.of(context).bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : AppPalette.of(context).border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(c,
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.primary
                            : AppPalette.of(context).textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.normal,
                      )),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(bool isLastPage) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Page dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length + 1, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _currentPage ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _currentPage
                      ? AppTheme.primary
                      : AppPalette.of(context).textMuted,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (_currentPage > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _controller.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2D2D55)),
                      foregroundColor: AppPalette.of(context).textSecondary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Back'),
                  ),
                ),
              if (_currentPage > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isLastPage ? _finish : _next,
                  child: Text(isLastPage ? "Let's Go! 🚀" : 'Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    await prefs.setString(
        'userName',
        _nameController.text.trim().isEmpty
            ? 'User'
            : _nameController.text.trim());
    await prefs.setString('currencySymbol', _selectedCurrency);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }
}

class _OnboardingPage {
  final String emoji;
  final String title;
  final String subtitle;
  const _OnboardingPage(
      {required this.emoji, required this.title, required this.subtitle});
}
