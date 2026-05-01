import 'package:flutter/material.dart';
import '../models/login_request.dart';
import '../models/register_request.dart';
import '../models/auth_response.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final _service = AuthService();

  bool _isLoading = false;
  bool _isLoggedIn = false;
  String? staffId;
  String? _userId;
  String? _role;
  String? _userName;
  String? _fullName;
  String? _userEmail;
  String? _errorMessage;
  String? _tenantIdentifier;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  String? get userId => _userId;
  String? get tenantIdentifier => _tenantIdentifier;
  String? get role => _role;
  String? get userName => _userName;
  String? get fullName => _fullName;
  String? get userEmail => _userEmail;
  String? get errorMessage => _errorMessage;

  Future<void> checkLoginStatus() async {
    _isLoggedIn = await _service.isLoggedIn();
    if (_isLoggedIn) {
      _userId = await _service.getUserId();
      _role = await _service.getRole();
      _userName = await _service.getUserName();
      _fullName = await _service.getFullName();
      _userEmail = await _service.getUserEmail();
    }
    notifyListeners();
  }

  /// Called by SplashScreen after a successful PIN-unlock silent re-login.
  /// Re-reads what AuthService just wrote to SecureStorage so the rest of
  /// the app has fresh state without going through the login form.
  Future<void> refreshFromStoredData() async {
    final id = await _service.getUserId();

    _userId    = id;
    staffId    = id;                              // public field — no underscore
    _userName  = await _service.getUserName();
    _fullName  = await _service.getFullName();
    _userEmail = await _service.getUserEmail();
    _role      = await _service.getRole();
    _isLoggedIn = true;
    // No _token field in this provider — token lives in SecureStorage only.

    notifyListeners();
  }

  Future<LoginApiResponse> login(LoginRequest request) async {
    _setLoading(true);
    final response = await _service.login(request);
    debugPrint('login called');
    if (response.success && response.data != null) {
      _isLoggedIn = true;
      _userId = response.data!.userId;
      staffId = response.data!.userId.toString();
      _role = response.data!.role;
      _userName = response.data!.userName;
      _fullName = response.data!.fullName;
      _userEmail = response.data!.email;
      _tenantIdentifier = request.tenantIdentifier.toString();
    } else {
      _errorMessage = response.message;
    }
    _setLoading(false);
    return response;
  }

  Future<RegisterApiResponse> register(RegisterRequest request) async {
    _setLoading(true);
    final response = await _service.register(request);
    if (!response.success) _errorMessage = response.message;
    _setLoading(false);
    return response;
  }

  Future<void> logout() async {
    _setLoading(true);
    await _service.logout();
    _isLoggedIn = false;
    _userId = null;
    staffId = null;
    _tenantIdentifier = null;
    _role = null;
    _userName = null;
    _fullName = null;
    _userEmail = null;
    _errorMessage = null;
    _setLoading(false);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}