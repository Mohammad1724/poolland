import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/localization.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../forms/transaction_edit_page.dart';
import 'widgets.dart';

/// The swipe-reveal actions every transaction row offers:
/// edit, duplicate, and delete (behind a confirmation).
///
/// Shared by the customer statement, the dashboard "recent" list and the
/// personal page so a row behaves identically everywhere.
List<SwipeAction> txnSwipeActions(
  BuildContext context,
  Txn txn,
  AppRepository repo,
) {
  return [
    SwipeAction(
      icon: Icons.edit_rounded,
      label: 'Edit',
      color: Theme.of(context).colorScheme.primary,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionEditPage(existing: txn),
          ),
        );
      },
    ),
    SwipeAction(
      icon: Icons.copy_all_rounded,
      label: 'Duplicate',
      color: const Color(0xFF2563EB),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionEditPage(duplicateOf: txn),
          ),
        );
      },
    ),
    SwipeAction(
      icon: Icons.delete_outline_rounded,
      label: 'Delete',
      color: const Color(0xFFE11D48),
      onTap: () async {
        Haptics.tap();
        final ok = await confirmDialog(
          context,
          title: 'Delete transaction'.tr,
          message: 'Delete this transaction?'.tr,
          danger: true,
          okLabel: 'Delete'.tr,
        );
        if (!ok || !context.mounted) return;
        await repo.deleteTxn(txn.id);
        if (!context.mounted) return;
        showSnack(context, 'Transaction deleted');
      },
    ),
  ];
}
