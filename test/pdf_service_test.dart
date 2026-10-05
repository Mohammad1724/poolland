import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/pdf_service.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('poolland_pdf_test');
    store = await LocalStore.openAt(tempDir.path);
    repo = AppRepository(store: store);
    await repo.loadDemoData();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('Period report generates for Persian personal scope and English business scope', () async {
    final from = DateTime(2000);
    final to = DateTime(2100);

    await repo.updateSettings(repo.settings.copyWith(languageCode: 'fa'));
    final personalPdf = await PdfService.buildReport(
      repo: repo,
      from: from,
      to: to,
      scope: TxnScope.personal,
    );
    expect(latin1.decode(personalPdf.take(5).toList()), '%PDF-');

    final customer = repo.customers.first;
    final statementPdf = await PdfService.buildCustomerStatement(
      repo: repo,
      customer: customer,
      from: from,
      to: to,
    );
    expect(latin1.decode(statementPdf.take(5).toList()), '%PDF-');

    await repo.updateSettings(repo.settings.copyWith(languageCode: 'en'));
    final businessPdf = await PdfService.buildReport(
      repo: repo,
      from: from,
      to: to,
      scope: TxnScope.business,
    );
    expect(latin1.decode(businessPdf.take(5).toList()), '%PDF-');
  });
}
