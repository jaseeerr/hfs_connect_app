import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../app_routes.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _slideAnimation;

  bool _checkingInternet = true;
  bool _hasInternet = true;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _slideAnimation = Tween<double>(
      begin: 8,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
    _startFlow();
  }

  Future<bool> _hasActiveInternet() async {
    try {
      final Dio dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
          validateStatus: (status) => true,
        ),
      );

      final Response<dynamic> response = await dio.get(
        'https://clients3.google.com/generate_204',
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final int code = response.statusCode ?? 0;
      return code >= 200 && code < 400;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startFlow() async {
    if (_navigating) {
      return;
    }

    if (mounted) {
      setState(() {
        _checkingInternet = true;
        _hasInternet = true;
      });
    }

    final bool online = await _hasActiveInternet();
    if (!mounted) {
      return;
    }

    if (!online) {
      setState(() {
        _checkingInternet = false;
        _hasInternet = false;
      });
      return;
    }

    setState(() {
      _checkingInternet = false;
      _hasInternet = true;
      _navigating = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget status;
    if (_checkingInternet) {
      status = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(height: 12),
          Text(
            'Checking internet...',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ],
      );
    } else if (!_hasInternet) {
      status = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No internet connection',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _startFlow,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(108, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      status = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (_, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    ),
                  ),
                );
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image(
                    image: AssetImage('assets/LogoNoBg.png'),
                    width: 220,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Securing What Matters Most.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: status,
            ),
          ],
        ),
      ),
    );
  }
}
