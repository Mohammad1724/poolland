import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../data/repository.dart';
import 'pin_pad.dart';

/// What the user came here to do. Each mode is a different sequence of steps.
enum PinSetupMode {
  /// No PIN yet: choose one, then confirm it.
  create,

  /// A PIN exists: prove it, choose a new one, then confirm it.
  change,

  /// A PIN exists: prove it, then switch the lock off.
  remove,
}

/// Collects a PIN one step at a time and applies the change.
///
/// Pops with `true` when the lock was actually changed, and with nothing when
/// the user backed out.
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key, required this.mode});

  final PinSetupMode mode;

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

enum _Step { current, create, confirm }

class _PinSetupPageState extends State<PinSetupPage> {
  late _Step _step;

  String _entry = '';
  String _firstEntry = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Changing or removing a PIN starts by proving you know the current one.
    _step = widget.mode == PinSetupMode.create ? _Step.create : _Step.current;
  }

  String get _title => switch (widget.mode) {
    PinSetupMode.create => 'Set a PIN',
    PinSetupMode.change => 'Change PIN',
    PinSetupMode.remove => 'Turn off app lock',
  };

  String get _prompt => switch (_step) {
    _Step.current => 'Enter your current PIN',
    _Step.create => 'Choose a new PIN (4-8 digits)',
    _Step.confirm => 'Enter the new PIN again',
  };

  /// The button finishes the job on the confirmation step, and also right
  /// away when the only thing left to do is switch the lock off.
  bool get _isLastStep =>
      _step == _Step.confirm ||
      (_step == _Step.current && widget.mode == PinSetupMode.remove);

  void _append(String digit) {
    if (_entry.length >= AppLock.maxPinLength) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() {
      _entry = _entry.substring(0, _entry.length - 1);
      _error = null;
    });
  }

  void _fail(String message) {
    setState(() {
      _entry = '';
      _error = message;
    });
  }

  Future<void> _next() async {
    final repo = context.read<AppRepository>();
    final entry = _entry;

    switch (_step) {
      case _Step.current:
        await _checkCurrent(repo, entry);
        break;
      case _Step.create:
        _chooseNew(entry);
        break;
      case _Step.confirm:
        await _confirmNew(repo, entry);
        break;
    }
  }

  Future<void> _checkCurrent(AppRepository repo, String entry) async {
    if (!repo.verifyPin(entry)) {
      _fail('Wrong PIN. Try again.');
      return;
    }
    if (widget.mode == PinSetupMode.remove) {
      await _apply(repo.clearPin);
      return;
    }
    setState(() {
      _step = _Step.create;
      _entry = '';
      _error = null;
    });
  }

  void _chooseNew(String entry) {
    if (!AppLock.isValidPin(entry)) {
      _fail('A PIN must be 4-8 digits');
      return;
    }
    setState(() {
      _step = _Step.confirm;
      _firstEntry = entry;
      _entry = '';
      _error = null;
    });
  }

  Future<void> _confirmNew(AppRepository repo, String entry) async {
    if (entry != _firstEntry) {
      // Send them back to the start rather than letting them guess which of
      // the two entries was the typo.
      setState(() {
        _step = _Step.create;
        _firstEntry = '';
        _entry = '';
        _error = 'The PINs did not match. Start again.';
      });
      return;
    }
    await _apply(() => repo.setPin(entry));
  }

  Future<void> _apply(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _fail('Could not save the PIN');
      return;
    }
    if (!mounted) return;
    // The caller shows the confirmation message: it still has a live
    // Scaffold once this route is gone.
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canContinue = !_busy && _entry.length >= AppLock.minPinLength;

    return Scaffold(
      appBar: AppBar(title: Text(_title.tr)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _prompt.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_step == _Step.create) ...[
                  const SizedBox(height: 8),
                  Text(
                    'If you forget this PIN there is no way to recover it. Keep a backup of your data.'
                        .tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                PinDots(
                  length: math.max(AppLock.minPinLength, _entry.length),
                  filled: _entry.length,
                  error: _error != null,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 20,
                  child: _error == null
                      ? null
                      : Text(
                          _error!.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: scheme.error),
                        ),
                ),
                const SizedBox(height: 6),
                PinPad(
                  onDigit: _append,
                  onBackspace: _backspace,
                  enabled: !_busy,
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canContinue ? _next : null,
                      child: Text((_isLastStep ? 'Confirm' : 'Continue').tr),
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
