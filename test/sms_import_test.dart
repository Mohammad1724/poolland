import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/sms/sms_models.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';

/// The `safe` Android build cannot read the inbox, so the review queue is fed
/// by pasted messages instead. These tests cover the parser hand-off and the
/// three outcomes the UI explains.
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
}
