import 'package:flutter/material.dart';

/// Waits for the dialog's exit animation before returning to callers that own
/// resources such as text controllers used by the dialog.
Future<T?> showSettledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}
