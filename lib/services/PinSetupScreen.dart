import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_app/services/PinCheckResult.dart';
import '../utils/app_theme.dart';

/// A full-screen PIN entry pad used for both SETUP and VERIFICATION.
///
/// [mode] = [PinPadMode.setup]  → asks the user to enter a new PIN twice.
/// [mode] = [PinPadMode.verify] → verifies the PIN and calls [onSuccess].
///
/// Usage (setup):
///   final changed = await Navigator.push(context,
///     MaterialPageRoute(builder: (_) => const PinSetupScreen()));
///
/// Usage (verify):
///   final ok = await Navigator.push(context,
///     MaterialPageRoute(builder: (_) =>
///       PinSetupScreen(mode: PinPadMode.verify, onSuccess: () { … })));
class PinSetupScreen extends StatefulWidget {
  final PinPadMode mode;
  final VoidCallback? onSuccess;
  final String? title;

  const PinSetupScreen({
    super.key,
    this.mode = PinPadMode.setup,
    this.onSuccess,
    this.title,
  });

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

enum PinPadMode { setup, verify }

class _PinSetupScreenState extends State<PinSetupScreen>
    with TickerProviderStateMixin {
  static const int _pinLength = 6;

  String _firstPin = '';
  String _currentInput = '';
  bool _isConfirmStep = false;
  String _statusText = '';
  bool _isError = false;

  // Shake animation
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  // Dot scale animation
  late AnimationController _dotCtrl;

  // Lockout
  int _lockoutSeconds = 0;
  bool _isLockedOut = false;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _statusText = widget.mode == PinPadMode.setup
        ? 'Enter a new 6-digit PIN'
        : 'Enter your PIN';

    if (widget.mode == PinPadMode.verify) {
      _checkLockout();
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkLockout() async {
    final secs = await PinService.getRemainingLockoutSeconds();
    if (secs > 0) {
      setState(() {
        _isLockedOut = true;
        _lockoutSeconds = secs;
        _statusText = 'Too many attempts';
      });
      _startLockoutCountdown();
    }
  }

  void _startLockoutCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _lockoutSeconds--;
        if (_lockoutSeconds <= 0) {
          _isLockedOut = false;
          _statusText = widget.mode == PinPadMode.setup
              ? 'Enter a new 6-digit PIN'
              : 'Enter your PIN';
        }
      });
      return _lockoutSeconds > 0;
    });
  }

  void _onKeyTap(String key) {
    HapticFeedback.lightImpact();
    if (_isLockedOut || _currentInput.length >= _pinLength) return;

    setState(() {
      _currentInput += key;
      _isError = false;
    });

    if (_currentInput.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 150), _onPinComplete);
    }
  }

  void _onDelete() {
    HapticFeedback.lightImpact();
    if (_currentInput.isEmpty) return;
    setState(() => _currentInput = _currentInput.substring(0, _currentInput.length - 1));
  }

  Future<void> _onPinComplete() async {
    if (widget.mode == PinPadMode.verify) {
      await _handleVerify();
    } else {
      _handleSetup();
    }
  }

  Future<void> _handleVerify() async {
    final result = await PinService.verifyPin(_currentInput);

    if (result.isCorrect) {
      HapticFeedback.mediumImpact();
      widget.onSuccess?.call();
      if (mounted) Navigator.pop(context, true);
    } else if (result.isLockedOut) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isLockedOut = true;
        _lockoutSeconds = result.lockoutSeconds;
        _currentInput = '';
        _isError = true;
        _statusText = 'Too many attempts';
      });
      _shake();
      _startLockoutCountdown();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _isError = true;
        _statusText = 'Wrong PIN — ${result.attemptsLeft} attempt${result.attemptsLeft == 1 ? '' : 's'} left';
        _currentInput = '';
      });
      _shake();
    }
  }

  void _handleSetup() {
    if (!_isConfirmStep) {
      setState(() {
        _firstPin = _currentInput;
        _currentInput = '';
        _isConfirmStep = true;
        _statusText = 'Confirm your PIN';
      });
    } else {
      if (_currentInput == _firstPin) {
        _saveAndExit();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _isError = true;
          _statusText = 'PINs don\'t match — try again';
          _currentInput = '';
          _isConfirmStep = false;
          _firstPin = '';
        });
        _shake();
      }
    }
  }

  Future<void> _saveAndExit() async {
    await PinService.setPin(_currentInput);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _shake() {
    _shakeCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 18),
          ),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text(
          widget.title ??
              (widget.mode == PinPadMode.setup ? 'Set Up PIN' : 'Enter PIN'),
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            // ── Icon ────────────────────────────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryDark, AppTheme.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: primaryShadow(opacity: 0.22, blur: 24),
              ),
              child: Icon(
                widget.mode == PinPadMode.setup
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),
            // ── Status text ──────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                _isLockedOut
                    ? 'Locked — try again in ${_lockoutSeconds}s'
                    : _statusText,
                key: ValueKey(_statusText + _lockoutSeconds.toString()),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _isError || _isLockedOut
                      ? AppTheme.error
                      : AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            // ── PIN dots ─────────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(
                  _shakeCtrl.isAnimating
                      ? _shakeAnim.value *
                      ((_shakeCtrl.value * 10).floor().isEven ? 1 : -1)
                      : 0,
                  0,
                ),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (i) {
                  final filled = i < _currentInput.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: filled ? 18 : 16,
                    height: filled ? 18 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? (_isError ? AppTheme.error : AppTheme.primary)
                          : Colors.transparent,
                      border: Border.all(
                        color: filled
                            ? (_isError ? AppTheme.error : AppTheme.primary)
                            : AppTheme.border,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: filled
                              ? (_isError ? AppTheme.error : AppTheme.primary)
                              .withOpacity(0.3)
                              : Colors.transparent,   // ← always present, just invisible
                          blurRadius: filled ? 8 : 0, // ← tween stays 0 → 8, never negative
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const Spacer(),
            // ── Keypad ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 32),
              child: Column(
                children: [
                  _KeyRow(keys: const ['1', '2', '3'], onTap: _onKeyTap),
                  const SizedBox(height: 12),
                  _KeyRow(keys: const ['4', '5', '6'], onTap: _onKeyTap),
                  const SizedBox(height: 12),
                  _KeyRow(keys: const ['7', '8', '9'], onTap: _onKeyTap),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 72), // placeholder
                      _PinKey(label: '0', onTap: () => _onKeyTap('0')),
                      _DeleteKey(onTap: _onDelete),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Key row ────────────────────────────────────────────────────────────────────
class _KeyRow extends StatelessWidget {
  final List<String> keys;
  final void Function(String) onTap;
  const _KeyRow({required this.keys, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((k) => _PinKey(label: k, onTap: () => onTap(k))).toList(),
    );
  }
}

// ── Individual key ─────────────────────────────────────────────────────────────
class _PinKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PinKey({required this.label, required this.onTap});

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1, end: 0.88)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) {
        _c.reverse();
        widget.onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Delete key ─────────────────────────────────────────────────────────────────
class _DeleteKey extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteKey({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        child: const Icon(Icons.backspace_outlined,
            color: AppTheme.textSecondary, size: 26),
      ),
    );
  }
}