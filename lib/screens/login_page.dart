import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../app_routes.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        color: const Color(0xFFF9FAFB),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'HFSConnect - Admin',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_errorMsg.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            child: Text(
                              _errorMsg,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Text(
                          'Username',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'admin',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Password',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _onSubmit(),
                          decoration: InputDecoration(
                            hintText: '********',
                            border: const OutlineInputBorder(),
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
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _onSubmit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.black,
                            disabledBackgroundColor: Colors.black45,
                          ),
                          child: Text(_loading ? 'Signing in...' : 'Sign In'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
