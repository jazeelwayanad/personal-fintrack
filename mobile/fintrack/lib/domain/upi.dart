class UpiQr {
  final String payload;
  final String vpa;
  final String? name;
  final int? fixedPaise;
  final bool preservePayload;

  const UpiQr._(
    this.payload,
    this.vpa,
    this.name,
    this.fixedPaise,
    this.preservePayload,
  );

  static int? parsePaise(String value) {
    if (!RegExp(r'^\d{1,11}(\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final paise =
        int.parse(parts.first) * 100 +
        (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
    return paise > 0 && paise <= 1000000000000 ? paise : null;
  }

  factory UpiQr.parse(String input) {
    final payload = input.trim();
    const invalid = FormatException('Enter a supported INR UPI payment QR.');
    if (payload.length > 4096 ||
        !payload.startsWith('upi://pay?') ||
        !RegExp(r'^[!-~]+$').hasMatch(payload) ||
        RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(payload)) {
      throw invalid;
    }
    final uri = Uri.tryParse(payload);
    if (uri == null ||
        uri.authority != 'pay' ||
        uri.path.isNotEmpty ||
        uri.hasFragment) {
      throw invalid;
    }
    final params = <String, String>{};
    for (final field in payload.substring('upi://pay?'.length).split('&')) {
      final separator = field.indexOf('=');
      if (separator < 1) throw invalid;
      final key = Uri.decodeQueryComponent(
        field.substring(0, separator),
      ).toLowerCase();
      final value = Uri.decodeQueryComponent(field.substring(separator + 1));
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(key) ||
          params.containsKey(key) ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw invalid;
      }
      params[key] = value;
    }
    final vpa = params['pa'] ?? '';
    if (vpa.length > 255 ||
        !RegExp(r'^[a-zA-Z0-9._+\-]+@[a-zA-Z0-9.\-]+$').hasMatch(vpa) ||
        (params['cu'] != null && params['cu'] != 'INR') ||
        (params['pn']?.length ?? 0) > 120) {
      throw invalid;
    }
    final amount = params['am'];
    final paise = amount == null ? null : parsePaise(amount);
    if (amount != null && paise == null) throw invalid;
    final preserve = params.keys.any(
      (key) => !const {'pa', 'pn', 'cu', 'tn'}.contains(key),
    );
    return UpiQr._(payload, vpa, params['pn'], paise, preserve);
  }

  String forHandoff(int paise) {
    if (fixedPaise != null || preservePayload) return payload;
    final rupees = paise ~/ 100;
    final minor = (paise % 100).toString().padLeft(2, '0');
    return '$payload&am=$rupees.$minor';
  }
}
