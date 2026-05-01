import 'package:flutter/material.dart';

// ── Colour palette ─────────────────────────────────────────────────────────────
class AppTheme {
  // Brand colours
  static const Color primary      = Color(0xFF8B1A2C);
  static const Color primaryDark  = Color(0xFF6A1220);
  static const Color primaryLight = Color(0xFFB22234);

  // Accent
  static const Color accent = Color(0xFFE8C547);

  // Surfaces
  static const Color surface  = Color(0xFFF2F3F7);
  static const Color cardBg   = Color(0xFFFFFFFF);
  static const Color inputBg  = Color(0xFFFAFAFC);

  // Text
  static const Color textPrimary   = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint      = Color(0xFFADB5BD);

  // Borders
  static const Color border      = Color(0xFFE5E7EB);
  static const Color borderFocus = Color(0xFF8B1A2C);

  // Status
  static const Color error   = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info    = Color(0xFF0EA5E9);

  // ── Main theme ─────────────────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: primary,
      secondary: accent,
      surface: surface,
      error: error,
      onPrimary: Colors.white,
      onSecondary: Colors.black,
      onSurface: textPrimary,
    ),
    scaffoldBackgroundColor: surface,

    // ── Typography ──────────────────────────────────────────────────────────
    // Use the system default font so that accessibility font-weight /
    // letter-spacing settings are honoured automatically.
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.8),
      displayMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,  color: textPrimary, letterSpacing: -0.5),
      displaySmall:  TextStyle(fontSize: 22, fontWeight: FontWeight.bold,  color: textPrimary, letterSpacing: -0.4),
      headlineLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,  color: textPrimary, letterSpacing: -0.3),
      headlineMedium:TextStyle(fontSize: 18, fontWeight: FontWeight.bold,  color: textPrimary, letterSpacing: -0.2),
      headlineSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,  color: textPrimary),
      titleLarge:    TextStyle(fontSize: 15, fontWeight: FontWeight.w700,  color: textPrimary),
      titleMedium:   TextStyle(fontSize: 14, fontWeight: FontWeight.w600,  color: textPrimary),
      titleSmall:    TextStyle(fontSize: 13, fontWeight: FontWeight.w600,  color: textSecondary),
      bodyLarge:     TextStyle(fontSize: 15, fontWeight: FontWeight.normal,color: textPrimary, height: 1.55),
      bodyMedium:    TextStyle(fontSize: 14, fontWeight: FontWeight.normal,color: textPrimary, height: 1.5),
      bodySmall:     TextStyle(fontSize: 12, fontWeight: FontWeight.normal,color: textSecondary, height: 1.45),
      labelLarge:    TextStyle(fontSize: 14, fontWeight: FontWeight.w600,  color: textPrimary, letterSpacing: 0.1),
      labelMedium:   TextStyle(fontSize: 12, fontWeight: FontWeight.w600,  color: textSecondary, letterSpacing: 0.2),
      labelSmall:    TextStyle(fontSize: 11, fontWeight: FontWeight.w600,  color: textSecondary, letterSpacing: 0.3),
    ),

    // ── AppBar ─────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: primary,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: primary, size: 22),
    ),

    // ── Cards ──────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),

    // ── Inputs ─────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputBg,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: error, width: 2),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
      hintStyle: const TextStyle(color: textHint, fontSize: 14),
      prefixIconColor: textSecondary,
      floatingLabelStyle: const TextStyle(color: primary, fontSize: 13),
    ),

    // ── Elevated buttons ───────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: primary.withOpacity(0.45),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding:
        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),

    // ── Outlined buttons ───────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding:
        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ── Checkbox ────────────────────────────────────────────────────────────
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: primary, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    // ── Divider ─────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
      space: 0,
    ),

    // ── Dialog ──────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.15),
    ),

    // ── Drawer ─────────────────────────────────────────────────────────────
    drawerTheme: const DrawerThemeData(
      backgroundColor: cardBg,
      elevation: 4,
    ),

    // ── Snackbar ────────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: textPrimary,
      contentTextStyle:
      const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // ── Legacy light theme (kept for backward compat) ─────────────────────────
  static ThemeData get lightTheme => theme;
}

// ── Shared shadow helper ──────────────────────────────────────────────────────
List<BoxShadow> cardShadow({double opacity = 0.06, double blur = 16}) => [
  BoxShadow(
    color: Colors.black.withOpacity(opacity),
    blurRadius: blur,
    offset: const Offset(0, 4),
  ),
];

List<BoxShadow> primaryShadow({double opacity = 0.18, double blur = 20}) => [
  BoxShadow(
    color: AppTheme.primary.withOpacity(opacity),
    blurRadius: blur,
    offset: const Offset(0, 6),
  ),
];

// ── Toast ─────────────────────────────────────────────────────────────────────

class AppToast {
  static void show(
      BuildContext context,
      String message, {
        bool isError = false,
        bool isSuccess = false,
      }) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        message: message,
        isError: isError,
        isSuccess: isSuccess,
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError, isSuccess;

  const _ToastWidget({
    required this.message,
    this.isError = false,
    this.isSuccess = false,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<Offset> _sl;
  late Animation<double> _fd;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _sl = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _fd = CurvedAnimation(parent: _c, curve: Curves.easeIn);
    _c.forward();
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) _c.reverse();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isError
        ? AppTheme.error
        : widget.isSuccess
        ? AppTheme.success
        : AppTheme.primary;
    final icon = widget.isError
        ? Icons.error_outline_rounded
        : widget.isSuccess
        ? Icons.check_circle_outline_rounded
        : Icons.info_outline_rounded;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _sl,
        child: FadeTransition(
          opacity: _fd,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: bg.withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      // Respect system font scale — no manual scaling here.
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}