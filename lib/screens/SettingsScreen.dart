import 'package:flutter/material.dart';
import 'package:my_app/services/PinCheckResult.dart';
import 'package:my_app/services/PinSetupScreen.dart';
import '../utils/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  bool _pinEnabled = false;
  bool _pinSet = false;
  bool _busy = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadSettings();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Load settings ──────────────────────────────────────────────────────────
  Future<void> _loadSettings() async {
    final settings = await PinService.loadSettings();
    if (!mounted) return;
    setState(() {
      _pinEnabled = settings.isPinEnabled;
      _pinSet = settings.isPinSet;
    });
    _fadeCtrl.forward();
  }

  // ── PIN toggle ─────────────────────────────────────────────────────────────
  Future<void> _onPinToggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      if (value) {
        // Enable: ask user to set a new PIN
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => const PinSetupScreen(mode: PinPadMode.setup),
          ),
        );
        if (result == true && mounted) {
          setState(() {
            _pinEnabled = true;
            _pinSet = true;
          });
          _toast('PIN lock enabled', isSuccess: true);
        }
      } else {
        // Disable: verify existing PIN first
        final confirmed = await _confirmWithPin('Enter your PIN to disable lock');
        if (confirmed && mounted) {
          await PinService.clearPin();
          setState(() {
            _pinEnabled = false;
            _pinSet = false;
          });
          _toast('PIN lock disabled');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Change PIN ─────────────────────────────────────────────────────────────
  Future<void> _onChangePinTap() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final verified = await _confirmWithPin('Enter your current PIN');
      if (!verified || !mounted) return;

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const PinSetupScreen(
            mode: PinPadMode.setup,
            title: 'Set New PIN',
          ),
        ),
      );
      if (result == true && mounted) {
        _toast('PIN changed successfully', isSuccess: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Remove PIN ─────────────────────────────────────────────────────────────
  Future<void> _onRemovePinTap() async {
    if (_busy) return;

    // Show confirmation dialog first
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (_) => const _RemovePinDialog(),
    );
    if (shouldRemove != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final confirmed = await _confirmWithPin('Enter your PIN to remove it');
      if (!confirmed || !mounted) return;

      await PinService.clearPin();
      setState(() {
        _pinEnabled = false;
        _pinSet = false;
      });
      _toast('PIN removed successfully');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Future<bool> _confirmWithPin(String title) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PinSetupScreen(
          mode: PinPadMode.verify,
          title: title,
        ),
      ),
    );
    return result == true;
  }

  void _toast(String msg, {bool isSuccess = false, bool isError = false}) {
    if (!mounted) return;
    AppToast.show(context, msg, isSuccess: isSuccess, isError: isError);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppTheme.textPrimary,
              size: 18,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.border),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Security section ───────────────────────────────────────────
            const _SectionHeader(
              icon: Icons.security_rounded,
              label: 'Security',
            ),
            const SizedBox(height: 8),

            _SettingsCard(
              children: [
                // PIN toggle
                _ToggleTile(
                  icon: Icons.lock_rounded,
                  iconBg: AppTheme.primary.withOpacity(0.1),
                  iconColor: AppTheme.primary,
                  title: 'PIN Lock',
                  subtitle: _pinEnabled
                      ? 'App is protected — PIN required on every open'
                      : 'Require a PIN every time the app opens',
                  value: _pinEnabled,
                  onChanged: _busy ? null : _onPinToggle,
                ),

                // Change PIN (only shown when PIN is active)
                if (_pinEnabled && _pinSet) ...[
                  const _SettingsDivider(),
                  _ActionTile(
                    icon: Icons.edit_rounded,
                    iconBg: AppTheme.primary.withOpacity(0.08),
                    iconColor: AppTheme.primary,
                    title: 'Change PIN',
                    subtitle: 'Update your current 6-digit PIN',
                    onTap: _onChangePinTap,
                  ),
                  const _SettingsDivider(),
                  _ActionTile(
                    icon: Icons.lock_open_rounded,
                    iconBg: AppTheme.error.withOpacity(0.08),
                    iconColor: AppTheme.error,
                    title: 'Remove PIN',
                    subtitle: 'Disable PIN protection entirely',
                    titleColor: AppTheme.error,
                    onTap: _onRemovePinTap,
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // ── PIN info banner ────────────────────────────────────────────
            _InfoBanner(
              icon: Icons.info_outline_rounded,
              message: _pinEnabled
                  ? 'PIN is active. You will be asked to enter it each time '
                  'the app opens or returns from the background.'
                  : 'Enable PIN lock to protect your shift data. '
                  'Your login session lasts 15 days before re-authentication is required.',
            ),

            const SizedBox(height: 32),

            // ── App info section ───────────────────────────────────────────
            const _SectionHeader(
              icon: Icons.info_rounded,
              label: 'About',
            ),
            const SizedBox(height: 8),

            _SettingsCard(
              children: [
                _InfoTile(
                  icon: Icons.badge_rounded,
                  iconBg: const Color(0xFFEEF2FF),
                  iconColor: const Color(0xFF6366F1),
                  title: 'APC Track',
                  subtitle: 'Version 1.0.0',
                ),
                const _SettingsDivider(),
                _InfoTile(
                  icon: Icons.business_rounded,
                  iconBg: AppTheme.primary.withOpacity(0.08),
                  iconColor: AppTheme.primary,
                  title: 'AP Cabinet',
                  subtitle: 'Staff management portal',
                ),
                const _SettingsDivider(),
                _InfoTile(
                  icon: Icons.calendar_today_rounded,
                  iconBg: AppTheme.success.withOpacity(0.08),
                  iconColor: AppTheme.success,
                  title: 'Session Expiry',
                  subtitle: '15 days from last login',
                ),
              ],
            ),

            const SizedBox(height: 40),

            Center(
              child: Text(
                'APC Track v1.0.0 — © 2026 AP Cabinet',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary.withOpacity(0.5),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Remove PIN confirmation dialog
// ─────────────────────────────────────────────────────────────────────────────

class _RemovePinDialog extends StatelessWidget {
  const _RemovePinDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              color: AppTheme.error,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Remove PIN?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your app will no longer be protected by a PIN. '
                'Anyone with access to your device can open it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            side: const BorderSide(color: AppTheme.border),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text(
            'Remove',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 56,
      endIndent: 0,
      color: Color(0xFFEEEEEE),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool)? onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Switch
            Switch(
              value: value,
              onChanged: disabled ? null : onChanged,
              activeColor: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? titleColor;

  const _ActionTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: titleColor ?? AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InfoBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}