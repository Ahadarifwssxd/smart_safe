import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/services/sim_sos_service.dart';

void main() {
  group('SimSosResult.hasError', () {
    test('is true only when an error is set', () {
      expect(SimSosResult(error: 'boom').hasError, isTrue);
      expect(SimSosResult(smsSent: 1).hasError, isFalse);
    });
  });

  group('SimSosResult.summaryMessage — error', () {
    test('shows the error prefixed with a warning', () {
      expect(
        SimSosResult(error: 'No SIM').summaryMessage,
        '⚠️ No SIM',
      );
    });
  });

  group('SimSosResult.summaryMessage — sent', () {
    test('lists each channel that was delivered', () {
      final msg = SimSosResult(
        callsMade: 1,
        smsSent: 3,
        whatsappSent: 2,
        emailsSent: 1,
      ).summaryMessage;
      expect(msg, contains('SOS sent'));
      expect(msg, contains('1 call'));
      expect(msg, contains('3 SMS'));
      expect(msg, contains('2 WhatsApp'));
      expect(msg, contains('1 email'));
    });

    test('warns when nothing was sent', () {
      expect(
        SimSosResult().summaryMessage,
        contains('Nothing was sent'),
      );
    });
  });

  group('SimSosResult.summaryMessage — cancelled', () {
    test('marks the user safe when no channels were used', () {
      final msg = SimSosResult(cancelled: true).summaryMessage;
      expect(msg, contains('cancelled'));
      expect(msg, contains('safe'));
    });

    test('lists notified contacts on cancel', () {
      final msg =
          SimSosResult(cancelled: true, smsSent: 2).summaryMessage;
      expect(msg, contains('cancelled'));
      expect(msg, contains('2 SMS'));
    });
  });
}
