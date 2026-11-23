import 'package:flutter/material.dart';

class SpendlyLogo extends StatelessWidget {
  const SpendlyLogo({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/spendly-pocket.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'Spendly pocket logo',
      );
}
