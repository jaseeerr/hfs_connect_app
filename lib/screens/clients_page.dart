import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../widget/app_bottom_nav_bar.dart';

class _ClientColors {
  const _ClientColors._();

  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF8FAFC);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color dangerRed = Color(0xFFDC2626);
}

class _DeleteClientCountdownDialog extends StatefulWidget {
  const _DeleteClientCountdownDialog();

  @override
  State<_DeleteClientCountdownDialog> createState() =>
      _DeleteClientCountdownDialogState();
}

class _DeleteClientCountdownDialogState
    extends State<_DeleteClientCountdownDialog> {
  static const int _initialCountdownMs = 3000;
  static const int _tickMs = 100;

  int _remainingMs = _initialCountdownMs;
  Timer? _timer;

  bool get _canDelete => _remainingMs <= 0;

  String get _countdownLabel {
    final double seconds = _remainingMs / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _remainingMs -= _tickMs;
        if (_remainingMs <= 0) {
          _remainingMs = 0;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Client'),
      content: const Text('Are you sure you want to delete this client?'),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: _ClientColors.darkGray,
            side: const BorderSide(color: _ClientColors.mediumGray, width: 1),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canDelete ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: _ClientColors.dangerRed,
            foregroundColor: _ClientColors.pureWhite,
          ),
          child: Text(_canDelete ? 'Delete' : _countdownLabel),
        ),
      ],
    );
  }
}

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  static const List<String> _businessTypes = <String>[
    'restaurant',
    'bar',
    'club',
    'event',
    'retail',
    'office',
    'warehouse',
    'other',
  ];

  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _clients = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _isSuperUser = false;
  String _searchTerm = '';

  Dio _api() => ApiClient.create(opt: 0, token: AuthStorage.token);

  @override
  void initState() {
    super.initState();
    _loadSuperUser();
    _fetchClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
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

  String _errorMessage(Object error) {
    if (error is DioException) {
      final Map<String, dynamic> body = _asMap(error.response?.data);
      final String apiError = _asString(body['error']).trim();
      final String apiMessage = _asString(body['message']).trim();

      if (apiError.isNotEmpty) {
        return apiError;
      }
      if (apiMessage.isNotEmpty) {
        return apiMessage;
      }
      if (_asString(error.message).isNotEmpty) {
        return _asString(error.message);
      }
    }

    return _asString(error).replaceFirst('Exception: ', '');
  }

  Future<void> _loadSuperUser() async {
    try {
      if (!Hive.isBoxOpen('auth_box')) {
        await Hive.openBox<dynamic>('auth_box');
      }
      final dynamic value = Hive.box<dynamic>('auth_box').get('superUser');
      if (mounted) {
        setState(() {
          _isSuperUser = _asString(value).toLowerCase() == 'true';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSuperUser = false;
        });
      }
    }
  }

  Future<void> _fetchClients({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final Response<dynamic> response = await _api().get('/clients');
      final Map<String, dynamic> body = _asMap(response.data);

      if (body['ok'] == true) {
        if (mounted) {
          setState(() {
            _clients = _asMapList(body['data']);
          });
        }
      } else {
        throw Exception(
          _asString(body['error']).isNotEmpty
              ? _asString(body['error'])
              : 'Failed to load clients',
        );
      }
    } catch (error) {
      _showSnack(_errorMessage(error), isError: true);
    } finally {
      if (showLoader && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<String> _uploadLogoToCloudinary(XFile file) async {
    final String filename =
        'client-logo-${DateTime.now().millisecondsSinceEpoch}-${file.name}';

    final FormData data = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: filename),
      'upload_preset': 'HFS_Other',
      'cloud_name': 'dfethvtz3',
    });

    final Response<dynamic> response = await Dio().post(
      'https://api.cloudinary.com/v1_1/dfethvtz3/auto/upload',
      data: data,
    );

    final String url = _asString(_asMap(response.data)['secure_url']).trim();
    if (url.isEmpty) {
      throw Exception('Error uploading logo');
    }
    return url;
  }

  Future<void> _saveClient(
    _ClientFormData formData,
    XFile? logoFile,
    String? clientId,
  ) async {
    String logoUrl = formData.logo.trim();
    if (logoFile != null) {
      logoUrl = await _uploadLogoToCloudinary(logoFile);
    }

    final Map<String, dynamic> payload = formData.toPayload(logoUrl: logoUrl);

    final Response<dynamic> response = clientId == null || clientId.isEmpty
        ? await _api().post('/clients', data: payload)
        : await _api().put('/clients/$clientId', data: payload);

    final Map<String, dynamic> body = _asMap(response.data);
    if (body['ok'] != true) {
      throw Exception(
        _asString(body['error']).isNotEmpty
            ? _asString(body['error'])
            : 'Failed to save client',
      );
    }

    await _fetchClients(showLoader: false);
  }

  Future<void> _deleteClient(String clientId) async {
    final bool shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (_) => const _DeleteClientCountdownDialog(),
        ) ??
        false;

    if (!shouldDelete) {
      return;
    }

    try {
      final Response<dynamic> response = await _api().delete(
        '/clients/$clientId',
      );
      final Map<String, dynamic> body = _asMap(response.data);

      if (body['ok'] != true) {
        throw Exception(
          _asString(body['error']).isNotEmpty
              ? _asString(body['error'])
              : 'Failed to delete client',
        );
      }

      await _fetchClients(showLoader: false);
      _showSnack('Client deleted successfully');
    } catch (error) {
      _showSnack(_errorMessage(error), isError: true);
    }
  }

  Future<void> _openClientForm({Map<String, dynamic>? client}) async {
    final String? clientId = _asString(client?['_id']).trim().isEmpty
        ? null
        : _asString(client?['_id']).trim();

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _ClientFormDialog(
          picker: _picker,
          initialData: client == null
              ? _ClientFormData.empty()
              : _ClientFormData.fromClient(client),
          clientId: clientId,
          businessTypes: _businessTypes,
          onSubmit: _saveClient,
          errorMessageBuilder: _errorMessage,
        );
      },
    );

    if (!mounted || saved != true) {
      return;
    }

    _showSnack(
      clientId == null
          ? 'Client added successfully'
          : 'Client updated successfully',
    );
  }

  Future<void> _openClientDetails(Map<String, dynamic> client) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ClientDetailsDialog(client: client),
    );
  }

  List<Map<String, dynamic>> get _filteredClients {
    final String query = _searchTerm.trim().toLowerCase();
    if (query.isEmpty) {
      return _clients;
    }

    return _clients.where((Map<String, dynamic> client) {
      final String name = _asString(client['name']).toLowerCase();
      final String contactPerson = _asString(
        client['contactPerson'],
      ).toLowerCase();
      final String email = _asString(client['email']).toLowerCase();
      final String phone = _asString(client['contactPhone']).toLowerCase();

      return name.contains(query) ||
          contactPerson.contains(query) ||
          email.contains(query) ||
          phone.contains(query);
    }).toList();
  }

  String _formatType(dynamic value) {
    final String raw = _asString(value).trim();
    if (raw.isEmpty) {
      return 'No type specified';
    }
    final String withSpaces = raw.replaceAll('-', ' ');
    return withSpaces
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.length > 1 ? word.substring(1) : ''}',
        )
        .join(' ');
  }

  Widget _buildCardAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive
            ? _ClientColors.dangerRed
            : _ClientColors.darkGray,
        side: BorderSide(
          color: destructive
              ? _ClientColors.dangerRed.withValues(alpha: 0.45)
              : _ClientColors.mediumGray,
          width: 1,
        ),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  Widget _buildInfoRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _ClientColors.textGray),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.trim().isEmpty ? '-' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: _ClientColors.darkGray,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClientCard(Map<String, dynamic> client, bool isSmallScreen) {
    final String clientId = _asString(client['_id']).trim();
    final String name = _asString(client['name']).trim().isEmpty
        ? 'Unnamed client'
        : _asString(client['name']).trim();
    final String type = _formatType(client['type']);
    final String logo = _asString(client['logo']).trim();

    final List<Widget> actions = <Widget>[
      _buildCardAction(
        icon: Icons.visibility_outlined,
        label: 'View',
        onTap: () => _openClientDetails(client),
      ),
      _buildCardAction(
        icon: Icons.edit_outlined,
        label: 'Edit',
        onTap: () => _openClientForm(client: client),
      ),
      if (_isSuperUser)
        _buildCardAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          onTap: clientId.isEmpty ? () {} : () => _deleteClient(clientId),
          destructive: true,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _ClientColors.pureWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ClientColors.lightGray, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _ClientColors.offWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _ClientColors.lightGray),
                ),
                alignment: Alignment.center,
                child: logo.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.network(
                          logo,
                          fit: BoxFit.cover,
                          width: 48,
                          height: 48,
                          errorBuilder: (_, __, ___) {
                            return const Icon(
                              Icons.business_outlined,
                              color: _ClientColors.textGray,
                              size: 20,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.business_outlined,
                        color: _ClientColors.textGray,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _ClientColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _ClientColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            Icons.person_outline,
            _asString(client['contactPerson']),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.phone_outlined,
            _asString(client['contactPhone']),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.mail_outline, _asString(client['email'])),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.location_on_outlined,
            _asString(client['address']),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (int i = 0; i < actions.length; i++) ...[
                Expanded(child: actions[i]),
                if (i < actions.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          if (isSmallScreen) const SizedBox(height: 2),
        ],
      ),
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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _ClientColors.pureWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _ClientColors.lightGray),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: _ClientColors.offWhite,
                    foregroundColor: _ClientColors.textGray,
                  ),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clients Management',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          color: _ClientColors.darkGray,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage client companies and organizations',
                        style: TextStyle(
                          fontSize: 13,
                          color: _ClientColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (isSmallScreen) ...[
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchTerm = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search clients...',
                  hintStyle: const TextStyle(
                    color: _ClientColors.textGray,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: _ClientColors.textGray,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: _ClientColors.pureWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: _ClientColors.lightGray,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: _ClientColors.lightGray,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: _ClientColors.primaryBlue,
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
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openClientForm(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ClientColors.primaryBlue,
                    foregroundColor: _ClientColors.pureWhite,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Client'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchTerm = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search clients...',
                        hintStyle: const TextStyle(
                          color: _ClientColors.textGray,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: _ClientColors.textGray,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: _ClientColors.pureWhite,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _ClientColors.lightGray,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _ClientColors.lightGray,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _ClientColors.primaryBlue,
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
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _openClientForm(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _ClientColors.primaryBlue,
                      foregroundColor: _ClientColors.pureWhite,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Client'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _ClientColors.pureWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _ClientColors.lightGray),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.business_outlined,
              size: 52,
              color: _ClientColors.textGray,
            ),
            SizedBox(height: 12),
            Text(
              'No clients found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _ClientColors.darkGray,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Get started by adding your first client.',
              style: TextStyle(fontSize: 13, color: _ClientColors.textGray),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 12),
            Text(
              'Loading clients...',
              style: TextStyle(fontSize: 13, color: _ClientColors.textGray),
            ),
          ],
        ),
      );
    }

    final List<Map<String, dynamic>> filtered = _filteredClients;
    if (filtered.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _fetchClients,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isSmallScreen = constraints.maxWidth < 780;

          if (isSmallScreen) {
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) =>
                  _buildClientCard(filtered[index], true),
            );
          }

          final int columns = constraints.maxWidth > 1250 ? 3 : 2;

          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: filtered.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: constraints.maxWidth > 1250 ? 1.28 : 1.14,
            ),
            itemBuilder: (_, index) => _buildClientCard(filtered[index], false),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 780;

    return Scaffold(
      backgroundColor: _ClientColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isSmallScreen),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 3),
    );
  }
}

typedef _ClientFormSubmit =
    Future<void> Function(
      _ClientFormData data,
      XFile? logoFile,
      String? clientId,
    );

class _ClientFormDialog extends StatefulWidget {
  const _ClientFormDialog({
    required this.picker,
    required this.initialData,
    required this.clientId,
    required this.businessTypes,
    required this.onSubmit,
    required this.errorMessageBuilder,
  });

  final ImagePicker picker;
  final _ClientFormData initialData;
  final String? clientId;
  final List<String> businessTypes;
  final _ClientFormSubmit onSubmit;
  final String Function(Object error) errorMessageBuilder;

  @override
  State<_ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<_ClientFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late _ClientFormData _formData;
  XFile? _logoFile;
  String _logoPreview = '';
  bool _submitting = false;
  String _error = '';

  bool get _isEditMode =>
      widget.clientId != null && widget.clientId!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _formData = widget.initialData.copy();
    _logoPreview = _formData.logo;
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _ClientColors.textGray,
      ),
      filled: true,
      fillColor: _ClientColors.pureWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _ClientColors.lightGray, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _ClientColors.lightGray, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: _ClientColors.primaryBlue,
          width: 1.2,
        ),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<void> _pickLogo() async {
    final XFile? file = await widget.picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (file == null) {
      return;
    }

    setState(() {
      _logoFile = file;
      _logoPreview = '';
      _formData.logo = '';
    });
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
      _logoPreview = '';
      _formData.logo = '';
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      await widget.onSubmit(_formData, _logoFile, widget.clientId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _ClientColors.pureWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditMode ? 'Edit Client' : 'Add New Client',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: _ClientColors.darkGray,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    color: _ClientColors.textGray,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: _ClientColors.lightGray,
            ),
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
                            color: _ClientColors.dangerRed.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _ClientColors.dangerRed.withValues(
                                alpha: 0.25,
                              ),
                            ),
                          ),
                          child: Text(
                            _error,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _ClientColors.dangerRed,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 260,
                            child: TextFormField(
                              initialValue: _formData.name,
                              decoration: _inputDecoration('Company Name *'),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Company name is required';
                                }
                                return null;
                              },
                              onChanged: (value) => _formData.name = value,
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              initialValue: _formData.type.trim().isEmpty
                                  ? null
                                  : _formData.type,
                              decoration: _inputDecoration('Business Type'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('Select type'),
                                ),
                                ...widget.businessTypes.map(
                                  (type) => DropdownMenuItem<String>(
                                    value: type,
                                    child: Text(
                                      type[0].toUpperCase() +
                                          (type.length > 1
                                              ? type.substring(1)
                                              : ''),
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                _formData.type = value ?? '';
                              },
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              initialValue: _formData.contactPerson,
                              decoration: _inputDecoration('Contact Person'),
                              onChanged: (value) =>
                                  _formData.contactPerson = value,
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              initialValue: _formData.contactPhone,
                              decoration: _inputDecoration('Contact Phone'),
                              keyboardType: TextInputType.phone,
                              onChanged: (value) =>
                                  _formData.contactPhone = value,
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: TextFormField(
                              initialValue: _formData.email,
                              decoration: _inputDecoration('Email'),
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (value) => _formData.email = value,
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: TextFormField(
                              initialValue: _formData.website,
                              decoration: _inputDecoration('Website'),
                              keyboardType: TextInputType.url,
                              onChanged: (value) => _formData.website = value,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _ClientColors.pureWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _ClientColors.lightGray),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Company Logo (Optional)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _ClientColors.darkGray,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_logoFile != null || _logoPreview.isNotEmpty)
                              Row(
                                children: [
                                  Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      color: _ClientColors.offWhite,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _ClientColors.lightGray,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: _logoFile != null
                                          ? Image.file(
                                              File(_logoFile!.path),
                                              fit: BoxFit.cover,
                                            )
                                          : Image.network(
                                              _logoPreview,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) {
                                                return const Icon(
                                                  Icons.broken_image_outlined,
                                                  color: _ClientColors.textGray,
                                                );
                                              },
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Logo selected',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _ClientColors.textGray,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        TextButton.icon(
                                          onPressed: _removeLogo,
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                _ClientColors.dangerRed,
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(0, 32),
                                          ),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 16,
                                          ),
                                          label: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _ClientColors.offWhite,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.upload_outlined,
                                      color: _ClientColors.textGray,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Upload company logo',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: _ClientColors.textGray,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _pickLogo,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _ClientColors.darkGray,
                                side: const BorderSide(
                                  color: _ClientColors.mediumGray,
                                  width: 1,
                                ),
                                minimumSize: const Size(0, 42),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: const Text('Choose File'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _formData.address,
                        decoration: _inputDecoration('Address'),
                        onChanged: (value) => _formData.address = value,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: _formData.locationUrl,
                        decoration: _inputDecoration(
                          'Location URL (Google Maps)',
                          hint: 'https://maps.google.com/...',
                        ),
                        keyboardType: TextInputType.url,
                        onChanged: (value) => _formData.locationUrl = value,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: _formData.note,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          'Internal Notes',
                          hint: 'Internal notes for admin use...',
                        ),
                        onChanged: (value) => _formData.note = value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: _ClientColors.pureWhite,
                border: Border(
                  top: BorderSide(color: _ClientColors.lightGray, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ClientColors.darkGray,
                        side: const BorderSide(
                          color: _ClientColors.mediumGray,
                          width: 1,
                        ),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _ClientColors.primaryBlue,
                        foregroundColor: _ClientColors.pureWhite,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _submitting
                            ? (_isEditMode ? 'Updating...' : 'Adding...')
                            : (_isEditMode ? 'Update Client' : 'Add Client'),
                      ),
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

class _ClientDetailsDialog extends StatelessWidget {
  const _ClientDetailsDialog({required this.client});

  final Map<String, dynamic> client;

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  String _formatType(dynamic value) {
    final String raw = _asString(value).trim();
    if (raw.isEmpty) {
      return 'Not specified';
    }
    final String withSpaces = raw.replaceAll('-', ' ');
    return withSpaces
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.length > 1 ? word.substring(1) : ''}',
        )
        .join(' ');
  }

  String _formatDate(dynamic value) {
    final DateTime? date = DateTime.tryParse(_asString(value));
    if (date == null) {
      return '-';
    }
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _ClientColors.darkGray,
      ),
    );
  }

  Widget _line(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _ClientColors.textGray,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value.trim().isEmpty ? '-' : value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _ClientColors.darkGray,
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ClientColors.pureWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ClientColors.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_sectionTitle(title), const SizedBox(height: 12), child],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String logo = _asString(client['logo']).trim();

    return Dialog(
      backgroundColor: _ClientColors.pureWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Client Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: _ClientColors.darkGray,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    color: _ClientColors.textGray,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: _ClientColors.lightGray,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _sectionCard(
                      title: 'Company Information',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              SizedBox(
                                width: 250,
                                child: _line(
                                  'Company Name',
                                  _asString(client['name']),
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: _line(
                                  'Business Type',
                                  _formatType(client['type']),
                                ),
                              ),
                              SizedBox(
                                width: 250,
                                child: _line(
                                  'Website',
                                  _asString(client['website']),
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: _line(
                                  'Created',
                                  _formatDate(client['createdAt']),
                                ),
                              ),
                            ],
                          ),
                          if (logo.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Company Logo',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _ClientColors.textGray,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _ClientColors.lightGray,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.network(
                                  logo,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return const Icon(
                                      Icons.broken_image_outlined,
                                      color: _ClientColors.textGray,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: 'Contact Information',
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          SizedBox(
                            width: 250,
                            child: _line(
                              'Contact Person',
                              _asString(client['contactPerson']),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: _line(
                              'Contact Phone',
                              _asString(client['contactPhone']),
                            ),
                          ),
                          SizedBox(
                            width: 484,
                            child: _line('Email', _asString(client['email'])),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: 'Location Information',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _line('Address', _asString(client['address'])),
                          const SizedBox(height: 12),
                          _line(
                            'Location URL',
                            _asString(client['locationUrl']),
                          ),
                        ],
                      ),
                    ),
                    if (_asString(client['note']).trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _sectionCard(
                        title: 'Internal Notes',
                        child: Text(
                          _asString(client['note']),
                          style: const TextStyle(
                            fontSize: 14,
                            color: _ClientColors.darkGray,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: _ClientColors.pureWhite,
                border: Border(
                  top: BorderSide(color: _ClientColors.lightGray, width: 1),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ClientColors.primaryBlue,
                    foregroundColor: _ClientColors.pureWhite,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientFormData {
  _ClientFormData({
    required this.name,
    required this.type,
    required this.contactPerson,
    required this.contactPhone,
    required this.email,
    required this.website,
    required this.logo,
    required this.address,
    required this.locationUrl,
    required this.note,
  });

  String name;
  String type;
  String contactPerson;
  String contactPhone;
  String email;
  String website;
  String logo;
  String address;
  String locationUrl;
  String note;

  factory _ClientFormData.empty() {
    return _ClientFormData(
      name: '',
      type: '',
      contactPerson: '',
      contactPhone: '',
      email: '',
      website: '',
      logo: '',
      address: '',
      locationUrl: '',
      note: '',
    );
  }

  factory _ClientFormData.fromClient(Map<String, dynamic> client) {
    return _ClientFormData(
      name: _string(client['name']),
      type: _string(client['type']),
      contactPerson: _string(client['contactPerson']),
      contactPhone: _string(client['contactPhone']),
      email: _string(client['email']),
      website: _string(client['website']),
      logo: _string(client['logo']),
      address: _string(client['address']),
      locationUrl: _string(client['locationUrl']),
      note: _string(client['note']),
    );
  }

  _ClientFormData copy() {
    return _ClientFormData(
      name: name,
      type: type,
      contactPerson: contactPerson,
      contactPhone: contactPhone,
      email: email,
      website: website,
      logo: logo,
      address: address,
      locationUrl: locationUrl,
      note: note,
    );
  }

  Map<String, dynamic> toPayload({required String logoUrl}) {
    return <String, dynamic>{
      'name': name.trim(),
      'type': type.trim(),
      'contactPerson': contactPerson.trim(),
      'contactPhone': contactPhone.trim(),
      'email': email.trim(),
      'website': website.trim(),
      'logo': logoUrl.trim(),
      'address': address.trim(),
      'locationUrl': locationUrl.trim(),
      'note': note.trim(),
    };
  }

  static String _string(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }
}
