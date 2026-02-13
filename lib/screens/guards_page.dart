import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../widget/app_bottom_nav_bar.dart';

class AppColors {
  const AppColors._();

  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF8FAFC);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFFB45309);
  static const Color danger = Color(0xFFB91C1C);
}

String _stringValue(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString();
}

num _numValue(dynamic value) {
  if (value is num) {
    return value;
  }
  return num.tryParse(_stringValue(value)) ?? 0;
}

bool _boolValue(dynamic value) {
  if (value is bool) {
    return value;
  }
  final String lower = _stringValue(value).toLowerCase();
  return lower == 'true' || lower == '1';
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _mapListValue(dynamic value) {
  if (value is! List) {
    return <Map<String, dynamic>>[];
  }

  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<String> _stringListValue(dynamic value) {
  if (value is List) {
    return value
        .map((item) => _stringValue(item).trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  final String raw = _stringValue(value);
  if (raw.trim().isEmpty) {
    return <String>[];
  }

  return raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _toDateInput(dynamic value) {
  final String raw = _stringValue(value).trim();
  if (raw.isEmpty) {
    return '';
  }

  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  final String year = parsed.year.toString().padLeft(4, '0');
  final String month = parsed.month.toString().padLeft(2, '0');
  final String day = parsed.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _displayDate(dynamic value) {
  final DateTime? parsed = DateTime.tryParse(_stringValue(value));
  if (parsed == null) {
    return '-';
  }
  final String year = parsed.year.toString().padLeft(4, '0');
  final String month = parsed.month.toString().padLeft(2, '0');
  final String day = parsed.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _joined(dynamic value) {
  return _stringListValue(value).join(', ');
}

String _guardId(Map<String, dynamic> guard) {
  return _stringValue(guard['_id']);
}

List<String> _csvToList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class GuardsPage extends StatefulWidget {
  const GuardsPage({super.key});

  @override
  State<GuardsPage> createState() => _GuardsPageState();
}

class _GuardsPageState extends State<GuardsPage> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _guards = <Map<String, dynamic>>[];
  bool _loading = true;
  String _searchTerm = '';
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  Dio _adminApi() {
    return ApiClient.create(opt: 0, token: AuthStorage.token);
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    _fetchGuards();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _errorMessageFrom(Object error) {
    if (error is DioException) {
      final Map<String, dynamic> data = _mapValue(error.response?.data);
      final String apiError = _stringValue(data['error']).trim();
      final String apiMessage = _stringValue(data['message']).trim();

      if (apiError.isNotEmpty) {
        return apiError;
      }
      if (apiMessage.isNotEmpty) {
        return apiMessage;
      }
      if (_stringValue(error.message).isNotEmpty) {
        return _stringValue(error.message);
      }
    }

    final String fallback = _stringValue(error);
    if (fallback.startsWith('Exception: ')) {
      return fallback.replaceFirst('Exception: ', '');
    }
    return fallback;
  }

  Future<void> _fetchGuards({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final Response<dynamic> response = await _adminApi().get('/guards');
      final Map<String, dynamic> body = _mapValue(response.data);

      if (body['ok'] == true) {
        final List<Map<String, dynamic>> items = _mapListValue(body['data']);
        if (mounted) {
          setState(() {
            _guards = items;
          });
        }
      } else {
        throw Exception(
          _stringValue(body['error']).isNotEmpty
              ? _stringValue(body['error'])
              : 'Error fetching guards',
        );
      }
    } catch (error) {
      _showSnack(_errorMessageFrom(error), isError: true);
    } finally {
      if (showLoader && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Map<String, dynamic>? _guardById(String guardId) {
    for (final Map<String, dynamic> guard in _guards) {
      if (_guardId(guard) == guardId) {
        return guard;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _runMutation({
    required String guardId,
    required Future<Response<dynamic>> Function(Dio dio) request,
    String? successMessage,
  }) async {
    try {
      final Response<dynamic> response = await request(_adminApi());
      final Map<String, dynamic> body = _mapValue(response.data);
      if (body['ok'] != true) {
        throw Exception(
          _stringValue(body['error']).isNotEmpty
              ? _stringValue(body['error'])
              : 'Request failed',
        );
      }

      await _fetchGuards(showLoader: false);
      if (successMessage != null && successMessage.isNotEmpty) {
        _showSnack(successMessage);
      }

      final Map<String, dynamic> directData = _mapValue(body['data']);
      if (directData.isNotEmpty) {
        return directData;
      }

      return _guardById(guardId);
    } catch (error) {
      _showSnack(_errorMessageFrom(error), isError: true);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _toggleGuardStatus(String guardId) {
    return _runMutation(
      guardId: guardId,
      request: (dio) => dio.patch('/guards/$guardId/toggle-block'),
      successMessage: 'Guard status updated',
    );
  }

  Future<Map<String, dynamic>?> _toggleVerified(String guardId) {
    return _runMutation(
      guardId: guardId,
      request: (dio) => dio.patch('/guards/$guardId/verify'),
      successMessage: 'Verification status updated',
    );
  }

  Future<Map<String, dynamic>?> _toggleDocumentVerification(
    String guardId,
    String field,
  ) {
    return _runMutation(
      guardId: guardId,
      request: (dio) => dio.patch(
        '/guards/$guardId/toggle-verification',
        data: <String, dynamic>{'field': field},
      ),
      successMessage: '$field verification updated',
    );
  }

  Future<Map<String, dynamic>?> _addComplaint(
    String guardId,
    String description,
    String severity,
    DateTime date,
  ) async {
    try {
      final Response<dynamic> response = await _adminApi().post(
        '/guards/$guardId/complaints',
        data: <String, dynamic>{
          'description': description,
          'severity': severity,
          'date': date.toIso8601String(),
        },
      );

      final Map<String, dynamic> body = _mapValue(response.data);
      if (body['ok'] != true) {
        throw Exception(
          _stringValue(body['error']).isNotEmpty
              ? _stringValue(body['error'])
              : 'Error adding complaint',
        );
      }

      await _fetchGuards(showLoader: false);
      _showSnack('Complaint added');

      final Map<String, dynamic> updatedGuard = _mapValue(body['data']);
      if (updatedGuard.isNotEmpty) {
        return updatedGuard;
      }
      return _guardById(guardId);
    } catch (error) {
      _showSnack(_errorMessageFrom(error), isError: true);
      return null;
    }
  }

  Future<void> _deleteGuard(Map<String, dynamic> guard) async {
    final String guardId = _guardId(guard);
    if (guardId.isEmpty) {
      _showSnack('Invalid guard id', isError: true);
      return;
    }

    final bool shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Delete Guard'),
              content: const Text(
                'Are you sure you want to delete this guard?',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete) {
      return;
    }

    try {
      final Response<dynamic> response = await _adminApi().delete(
        '/guards/$guardId',
      );
      final Map<String, dynamic> body = _mapValue(response.data);
      if (body['ok'] != true) {
        throw Exception(
          _stringValue(body['error']).isNotEmpty
              ? _stringValue(body['error'])
              : 'Error deleting guard',
        );
      }

      await _fetchGuards(showLoader: false);
      _showSnack('Guard deleted');
    } catch (error) {
      _showSnack(_errorMessageFrom(error), isError: true);
    }
  }

  Future<String> _uploadToCloudinary(
    XFile file, {
    required String uploadPreset,
  }) async {
    final String fileName =
        'img${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}_${file.name}';

    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      'upload_preset': uploadPreset,
      'cloud_name': 'dfethvtz3',
    });

    final Response<dynamic> response = await Dio().post(
      'https://api.cloudinary.com/v1_1/dfethvtz3/auto/upload',
      data: formData,
    );

    final String secureUrl = _stringValue(
      _mapValue(response.data)['secure_url'],
    );
    if (secureUrl.isEmpty) {
      throw Exception('Error uploading image');
    }

    return secureUrl;
  }

  Future<List<String>> _uploadMultipleToCloudinary(List<XFile> files) async {
    final List<String> urls = <String>[];
    for (final XFile file in files) {
      final String url = await _uploadToCloudinary(
        file,
        uploadPreset: 'HFS_Docs',
      );
      urls.add(url);
    }
    return urls;
  }

  Future<void> _saveGuard(GuardFormData formData, String? guardId) async {
    final GuardFormData payloadData = formData.copy();

    if (payloadData.photoFile != null) {
      payloadData.photo = await _uploadToCloudinary(
        payloadData.photoFile!,
        uploadPreset: 'honorAttend',
      );
    }

    for (final GuardDocumentForm document in <GuardDocumentForm>[
      payloadData.emiratesId,
      payloadData.passport,
      payloadData.sira,
    ]) {
      if (document.selectedFiles.isNotEmpty) {
        final List<String> uploaded = await _uploadMultipleToCloudinary(
          document.selectedFiles,
        );
        document.imageUrls.addAll(uploaded);
        document.selectedFiles = <XFile>[];
      }
    }

    final Map<String, dynamic> payload = payloadData.toPayload();
    final Dio dio = _adminApi();

    final Response<dynamic> response;
    if (guardId != null && guardId.isNotEmpty) {
      response = await dio.put('/guards/$guardId', data: payload);
    } else {
      response = await dio.post('/guards', data: payload);
    }

    final Map<String, dynamic> body = _mapValue(response.data);
    if (body['ok'] != true) {
      throw Exception(
        _stringValue(body['error']).isNotEmpty
            ? _stringValue(body['error'])
            : 'Error saving guard',
      );
    }

    await _fetchGuards(showLoader: false);
  }

  Future<void> _openGuardForm({Map<String, dynamic>? guard}) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return GuardFormDialog(
          picker: _picker,
          initialGuard: guard,
          onSubmit: _saveGuard,
          errorMessageBuilder: _errorMessageFrom,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (saved == true) {
      _showSnack('Guard saved successfully');
    }
  }

  Future<void> _openGuardDetails(Map<String, dynamic> guard) async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        return GuardDetailsDialog(
          initialGuard: guard,
          onRefresh: (guardId) async {
            await _fetchGuards(showLoader: false);
            return _guardById(guardId);
          },
          onToggleBlock: _toggleGuardStatus,
          onToggleVerified: _toggleVerified,
          onToggleDocumentVerification: _toggleDocumentVerification,
          onAddComplaint: _addComplaint,
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredGuards {
    final String search = _searchTerm.toLowerCase().trim();

    return _guards.where((Map<String, dynamic> guard) {
      final String name = _stringValue(guard['name']).toLowerCase();
      final String email = _stringValue(guard['email']).toLowerCase();
      final String phone = _stringValue(guard['phone']);

      final bool matchesSearch =
          search.isEmpty ||
          name.contains(search) ||
          email.contains(search) ||
          phone.contains(search);

      return matchesSearch;
    }).toList();
  }

  BoxDecoration _buildBackgroundGradient() {
    return const BoxDecoration(color: AppColors.offWhite);
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(18)),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.lightGray, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: AppColors.pureWhite,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      minimumSize: const Size(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
    );
  }

  Widget _buildHeader(bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isSmallScreen ? 12 : 20,
        isSmallScreen ? 12 : 20,
        isSmallScreen ? 12 : 20,
        0,
      ),
      child: _glassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.lightGray,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.security_rounded,
                    color: AppColors.primaryBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Guards Management',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkGray,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Manage your team, compliance and status in one place',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openGuardForm(),
                  style: _primaryButtonStyle(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(isSmallScreen ? 'Add' : 'Add Guard'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchTerm = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by name, email, or phone',
                hintStyle: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textGray,
                  size: 20,
                ),
                filled: true,
                fillColor: AppColors.pureWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.lightGray,
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.lightGray,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.primaryBlue,
                    width: 1.2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(
    String label, {
    required Color background,
    required Color textColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String value) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textGray),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.darkGray,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Color iconColor = AppColors.darkGray,
    Color? background,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: background ?? AppColors.pureWhite,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.lightGray, width: 1),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }

  Widget _buildDocBadge(String label, bool verified) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: verified
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: verified ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: verified ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuardCard(Map<String, dynamic> guard, bool isSmallScreen) {
    final String guardId = _guardId(guard);
    final String name = _stringValue(guard['name']).isNotEmpty
        ? _stringValue(guard['name'])
        : 'Unnamed Guard';
    final String type = _stringValue(guard['type']);
    final bool block = _boolValue(guard['block']);
    final bool verified = _boolValue(guard['verified']);
    final String photo = _stringValue(guard['photo']);
    final int complaintsCount = _mapListValue(guard['complaints']).length;
    final num payPerHour = _numValue(guard['defaultPay']);
    final String defaultPay = payPerHour % 1 == 0
        ? payPerHour.toStringAsFixed(0)
        : payPerHour.toStringAsFixed(2);

    final Map<String, dynamic> emiratesId = _mapValue(guard['emiratesId']);
    final Map<String, dynamic> passport = _mapValue(guard['passport']);
    final Map<String, dynamic> sira = _mapValue(guard['sira']);
    final String typeLabel = type.isEmpty
        ? ''
        : '${type[0].toUpperCase()}${type.substring(1)}'.replaceAll('-', ' ');

    return _glassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.lightGray, width: 1),
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.lightGray,
                  backgroundImage: photo.isNotEmpty
                      ? NetworkImage(photo)
                      : null,
                  child: photo.isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textGray,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$defaultPay AED / hour',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusChip(
                          block ? 'Blocked' : 'Active',
                          background: block
                              ? AppColors.danger.withValues(alpha: 0.1)
                              : AppColors.success.withValues(alpha: 0.1),
                          textColor: block
                              ? AppColors.danger
                              : AppColors.success,
                        ),
                        _statusChip(
                          verified ? 'Verified' : 'Unverified',
                          background: verified
                              ? AppColors.primaryBlue.withValues(alpha: 0.1)
                              : AppColors.warning.withValues(alpha: 0.1),
                          textColor: verified
                              ? AppColors.primaryBlue
                              : AppColors.warning,
                          icon: verified
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (typeLabel.isNotEmpty)
                          Text(
                            'Type: $typeLabel',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textGray,
                            ),
                          ),
                        Text(
                          'Complaints: $complaintsCount',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 4,
                runSpacing: 6,
                children: [
                  _actionButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View',
                    onTap: () => _openGuardDetails(guard),
                  ),
                  _actionButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    onTap: () => _openGuardForm(guard: guard),
                  ),
                  _actionButton(
                    icon: block
                        ? Icons.remove_red_eye_outlined
                        : Icons.visibility_off_outlined,
                    tooltip: block ? 'Unblock' : 'Block',
                    onTap: guardId.isEmpty
                        ? null
                        : () => _toggleGuardStatus(guardId),
                  ),
                  _actionButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    iconColor: AppColors.danger,
                    background: AppColors.pureWhite,
                    onTap: () => _deleteGuard(guard),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              SizedBox(
                width: isSmallScreen ? 240 : 290,
                child: _infoLine(
                  Icons.mail_outline,
                  _stringValue(guard['email']),
                ),
              ),
              SizedBox(
                width: isSmallScreen ? 200 : 220,
                child: _infoLine(
                  Icons.phone_outlined,
                  _stringValue(guard['phone']),
                ),
              ),
              SizedBox(
                width: isSmallScreen ? 220 : 270,
                child: _infoLine(
                  Icons.public_outlined,
                  _joined(guard['nationality']),
                ),
              ),
              SizedBox(
                width: isSmallScreen ? 190 : 220,
                child: _infoLine(
                  Icons.language_outlined,
                  _joined(guard['language']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDocBadge('Emirates ID', _boolValue(emiratesId['verified'])),
              _buildDocBadge('Passport', _boolValue(passport['verified'])),
              _buildDocBadge('SIRA', _boolValue(sira['verified'])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListBody(bool isSmallScreen) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }

    final List<Map<String, dynamic>> filtered = _filteredGuards;
    if (filtered.isEmpty) {
      return Center(
        child: _glassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.groups_2_outlined,
                size: 48,
                color: AppColors.textGray,
              ),
              SizedBox(height: 12),
              Text(
                'No guards found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGray,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Try a different search term',
                style: TextStyle(fontSize: 13, color: AppColors.textGray),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        isSmallScreen ? 12 : 20,
        12,
        isSmallScreen ? 12 : 20,
        20,
      ),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, index) =>
          _buildGuardCard(filtered[index], isSmallScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Container(
        decoration: _buildBackgroundGradient(),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildHeader(isSmallScreen),
                Expanded(child: _buildListBody(isSmallScreen)),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 2),
    );
  }
}

typedef GuardFormSubmit =
    Future<void> Function(GuardFormData data, String? guardId);

class GuardFormDialog extends StatefulWidget {
  const GuardFormDialog({
    super.key,
    required this.picker,
    required this.onSubmit,
    required this.errorMessageBuilder,
    this.initialGuard,
  });

  final ImagePicker picker;
  final GuardFormSubmit onSubmit;
  final String Function(Object error) errorMessageBuilder;
  final Map<String, dynamic>? initialGuard;

  @override
  State<GuardFormDialog> createState() => _GuardFormDialogState();
}

class _GuardFormDialogState extends State<GuardFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late GuardFormData _formData;
  bool _submitting = false;
  String _error = '';

  String? get _guardId {
    if (widget.initialGuard == null) {
      return null;
    }
    final String id = _guardIdFrom(widget.initialGuard!);
    return id.isEmpty ? null : id;
  }

  String _guardIdFrom(Map<String, dynamic> guard) {
    return _stringValue(guard['_id']);
  }

  @override
  void initState() {
    super.initState();
    _formData = widget.initialGuard == null
        ? GuardFormData.empty()
        : GuardFormData.fromGuard(widget.initialGuard!);
  }

  Future<void> _pickProfilePhoto() async {
    final XFile? file = await widget.picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (file == null) {
      return;
    }

    setState(() {
      _formData.photoFile = file;
      _formData.photo = '';
    });
  }

  GuardDocumentForm _docByKey(String key) {
    switch (key) {
      case 'emiratesId':
        return _formData.emiratesId;
      case 'passport':
        return _formData.passport;
      case 'sira':
        return _formData.sira;
      default:
        return _formData.emiratesId;
    }
  }

  Future<void> _pickDocumentFiles(String docKey) async {
    final List<XFile> files = await widget.picker.pickMultiImage(
      imageQuality: 85,
    );
    if (files.isEmpty) {
      return;
    }

    final GuardDocumentForm doc = _docByKey(docKey);
    setState(() {
      doc.selectedFiles = <XFile>[...doc.selectedFiles, ...files];
    });
  }

  Future<void> _pickDate({
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) async {
    final DateTime initial = DateTime.tryParse(currentValue) ?? DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );

    if (selected == null) {
      return;
    }

    onSelected(_toDateInput(selected.toIso8601String()));
  }

  Future<void> _submit() async {
    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      return;
    }

    final NavigatorState navigator = Navigator.of(context);

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await widget.onSubmit(_formData, _guardId);
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = widget.errorMessageBuilder(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: AppColors.textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: AppColors.pureWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.lightGray, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.lightGray, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.2),
      ),
      isDense: true,
    );
  }

  Widget _dateField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isEmpty ? 'Select date' : value,
                style: TextStyle(
                  color: value.isEmpty
                      ? AppColors.textGray
                      : AppColors.darkGray,
                ),
              ),
            ),
            const Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _documentSection({
    required String title,
    required String keyName,
    required GuardDocumentForm doc,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        border: Border.all(color: AppColors.lightGray, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppColors.darkGray,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 220,
                child: TextFormField(
                  initialValue: doc.no,
                  decoration: _inputDecoration('$title Number'),
                  onChanged: (value) => doc.no = value,
                ),
              ),
              SizedBox(
                width: 220,
                child: _dateField(
                  label: 'Issue Date',
                  value: doc.issueDate,
                  onTap: () => _pickDate(
                    currentValue: doc.issueDate,
                    onSelected: (value) {
                      setState(() {
                        doc.issueDate = value;
                      });
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: _dateField(
                  label: 'Expiry Date',
                  value: doc.expiryDate,
                  onTap: () => _pickDate(
                    currentValue: doc.expiryDate,
                    onSelected: (value) {
                      setState(() {
                        doc.expiryDate = value;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...doc.imageUrls.asMap().entries.map((entry) {
                final int index = entry.key;
                final String url = entry.value;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.offWhite,
                        border: Border.all(color: AppColors.lightGray),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            doc.imageUrls.removeAt(index);
                          });
                        },
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.danger,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: AppColors.pureWhite,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              ...doc.selectedFiles.asMap().entries.map((entry) {
                final int index = entry.key;
                final XFile file = entry.value;
                return Container(
                  constraints: const BoxConstraints(maxWidth: 220),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: AppColors.offWhite,
                    border: Border.all(color: AppColors.lightGray),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.image_outlined,
                        size: 14,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          file.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.darkGray,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            doc.selectedFiles.removeAt(index);
                          });
                        },
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pickDocumentFiles(keyName),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              side: const BorderSide(color: AppColors.mediumGray, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              minimumSize: const Size(0, 42),
            ),
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: const Text('Select Images'),
          ),
        ],
      ),
    );
  }

  Widget _formSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightGray, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.primaryBlue, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = _guardId != null;

    return Dialog(
      backgroundColor: AppColors.pureWhite,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Guard Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkGray,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.lightGray),
                    ),
                    child: Text(
                      isEdit ? 'Edit' : 'New',
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            Navigator.of(context).pop(false);
                          },
                    color: AppColors.textGray,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.lightGray),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            _error,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                      _formSectionCard(
                        icon: Icons.person_outline_rounded,
                        title: 'Personal Information',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                SizedBox(
                                  width: 260,
                                  child: TextFormField(
                                    initialValue: _formData.name,
                                    decoration: _inputDecoration('Full Name *'),
                                    validator: (value) {
                                      if (_stringValue(value).trim().isEmpty) {
                                        return 'Name is required';
                                      }
                                      return null;
                                    },
                                    onChanged: (value) =>
                                        _formData.name = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 220,
                                  child: TextFormField(
                                    initialValue: _formData.phone,
                                    decoration: _inputDecoration('Phone *'),
                                    validator: (value) {
                                      if (_stringValue(value).trim().isEmpty) {
                                        return 'Phone is required';
                                      }
                                      return null;
                                    },
                                    onChanged: (value) =>
                                        _formData.phone = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 250,
                                  child: TextFormField(
                                    initialValue: _formData.email,
                                    decoration: _inputDecoration('Email'),
                                    onChanged: (value) =>
                                        _formData.email = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _formData.gender.isEmpty
                                        ? null
                                        : _formData.gender,
                                    decoration: _inputDecoration('Gender'),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'M',
                                        child: Text('Male'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'F',
                                        child: Text('Female'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Other',
                                        child: Text('Other'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      _formData.gender = _stringValue(value);
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _formData.type.isEmpty
                                        ? null
                                        : _formData.type,
                                    decoration: _inputDecoration('Type'),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'full-time',
                                        child: Text('full-time'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'part-time',
                                        child: Text('part-time'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      _formData.type = _stringValue(value);
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: _dateField(
                                    label: 'Date Of Birth',
                                    value: _formData.dob,
                                    onTap: () => _pickDate(
                                      currentValue: _formData.dob,
                                      onSelected: (value) {
                                        setState(() {
                                          _formData.dob = value;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: TextFormField(
                                    initialValue: _formData.weightKg,
                                    decoration: _inputDecoration('Weight (kg)'),
                                    onChanged: (value) =>
                                        _formData.weightKg = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: TextFormField(
                                    initialValue: _formData.heightCm,
                                    decoration: _inputDecoration('Height (cm)'),
                                    onChanged: (value) =>
                                        _formData.heightCm = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 300,
                                  child: TextFormField(
                                    initialValue: _formData.nationality,
                                    decoration: _inputDecoration(
                                      'Nationality (comma separated)',
                                    ),
                                    onChanged: (value) =>
                                        _formData.nationality = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 300,
                                  child: TextFormField(
                                    initialValue: _formData.language,
                                    decoration: _inputDecoration(
                                      'Languages (comma separated)',
                                    ),
                                    onChanged: (value) =>
                                        _formData.language = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 220,
                                  child: TextFormField(
                                    initialValue: _formData.password,
                                    decoration: _inputDecoration('Password'),
                                    onChanged: (value) =>
                                        _formData.password = value,
                                  ),
                                ),
                                SizedBox(
                                  width: 220,
                                  child: TextFormField(
                                    initialValue: _formData.defaultPay,
                                    decoration: _inputDecoration(
                                      'Default Pay Per Hour',
                                    ),
                                    onChanged: (value) =>
                                        _formData.defaultPay = value,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              initialValue: _formData.bio,
                              maxLines: 3,
                              decoration: _inputDecoration('Bio (Guard note)'),
                              onChanged: (value) => _formData.bio = value,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              initialValue: _formData.notes,
                              maxLines: 3,
                              decoration: _inputDecoration('Admin Notes'),
                              onChanged: (value) => _formData.notes = value,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _formSectionCard(
                        icon: Icons.badge_outlined,
                        title: 'Identity Documents',
                        child: Column(
                          children: [
                            _documentSection(
                              title: 'Emirates ID',
                              keyName: 'emiratesId',
                              doc: _formData.emiratesId,
                            ),
                            const SizedBox(height: 10),
                            _documentSection(
                              title: 'Passport',
                              keyName: 'passport',
                              doc: _formData.passport,
                            ),
                            const SizedBox(height: 10),
                            _documentSection(
                              title: 'SIRA Certificate',
                              keyName: 'sira',
                              doc: _formData.sira,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _formSectionCard(
                        icon: Icons.photo_camera_outlined,
                        title: 'Profile Photo',
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_formData.photo.isNotEmpty)
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.lightGray,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    _formData.photo,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            if (_formData.photoFile != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.offWhite,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.lightGray,
                                  ),
                                ),
                                child: Text(_formData.photoFile!.name),
                              ),
                            OutlinedButton.icon(
                              onPressed: _pickProfilePhoto,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryBlue,
                                side: const BorderSide(
                                  color: AppColors.mediumGray,
                                  width: 1,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                minimumSize: const Size(0, 42),
                              ),
                              icon: const Icon(Icons.upload_outlined, size: 18),
                              label: const Text('Select Profile Photo'),
                            ),
                            if (_formData.photo.isNotEmpty ||
                                _formData.photoFile != null)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _formData.photo = '';
                                    _formData.photoFile = null;
                                  });
                                },
                                child: const Text(
                                  'Remove',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.pureWhite,
                border: Border(
                  top: BorderSide(color: AppColors.lightGray, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            Navigator.of(context).pop(false);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textGray,
                      side: const BorderSide(
                        color: AppColors.mediumGray,
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: AppColors.pureWhite,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      minimumSize: const Size(0, 44),
                      elevation: 0,
                    ),
                    icon: Icon(
                      _submitting
                          ? Icons.hourglass_top_rounded
                          : Icons.check_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _submitting
                          ? 'Uploading Images & Saving...'
                          : isEdit
                          ? 'Update Guard'
                          : 'Add Guard',
                    ),
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

typedef GuardRefresh = Future<Map<String, dynamic>?> Function(String guardId);
typedef GuardToggleDocVerification =
    Future<Map<String, dynamic>?> Function(String guardId, String field);
typedef GuardAddComplaint =
    Future<Map<String, dynamic>?> Function(
      String guardId,
      String description,
      String severity,
      DateTime date,
    );

class GuardDetailsDialog extends StatefulWidget {
  const GuardDetailsDialog({
    super.key,
    required this.initialGuard,
    required this.onRefresh,
    required this.onToggleBlock,
    required this.onToggleVerified,
    required this.onToggleDocumentVerification,
    required this.onAddComplaint,
  });

  final Map<String, dynamic> initialGuard;
  final GuardRefresh onRefresh;
  final GuardRefresh onToggleBlock;
  final GuardRefresh onToggleVerified;
  final GuardToggleDocVerification onToggleDocumentVerification;
  final GuardAddComplaint onAddComplaint;

  @override
  State<GuardDetailsDialog> createState() => _GuardDetailsDialogState();
}

class _GuardDetailsDialogState extends State<GuardDetailsDialog> {
  final TextEditingController _complaintController = TextEditingController();

  late Map<String, dynamic> _guard;
  DateTime _complaintDate = DateTime.now();
  String _complaintSeverity = 'low';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _guard = Map<String, dynamic>.from(widget.initialGuard);
  }

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  String get _guardId => _stringValue(_guard['_id']);

  Future<void> _pickComplaintDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _complaintDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _complaintDate = picked;
    });
  }

  Future<void> _runAction(
    Future<Map<String, dynamic>?> Function() action,
  ) async {
    setState(() {
      _busy = true;
    });

    final Map<String, dynamic>? updated = await action();

    if (mounted && updated != null && updated.isNotEmpty) {
      setState(() {
        _guard = updated;
      });
    }

    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _submitComplaint() async {
    final String description = _complaintController.text.trim();
    if (description.isEmpty) {
      return;
    }

    await _runAction(() async {
      final Map<String, dynamic>? updated = await widget.onAddComplaint(
        _guardId,
        description,
        _complaintSeverity,
        _complaintDate,
      );

      if (updated != null) {
        _complaintController.clear();
        setState(() {
          _complaintSeverity = 'low';
          _complaintDate = DateTime.now();
        });
      }

      return updated;
    });
  }

  Widget _chip(String label, Color bg, Color fg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textGray),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.darkGray,
          ),
        ),
      ],
    );
  }

  Widget _pair(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 13, color: AppColors.darkGray),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentCard({
    required String title,
    required String keyName,
    required Map<String, dynamic> doc,
  }) {
    final bool verified = _boolValue(doc['verified']);
    final List<String> imageUrls = _stringListValue(doc['imageUrl']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.pureWhite,
        border: Border.all(color: AppColors.lightGray, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.darkGray,
                  ),
                ),
              ),
              Icon(
                verified ? Icons.check_circle : Icons.cancel,
                color: verified ? AppColors.success : AppColors.danger,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _pair('Number', _stringValue(doc['no'])),
          _pair('Issue Date', _displayDate(doc['issueDate'])),
          _pair('Expiry Date', _displayDate(doc['expiryDate'])),
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: imageUrls
                  .map(
                    (url) => Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.offWhite,
                        border: Border.all(color: AppColors.lightGray),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _runAction(
                    () =>
                        widget.onToggleDocumentVerification(_guardId, keyName),
                  ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkGray,
              side: const BorderSide(color: AppColors.mediumGray, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              minimumSize: const Size(0, 40),
            ),
            child: Text(verified ? 'Unverify $title' : 'Verify $title'),
          ),
        ],
      ),
    );
  }

  Widget _complaintsSection() {
    final List<Map<String, dynamic>> complaints = _mapListValue(
      _guard['complaints'],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Complaints Management',
          Icons.report_gmailerrorred_outlined,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.lightGray, width: 1),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _complaintController,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textGray,
                    ),
                    border: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.lightGray,
                        width: 1,
                      ),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.lightGray,
                        width: 1,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.primaryBlue,
                        width: 1.2,
                      ),
                    ),
                    filled: true,
                    fillColor: AppColors.pureWhite,
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _complaintSeverity,
                  decoration: InputDecoration(
                    labelText: 'Severity',
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textGray,
                    ),
                    border: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.lightGray,
                        width: 1,
                      ),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.lightGray,
                        width: 1,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.primaryBlue,
                        width: 1.2,
                      ),
                    ),
                    filled: true,
                    fillColor: AppColors.pureWhite,
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _complaintSeverity = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 170,
                child: InkWell(
                  onTap: _pickComplaintDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textGray,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.lightGray,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.lightGray,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.2,
                        ),
                      ),
                      filled: true,
                      fillColor: AppColors.pureWhite,
                      isDense: true,
                    ),
                    child: Text(_toDateInput(_complaintDate.toIso8601String())),
                  ),
                ),
              ),
              FilledButton(
                onPressed: _busy || _complaintController.text.trim().isEmpty
                    ? null
                    : _submitComplaint,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.pureWhite,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text('Add Complaint'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Complaint History (${complaints.length})',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.darkGray,
          ),
        ),
        const SizedBox(height: 8),
        if (complaints.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.lightGray),
            ),
            child: const Text(
              'No complaints recorded for this guard.',
              style: TextStyle(fontSize: 13, color: AppColors.textGray),
            ),
          )
        else
          Column(
            children: complaints.map((complaint) {
              final String severity = _stringValue(
                complaint['severity'],
              ).toLowerCase();
              final bool resolved = _boolValue(complaint['resolved']);
              final String severityLabel = severity.isEmpty
                  ? 'Low'
                  : '${severity[0].toUpperCase()}${severity.substring(1)}';

              Color severityBg;
              Color severityFg;
              if (severity == 'high') {
                severityBg = AppColors.danger.withValues(alpha: 0.12);
                severityFg = AppColors.danger;
              } else if (severity == 'medium') {
                severityBg = AppColors.warning.withValues(alpha: 0.12);
                severityFg = AppColors.warning;
              } else {
                severityBg = AppColors.success.withValues(alpha: 0.12);
                severityFg = AppColors.success;
              }

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.pureWhite,
                  border: Border.all(color: AppColors.lightGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(severityLabel, severityBg, severityFg),
                        _chip(
                          _displayDate(complaint['date']),
                          AppColors.lightGray,
                          AppColors.darkGray,
                        ),
                        _chip(
                          resolved ? 'Resolved' : 'Open',
                          resolved
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.danger.withValues(alpha: 0.12),
                          resolved ? AppColors.success : AppColors.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _stringValue(complaint['description']),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.darkGray,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = _stringValue(_guard['name']).isEmpty
        ? 'Unnamed Guard'
        : _stringValue(_guard['name']);
    final String photo = _stringValue(_guard['photo']);
    final bool block = _boolValue(_guard['block']);
    final bool verified = _boolValue(_guard['verified']);

    final Map<String, dynamic> emiratesId = _mapValue(_guard['emiratesId']);
    final Map<String, dynamic> passport = _mapValue(_guard['passport']);
    final Map<String, dynamic> sira = _mapValue(_guard['sira']);

    return Dialog(
      backgroundColor: AppColors.pureWhite,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1150, maxHeight: 780),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.badge_outlined,
                    color: AppColors.textGray,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Security Guard Details',
                      style: TextStyle(
                        color: AppColors.darkGray,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    color: AppColors.textGray,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.lightGray),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 18,
                      runSpacing: 14,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        Container(
                          width: 250,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: AppColors.pureWhite,
                            border: Border.all(color: AppColors.lightGray),
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 60,
                                backgroundColor: AppColors.lightGray,
                                backgroundImage: photo.isNotEmpty
                                    ? NetworkImage(photo)
                                    : null,
                                child: photo.isEmpty
                                    ? Text(
                                        name[0].toUpperCase(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 34,
                                          color: AppColors.textGray,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkGray,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  _chip(
                                    block ? 'Blocked' : 'Active',
                                    block
                                        ? AppColors.danger.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppColors.success.withValues(
                                            alpha: 0.12,
                                          ),
                                    block
                                        ? AppColors.danger
                                        : AppColors.success,
                                  ),
                                  _chip(
                                    verified ? 'Verified' : 'Unverified',
                                    verified
                                        ? AppColors.primaryBlue.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppColors.warning.withValues(
                                            alpha: 0.12,
                                          ),
                                    verified
                                        ? AppColors.primaryBlue
                                        : AppColors.warning,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 780,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _InfoCard(
                                title: 'Contact Information',
                                icon: Icons.phone_outlined,
                                lines: [
                                  _InfoLine(
                                    'Phone',
                                    _stringValue(_guard['phone']),
                                  ),
                                  _InfoLine(
                                    'Email',
                                    _stringValue(_guard['email']),
                                  ),
                                ],
                              ),
                              _InfoCard(
                                title: 'Personal Details',
                                icon: Icons.person_outline,
                                lines: [
                                  _InfoLine(
                                    'Gender',
                                    _stringValue(_guard['gender']),
                                  ),
                                  _InfoLine(
                                    'Date Of Birth',
                                    _displayDate(_guard['dob']),
                                  ),
                                  _InfoLine(
                                    'Weight',
                                    _stringValue(_guard['weightKg']).isEmpty
                                        ? ''
                                        : '${_stringValue(_guard['weightKg'])} kg',
                                  ),
                                  _InfoLine(
                                    'Height',
                                    _stringValue(_guard['heightCm']).isEmpty
                                        ? ''
                                        : '${_stringValue(_guard['heightCm'])} cm',
                                  ),
                                ],
                              ),
                              _InfoCard(
                                title: 'Nationality & Languages',
                                icon: Icons.public_outlined,
                                lines: [
                                  _InfoLine(
                                    'Nationality',
                                    _joined(_guard['nationality']),
                                  ),
                                  _InfoLine(
                                    'Languages',
                                    _joined(_guard['language']),
                                  ),
                                ],
                              ),
                              _InfoCard(
                                title: 'System Information',
                                icon: Icons.access_time_outlined,
                                lines: [
                                  _InfoLine(
                                    'Last Login',
                                    _displayDate(_guard['lastLogin']),
                                  ),
                                  _InfoLine(
                                    'Created',
                                    _displayDate(_guard['createdAt']),
                                  ),
                                  _InfoLine(
                                    'Updated',
                                    _displayDate(_guard['updatedAt']),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_stringValue(_guard['notes']).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _sectionTitle('Notes', Icons.sticky_note_2_outlined),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.pureWhite,
                          border: Border.all(color: AppColors.lightGray),
                        ),
                        child: Text(_stringValue(_guard['notes'])),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _sectionTitle('Identity Documents', Icons.badge_outlined),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 350,
                          child: _documentCard(
                            title: 'Emirates ID',
                            keyName: 'emiratesId',
                            doc: emiratesId,
                          ),
                        ),
                        SizedBox(
                          width: 350,
                          child: _documentCard(
                            title: 'Passport',
                            keyName: 'passport',
                            doc: passport,
                          ),
                        ),
                        SizedBox(
                          width: 350,
                          child: _documentCard(
                            title: 'SIRA',
                            keyName: 'sira',
                            doc: sira,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _complaintsSection(),
                    const SizedBox(height: 16),
                    _sectionTitle('Admin Actions', Icons.shield_outlined),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _runAction(
                                  () => widget.onToggleVerified(_guardId),
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: AppColors.pureWhite,
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            verified
                                ? 'Mark As Unverified'
                                : 'Mark As Verified',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _runAction(
                                  () => widget.onToggleBlock(_guardId),
                                ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: block
                                ? AppColors.success
                                : AppColors.danger,
                            side: BorderSide(
                              color: block
                                  ? AppColors.success
                                  : AppColors.danger,
                              width: 1,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(block ? 'Unblock Guard' : 'Block Guard'),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _runAction(
                                  () => widget.onRefresh(_guardId),
                                ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkGray,
                            side: const BorderSide(
                              color: AppColors.mediumGray,
                              width: 1,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                    if (_stringValue(_guard['bio']).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _sectionTitle('Guard Bio', Icons.person_outline),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.pureWhite,
                          border: Border.all(color: AppColors.lightGray),
                        ),
                        child: Text(_stringValue(_guard['bio'])),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final List<_InfoLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 382,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textGray),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.darkGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...lines.map((line) {
            final String value = line.value.trim().isEmpty ? '-' : line.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${line.label}: $value',
                style: const TextStyle(fontSize: 13, color: AppColors.darkGray),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class GuardDocumentForm {
  GuardDocumentForm({
    this.no = '',
    this.issueDate = '',
    this.expiryDate = '',
    List<String>? imageUrls,
    List<XFile>? selectedFiles,
    this.verified = false,
  }) : imageUrls = imageUrls ?? <String>[],
       selectedFiles = selectedFiles ?? <XFile>[];

  String no;
  String issueDate;
  String expiryDate;
  List<String> imageUrls;
  List<XFile> selectedFiles;
  bool verified;

  factory GuardDocumentForm.fromMap(dynamic value) {
    final Map<String, dynamic> map = _mapValue(value);

    return GuardDocumentForm(
      no: _stringValue(map['no']),
      issueDate: _toDateInput(map['issueDate']),
      expiryDate: _toDateInput(map['expiryDate']),
      imageUrls: _stringListValue(map['imageUrl']),
      verified: _boolValue(map['verified']),
    );
  }

  GuardDocumentForm copy() {
    return GuardDocumentForm(
      no: no,
      issueDate: issueDate,
      expiryDate: expiryDate,
      imageUrls: List<String>.from(imageUrls),
      selectedFiles: List<XFile>.from(selectedFiles),
      verified: verified,
    );
  }

  Map<String, dynamic> toPayload() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'no': no.trim(),
      'imageUrl': List<String>.from(imageUrls),
      'verified': verified,
    };

    if (issueDate.trim().isNotEmpty) {
      payload['issueDate'] = issueDate.trim();
    }
    if (expiryDate.trim().isNotEmpty) {
      payload['expiryDate'] = expiryDate.trim();
    }

    return payload;
  }
}

class GuardFormData {
  GuardFormData({
    required this.name,
    required this.phone,
    required this.email,
    required this.type,
    required this.password,
    required this.defaultPay,
    required this.gender,
    required this.photo,
    this.photoFile,
    required this.weightKg,
    required this.heightCm,
    required this.dob,
    required this.nationality,
    required this.language,
    required this.notes,
    required this.bio,
    required this.emiratesId,
    required this.passport,
    required this.sira,
  });

  String name;
  String phone;
  String email;
  String type;
  String password;
  String defaultPay;
  String gender;
  String photo;
  XFile? photoFile;
  String weightKg;
  String heightCm;
  String dob;
  String nationality;
  String language;
  String notes;
  String bio;
  GuardDocumentForm emiratesId;
  GuardDocumentForm passport;
  GuardDocumentForm sira;

  factory GuardFormData.empty() {
    return GuardFormData(
      name: '',
      phone: '',
      email: '',
      type: '',
      password: '',
      defaultPay: '0',
      gender: '',
      photo: '',
      weightKg: '',
      heightCm: '',
      dob: '',
      nationality: '',
      language: '',
      notes: '',
      bio: '',
      emiratesId: GuardDocumentForm(),
      passport: GuardDocumentForm(),
      sira: GuardDocumentForm(),
    );
  }

  factory GuardFormData.fromGuard(Map<String, dynamic> guard) {
    return GuardFormData(
      name: _stringValue(guard['name']),
      phone: _stringValue(guard['phone']),
      email: _stringValue(guard['email']),
      type: _stringValue(guard['type']),
      password: _stringValue(guard['password']),
      defaultPay: _numValue(guard['defaultPay']).toString(),
      gender: _stringValue(guard['gender']),
      photo: _stringValue(guard['photo']),
      weightKg: _stringValue(guard['weightKg']),
      heightCm: _stringValue(guard['heightCm']),
      dob: _toDateInput(guard['dob']),
      nationality: _joined(guard['nationality']),
      language: _joined(guard['language']),
      notes: _stringValue(guard['notes']),
      bio: _stringValue(guard['bio']),
      emiratesId: GuardDocumentForm.fromMap(guard['emiratesId']),
      passport: GuardDocumentForm.fromMap(guard['passport']),
      sira: GuardDocumentForm.fromMap(guard['sira']),
    );
  }

  GuardFormData copy() {
    return GuardFormData(
      name: name,
      phone: phone,
      email: email,
      type: type,
      password: password,
      defaultPay: defaultPay,
      gender: gender,
      photo: photo,
      photoFile: photoFile,
      weightKg: weightKg,
      heightCm: heightCm,
      dob: dob,
      nationality: nationality,
      language: language,
      notes: notes,
      bio: bio,
      emiratesId: emiratesId.copy(),
      passport: passport.copy(),
      sira: sira.copy(),
    );
  }

  Map<String, dynamic> toPayload() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'type': type.trim(),
      'defaultPay': num.tryParse(defaultPay.trim()) ?? 0,
      'gender': gender.trim(),
      'photo': photo.trim(),
      'weightKg': weightKg.trim(),
      'heightCm': heightCm.trim(),
      'dob': dob.trim(),
      'nationality': _csvToList(nationality),
      'language': _csvToList(language),
      'notes': notes.trim(),
      'bio': bio.trim(),
      'emiratesId': emiratesId.toPayload(),
      'passport': passport.toPayload(),
      'sira': sira.toPayload(),
    };

    if (password.trim().isNotEmpty) {
      payload['password'] = password.trim();
    }

    return payload;
  }
}
