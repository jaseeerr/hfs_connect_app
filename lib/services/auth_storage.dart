import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class AuthStorage {
  const AuthStorage._();

  static const String _boxName = 'auth_box';
  static const String _tokenKey = 'adminToken';
  static const String _userRoleKey = 'userRole';
  static const String _superUserKey = 'superUser';
  static const String _userKey = 'user';
  static const String _usernameKey = 'username';

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<dynamic>(_boxName);
    }
  }

  static Future<Box<dynamic>> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return Hive.openBox<dynamic>(_boxName);
    }
    return Hive.box<dynamic>(_boxName);
  }

  static String? get token {
    if (!Hive.isBoxOpen(_boxName)) {
      return null;
    }
    final dynamic value = Hive.box<dynamic>(_boxName).get(_tokenKey);
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static bool get hasToken => token != null;

  static Future<void> saveAdminSession({
    required String token,
    required String username,
    required Map<String, dynamic> user,
  }) async {
    final Box<dynamic> box = await _box();
    await box.put(_tokenKey, token);
    await box.put(_userRoleKey, 'admin');
    await box.put(_superUserKey, user['superUser'] == true ? 'true' : 'false');
    await box.put(_userKey, jsonEncode(user));
    await box.put(_usernameKey, username);
  }

  static Future<void> clear() async {
    final Box<dynamic> box = await _box();
    await box.delete(_tokenKey);
    await box.delete(_userRoleKey);
    await box.delete(_superUserKey);
    await box.delete(_userKey);
    await box.delete(_usernameKey);
  }
}
