import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../app_routes.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/tester_data_service.dart';

class _LoginColors {
  const _LoginColors._();

  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pageBackground = Color(0xFFF3F4F6);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color danger = Color(0xFFB91C1C);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _loading = false;
  String _errorMsg = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _extractErrorMessage(Object err) {
    if (err is DioException) {
      final dynamic data = err.response?.data;
      if (data is Map<String, dynamic>) {
        final dynamic apiError = data['error'];
        final dynamic apiMessage = data['message'];
        if (apiError is String && apiError.isNotEmpty) {
          return apiError;
        }
        if (apiMessage is String && apiMessage.isNotEmpty) {
          return apiMessage;
        }
      } else if (data is Map) {
        final dynamic apiError = data['error'];
        final dynamic apiMessage = data['message'];
        if (apiError is String && apiError.isNotEmpty) {
          return apiError;
        }
        if (apiMessage is String && apiMessage.isNotEmpty) {
          return apiMessage;
        }
      }
      if (err.message != null && err.message!.isNotEmpty) {
        return err.message!;
      }
    }

    final String fallback = err.toString();
    if (fallback.startsWith('Exception: ')) {
      return fallback.replaceFirst('Exception: ', '');
    }
    return fallback;
  }

  Future<void> _onSubmit() async {
    final bool isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _errorMsg = '';
      _loading = true;
    });

    final String username = _usernameController.text.trim();
    final String password = _passwordController.text;

    try {
      if (username == 'testuser' && password == 'password') {
        await TesterDataService.ensureSeeded();
        await AuthStorage.saveAdminSession(
          token: 'tester-token',
          username: username,
          user: <String, dynamic>{
            '_id': 'tester_admin',
            'name': 'Test User',
            'superUser': true,
          },
          isTester: true,
        );

        if (!mounted) {
          return;
        }
        Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
        return;
      }

      final Dio dio = ApiClient.create(opt: 0);
      final Response<dynamic> response = await dio.post<dynamic>(
        '/login',
        data: <String, dynamic>{'username': username, 'password': password},
      );

      final dynamic body = response.data;
      if (body is! Map) {
        throw Exception('Login failed');
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(body);
      final dynamic tokenValue = data['token'];
      final String token = tokenValue is String ? tokenValue : '';
      final bool ok = data['ok'] == true;

      if (!ok || token.isEmpty) {
        final dynamic errorValue = data['error'];
        final String message = errorValue is String && errorValue.isNotEmpty
            ? errorValue
            : 'Login failed';
        throw Exception(message);
      }

      final Map<String, dynamic> user = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : <String, dynamic>{};

      await AuthStorage.saveAdminSession(
        token: token,
        username: username,
        user: user,
        isTester: false,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMsg = _extractErrorMessage(err);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    Widget? suffixIcon,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: _LoginColors.primaryBlue, size: 18),
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _LoginColors.textGray,
      ),
      hintStyle: const TextStyle(color: _LoginColors.textGray, fontSize: 13),
      filled: true,
      fillColor: _LoginColors.pureWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _LoginColors.lightGray, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _LoginColors.lightGray, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _LoginColors.primaryBlue,
          width: 1.2,
        ),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget formCard = Container(
      decoration: BoxDecoration(
        color: _LoginColors.pureWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _LoginColors.lightGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Image(
              image: AssetImage('assets/LogoNoBg.png'),
              height: 84,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 10),
            const Text(
              'Admin Sign In',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _LoginColors.darkGray,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Secure access to dashboard and operations',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _LoginColors.textGray,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_errorMsg.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  _errorMsg,
                  style: const TextStyle(
                    color: _LoginColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                label: 'Username',
                hint: 'admin',
                prefixIcon: Icons.person_outline_rounded,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Username is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _onSubmit(),
              decoration: _inputDecoration(
                label: 'Password',
                hint: '********',
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: TextButton(
                  onPressed: () {
                    setState(() {
                      _showPassword = !_showPassword;
                    });
                  },
                  child: Text(_showPassword ? 'Hide' : 'Show'),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: _LoginColors.primaryBlue,
                disabledBackgroundColor: _LoginColors.mediumGray,
                foregroundColor: _LoginColors.pureWhite,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: Icon(
                _loading ? Icons.hourglass_top_rounded : Icons.login_rounded,
                size: 18,
              ),
              label: Text(_loading ? 'Signing in...' : 'Sign In'),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: _LoginColors.pageBackground,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(color: _LoginColors.pageBackground),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: formCard,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
