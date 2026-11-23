/// Show domain validation messages, keeping database/platform details out of UI.
String operationMessage(Object error, String fallback) {
  if (error is StateError) return error.message;
  if (error is ArgumentError && error.message is String)
    return error.message as String;
  return fallback;
}
