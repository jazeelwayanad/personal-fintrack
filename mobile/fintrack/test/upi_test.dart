import 'package:fintrack/domain/upi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps signed and fixed QR payloads exactly as scanned', () {
    const payload = 'upi://pay?pa=biller%40bank&pn=Water&am=10.20&sign=abc%2B';
    final qr = UpiQr.parse(payload);
    expect(qr.vpa, 'biller@bank');
    expect(qr.fixedPaise, 1020);
    expect(qr.forHandoff(999), payload);
    const open = 'upi://pay?pa=biller%40bank&tr=paid-123';
    expect(UpiQr.parse(open).forHandoff(999), open);
  });

  test('adds exact paise to an open link and refuses ambiguous parameters', () {
    final qr = UpiQr.parse('upi://pay?pa=biller@bank&cu=INR');
    expect(qr.forHandoff(905), 'upi://pay?pa=biller@bank&cu=INR&am=9.05');
    expect(
      () => UpiQr.parse('upi://pay?pa=biller@bank&p%61=other@bank'),
      throwsFormatException,
    );
    expect(
      () => UpiQr.parse('upi://pay?pa=biller@bank&am=1e3'),
      throwsFormatException,
    );
    expect(
      () => UpiQr.parse('upi://pay?pa=biller@bank&cu=USD'),
      throwsFormatException,
    );
    expect(
      () => UpiQr.parse('upi://pay?pa=biller@bank#extra'),
      throwsFormatException,
    );
  });
}
