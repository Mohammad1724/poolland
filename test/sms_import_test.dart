import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/sms/sms_models.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';

/// These tests cover both the permission-gated inbox hand-off and the pasted
/// message fallback, along with the outcomes the review UI explains.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_sms_import');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.reload();
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  const bankSms =
      'بانک ملت\n'
      'واریز مبلغ 1,500,000 ریال\n'
      'کارت 6104********1234';

  test('a pasted bank SMS enters the review queue', () {
    expect(repo.importSmsText(bankSms), SmsImportResult.added);
    expect(repo.smsSuggestions, hasLength(1));

    final parsed = repo.smsSuggestions.single;
    expect(parsed.bankName, 'Mellat Bank');
    expect(parsed.direction, SmsDirection.deposit);
    expect(parsed.amount, greaterThan(0));
    expect(parsed.isTransaction, isTrue);
  });

  test('the same text pasted twice is reported as a duplicate', () {
    expect(repo.importSmsText(bankSms), SmsImportResult.added);
    expect(repo.importSmsText(bankSms), SmsImportResult.duplicate);
    expect(repo.smsSuggestions, hasLength(1));
  });

  test(
    'inbox sync queues recognized messages once and ignores other SMS',
    () async {
      final bankMessage = SmsMessage(
        id: 'inbox-1',
        address: 'BANKMELAT',
        body: bankSms,
        date: DateTime(2026, 10, 17, 12),
      );
      final otp = SmsMessage(
        id: 'inbox-2',
        address: 'BANKMELAT',
        body: 'رمز پویا: 123456',
        date: DateTime(2026, 10, 17, 12, 1),
      );
      final unknownBank = SmsMessage(
        id: 'inbox-3',
        address: 'UNKNOWN',
        body: 'واریز مبلغ 250,000 ریال',
        date: DateTime(2026, 10, 17, 12, 2),
      );

      expect(repo.importInboxSms([bankMessage, otp, unknownBank]), 1);
      expect(repo.smsSuggestions, hasLength(1));
      expect(repo.smsSuggestions.single.message.id, 'inbox-1');
      expect(repo.smsSuggestions.single.manual, isFalse);
      expect(repo.importInboxSms([bankMessage]), 0);

      await repo.rejectSms(repo.smsSuggestions.single);
      expect(
        repo.importInboxSms([bankMessage]),
        0,
        reason: 'a reviewed inbox message must not reappear on the next sync',
      );
    },
  );

  test('a message without a matching bank rule is still queued and recordable',
      () async {
    // No built-in rule matches this sender-less text, but it has a clear
    // amount and direction, so the review sheet can still record it. The
    // manual mark is what lets approveSms accept it without weakening the
    // rule check for inbox messages.
    expect(
      repo.importSmsText('واریز 250,000 ریال به حساب'),
      SmsImportResult.added,
    );
    final parsed = repo.smsSuggestions.single;
    expect(parsed.bankName, isNull);
    expect(parsed.isPotentialUnrecognizedTransaction, isTrue);
    expect(parsed.manual, isTrue);

    final txn = await repo.approveSms(parsed, scope: TxnScope.business);
    expect(txn, isNotNull);
    expect(repo.smsSuggestions, isEmpty);
  });

  test('unrelated or empty text is rejected', () {
    expect(repo.importSmsText('سلام، فردا می‌بینمت'), SmsImportResult.notRecognized);
    expect(repo.importSmsText('   '), SmsImportResult.notRecognized);
    expect(repo.smsSuggestions, isEmpty);
  });

  test('a rejected SMS can be restored from history back to the review queue',
      () async {
    expect(repo.importSmsText(bankSms), SmsImportResult.added);
    final parsed = repo.smsSuggestions.single;
    await repo.rejectSms(parsed);
    expect(repo.smsSuggestions, isEmpty);
    expect(repo.smsHistory.single.wasRejected, isTrue);

    await repo.restoreRejectedSms(repo.smsHistory.single);
    expect(repo.smsHistory, isEmpty);
    expect(repo.smsSuggestions, hasLength(1));
    expect(repo.smsSuggestions.single.bankName, 'Mellat Bank');
  });
}
