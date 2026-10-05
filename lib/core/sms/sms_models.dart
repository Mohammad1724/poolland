// ============================================================
//  Models for bank SMS messages.
//  Platform-independent and testable without Flutter.
// ============================================================

// Direction of money movement in an SMS.
enum SmsDirection {
  deposit, // Money credited to our account.
  withdraw, // Withdrawal, purchase, or payment from our account.
  unknown;

  String get label => switch (this) {
    SmsDirection.deposit => 'Deposit',
    SmsDirection.withdraw => 'Withdrawal / purchase',
    SmsDirection.unknown => 'Unknown',
  };
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
    return '${address.trim()}|$minuteBucket|$body';
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

  /// Whether this is a financial transaction that can appear in the review queue.
  bool get isTransaction => amount > 0 && direction != SmsDirection.unknown;

  /// Suggested transaction type for the ledger.
  /// Deposit → customer receipt or income; withdrawal → expense.
  String get suggestedKindLabel => switch (direction) {
    SmsDirection.deposit => 'Receive from customer',
    SmsDirection.withdraw => 'Expense',
    SmsDirection.unknown => 'Unknown',
  };
}
