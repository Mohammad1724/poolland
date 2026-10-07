import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_lock.dart';
import '../../core/biometrics.dart';
import '../../core/localization.dart';
import '../../data/repository.dart';
import 'pin_pad.dart';

/// Covers the app with [LockScreen] while the PIN lock is engaged.
///
/// Mount this above the Navigator (via `MaterialApp.builder`), not inside
/// `home`, or any pushed route will be drawn on top of the lock.
///
/// The app underneath stays mounted and merely stops being painted, so
/// unlocking puts the user back on exactly the screen — and the half-filled
/// form — they left.
///
/// The gate only re-locks on resume after the app has been in the background
/// for [_backgroundGrace]. Without that grace period the lock would fire
/// every time a system picker takes over the screen — choosing a backup file
/// or a notification tone both background the activity — and the user would
/// be asked for their PIN in the middle of a task they just started.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  static const Duration _backgroundGrace = Duration(seconds: 60);

  bool _unlocked = true;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Only start locked if a PIN already exists. Turning the lock on later,
    // from Settings, must not throw the user out of the session they are in.
    _unlocked = !context.read<AppRepository>().hasAppLock;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      return;
    }
    // Ignore `inactive`: it fires for a pulled-down notification shade and
    // for the app switcher, neither of which means the phone changed hands.
    if (state != AppLifecycleState.resumed) return;

    final leftAt = _backgroundedAt;
    _backgroundedAt = null;
    final awayLongEnough =
        leftAt != null &&
        DateTime.now().difference(leftAt) >= _backgroundGrace;
    if (awayLongEnough && _unlocked) {
      setState(() => _unlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.watch<AppRepository>().hasAppLock && !_unlocked;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Always child 0, locked or not, so the Navigator below keeps its
        // element and never rebuilds its route stack from scratch.
        Visibility(
          visible: !locked,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: widget.child,
        ),
        if (locked)
          LockScreen(onUnlocked: () => setState(() => _unlocked = true)),
      ],
    );
  }
}

/// Full-screen PIN prompt shown by [AppLockGate].
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entry = '';
  bool _wrong = false;
  bool _biometricsAvailable = false;
  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    _offerBiometrics();
  }

  /// Show the fingerprint sheet straight away when it is switched on, so the
  /// common case is one touch and no typing.
  Future<void> _offerBiometrics() async {
    if (!context.read<AppRepository>().biometricUnlock) return;
    if (!await Biometrics.isAvailable()) return;
    if (!mounted) return;
    setState(() => _biometricsAvailable = true);
    await _runBiometricPrompt();
  }

  Future<void> _runBiometricPrompt() async {
    if (_promptOpen) return;
    setState(() => _promptOpen = true);
    final outcome = await Biometrics.prompt();
    if (!mounted) return;
    setState(() => _promptOpen = false);

    if (outcome == BiometricOutcome.success) {
      widget.onUnlocked();
    } else if (outcome == BiometricOutcome.failed) {
      // Hide the shortcut instead of nagging: the PIN still works, and a
      // sensor that just refused is unlikely to do better on a retry.
      setState(() => _biometricsAvailable = false);
    }
    // BiometricOutcome.canceled: they would rather type the PIN, so the
    // keypad is left exactly as it was.
  }

  void _append(String digit) {
    if (_entry.length >= AppLock.maxPinLength) return;
    setState(() {
      _entry += digit;
      _wrong = false;
    });
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() {
      _entry = _entry.substring(0, _entry.length - 1);
      _wrong = false;
    });
  }

  void _submit() {
    if (context.read<AppRepository>().verifyPin(_entry)) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _entry = '';
      _wrong = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = _entry.length >= AppLock.minPinLength;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 44,
                  color: scheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  'Poolland is locked'.tr,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your PIN to continue'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 26),
                PinDots(
                  length: math.max(AppLock.minPinLength, _entry.length),
                  filled: _entry.length,
                  error: _wrong,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 20,
                  child: _wrong
                      ? Text(
                          'Wrong PIN. Try again.'.tr,
                          style: TextStyle(fontSize: 12, color: scheme.error),
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                PinPad(
                  onDigit: _append,
                  onBackspace: _backspace,
                  enabled: !_promptOpen,
                  leading: _biometricsAvailable
                      ? IconButton(
                          onPressed: _promptOpen ? null : _runBiometricPrompt,
                          tooltip: 'Use fingerprint'.tr,
                          icon: const Icon(Icons.fingerprint_rounded, size: 28),
                        )
                      : null,
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canSubmit ? _submit : null,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: Text('Unlock'.tr),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
