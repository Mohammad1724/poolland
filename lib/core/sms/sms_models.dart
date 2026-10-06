import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../localization.dart';

// ============================================================
//  Models for bank SMS messages.
//  Platform-independent and testable without Flutter.
// ============================================================

/// Compact, stable key for persisting SMS review state without storing the
/// full message text in Hive keys.
String smsKeyDigest(String rawKey) =>
    'v2:${sha256.convert(utf8.encode(rawKey))}';

// Direction of money movement in an SMS.
enum SmsDirection {
  deposit, // Money credited to our account.
  withdraw, // Withdrawal, purchase, or payment from our account.
  unknown;

  String get label => switch (this) {
    SmsDirection.deposit => 'Deposit',
    SmsDirection.withdraw => 'Withdrawal / purchase',
    SmsDirection.unknown => 'Unknown',
  }.tr;
}

/// A raw SMS message read from the device (Android).
class SmsMessage {
  final String id;
  final String address; // Sender ID (for example, BANKMELAT) or phone number.
  final String body;
  final DateTime date;

  const SmsMessage({
    required this.id,
    required this.address,
    required this.body,
    required this.date,
  });

  /// Unique key used to identify duplicate messages.
  ///
  /// Important: this key is based on message content, not its SMS ID,
  /// because a message may be received twice (once from the receiver and once from the inbox)
  /// with different IDs.
  String get key {
    final minuteBucket = date.millisecondsSinceEpoch ~/ 60000;
    final rawKey = '${address.trim()}|$minuteBucket|$body';
    return smsKeyDigest(rawKey);
  }

  factory SmsMessage.fromMap(Map<dynamic, dynamic> map) => SmsMessage(
    id: '${map['id'] ?? ''}',
    address: '${map['address'] ?? ''}',
    body: '${map['body'] ?? ''}',
    date: DateTime.fromMillisecondsSinceEpoch(
      (map['date'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'address': address,
    'body': body,
    'date': date.millisecondsSinceEpoch,
  };
}

/// A locally stored record of an SMS that the user reviewed.
/// History stays out of the app's explicit JSON export/restore format.
class SmsHistoryEntry {
  static const String approvedStatus = 'approved';
  static const String rejectedStatus = 'rejected';

  final String key;
  final SmsMessage message;
  final String status;
  final String? bankName;
  final double amount;
  final String currency;
  final SmsDirection direction;
  final DateTime reviewedAt;
  final String? transactionId;

  const SmsHistoryEntry({
    required this.key,
    required this.message,
    required this.status,
    this.bankName,
    this.amount = 0,
    this.currency = 'IRT',
    this.direction = SmsDirection.unknown,
    required this.reviewedAt,
    this.transactionId,
  });

  bool get wasRecorded => status == approvedStatus;
  bool get wasRejected => status == rejectedStatus;

  Map<String, dynamic> toMap() => {
    'key': key,
    'status': status,
    'message': message.toMap(),
    'bankName': bankName,
    'amount': amount,
    'currency': currency,
    'direction': direction.name,
    'at': reviewedAt.millisecondsSinceEpoch,
    'transactionId': transactionId,
  };

  factory SmsHistoryEntry.fromMap(Map map) {
    final rawMessage = map['message'];
    if (rawMessage is! Map) {
      throw const FormatException('SMS review record has no message.');
    }
    final directionName = '${map['direction'] ?? SmsDirection.unknown.name}';
    return SmsHistoryEntry(
      key: '${map['key'] ?? ''}',
      status: '${map['status'] ?? ''}',
      message: SmsMessage.fromMap(Map<dynamic, dynamic>.from(rawMessage)),
      bankName: map['bankName'] as String?,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: '${map['currency'] ?? 'IRT'}',
      direction: SmsDirection.values.firstWhere(
        (value) => value.name == directionName,
        orElse: () => SmsDirection.unknown,
      ),
      reviewedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      transactionId: map['transactionId'] as String?,
    );
  }
}

/// Result of parsing an SMS message.
class ParsedSms {
  final SmsMessage message;

  /// Bank name, if identified.
  final String? bankName;

  /// Amount in Tomans (converted if the SMS used Rials).
  final double amount;

  /// Currency of the amount (usually IRT).
  final String currency;

  final SmsDirection direction;

  /// Masked card number (for example, 6104********1234).
  final String? cardMask;

  /// Card digits used to match the message to a customer.
  final String cardDigits;

  /// Balance reported in the SMS (in Tomans).
  final double? balance;

  /// Tracking or reference number, if present.
  final String? reference;

  /// Is the parsing result sufficiently reliable?
  final bool confident;

  /// Short explanation of how the message was interpreted.
  final String note;

  const ParsedSms({
    required this.message,
    this.bankName,
    this.amount = 0,
    this.currency = 'IRT',
    this.direction = SmsDirection.unknown,
    this.cardMask,
    this.cardDigits = '',
    this.balance,
    this.reference,
    this.confident = false,
    this.note = '',
  });

  String get key => message.key;

  /// Whether this is a recognized bank/payment-provider transaction that can
  /// appear in the review queue. Merely containing a payment keyword and amount
  /// is not enough: a built-in or user-defined sender/body rule must match.
  bool get isTransaction =>
      bankName != null && amount > 0 && direction != SmsDirection.unknown;

  /// Message has transaction-like direction and amount but no active rule.
  bool get isPotentialUnrecognizedTransaction =>
      bankName == null && amount > 0 && direction != SmsDirection.unknown;

  /// Suggested transaction type for the ledger.
  /// Deposit → customer receipt or income; withdrawal → expense.
  String get suggestedKindLabel => switch (direction) {
    SmsDirection.deposit => 'Receive from customer',
    SmsDirection.withdraw => 'Expense',
    SmsDirection.unknown => 'Unknown',
  }.tr;
}
