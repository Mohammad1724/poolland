import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep portrait and landscape available. The shell already adapts to wide
  // layouts, so forcing portrait unnecessarily excluded tablets and landscape
  // use on phones.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  runApp(const VpnLedgerApp());
}
