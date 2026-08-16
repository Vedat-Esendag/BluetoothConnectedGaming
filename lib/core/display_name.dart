/// Longest display name shown for a player, in characters.
///
/// Names arrive from two untrusted places — a peer's handshake payload and a
/// BLE advertisement's local name — and both end up in a widget, so they are
/// bounded and scrubbed rather than trusted (golden rule #2).
const int maxDisplayNameLength = 24;

/// Make an arbitrary inbound value safe to render as a player or host name.
///
/// Anything that is not a usable string becomes [fallback]. Control characters
/// — including the bidirectional-override codepoints that can visually reorder
/// surrounding text, and so let one device impersonate another in a host list —
/// are stripped rather than escaped, and the result is truncated to
/// [maxDisplayNameLength].
String sanitizeDisplayName(Object? value, {required String fallback}) {
  if (value is! String) return fallback;

  final stripped = value
      // C0/C1 control characters: a newline or a NUL would break layout.
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
      // Zero-width and bidirectional-override codepoints: invisible, and able
      // to visually reorder the text around them.
      .replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '')
      .trim();
  if (stripped.isEmpty) return fallback;

  final runes = stripped.runes.toList();
  if (runes.length <= maxDisplayNameLength) return stripped;
  return String.fromCharCodes(runes.take(maxDisplayNameLength));
}
