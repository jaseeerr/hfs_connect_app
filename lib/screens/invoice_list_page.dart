import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_routes.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../widget/app_bottom_nav_bar.dart';

class _InvoiceListColors {
  const _InvoiceListColors._();

  static const Color primaryBlue = Color(0xFF2563EB);

  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pageBackground = Color(0xFFF3F4F6);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color surfaceMuted = Color(0xFFF8FAFC);

  static const Color warningStripe = Color(0xFFD97706);

  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFDC2626);
}

enum _InvoicePaymentStatus { paid, partial, unpaid }

class InvoiceListPage extends StatefulWidget {
  const InvoiceListPage({super.key});

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _isSuperUser = false;
  String _sortOrder = 'latest';
  String _selectedClient = 'all';
  String _searchTerm = '';
  String? _deletingId;

  List<Map<String, dynamic>> _invoices = <Map<String, dynamic>>[];

  String _asString(dynamic value) => value == null ? '' : value.toString();

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_asString(value)) ?? 0;
  }

  String _isoDate(DateTime date) {
    final DateTime local = date.toLocal();
    final String year = local.year.toString().padLeft(4, '0');
    final String month = local.month.toString().padLeft(2, '0');
    final String day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _money(double value) => 'AED ${value.toStringAsFixed(2)}';

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

  String _errorMessage(Object err) {
    if (err is DioException) {
      final Map<String, dynamic> body = _asMap(err.response?.data);
      final String e = _asString(body['error']).trim();
      final String m = _asString(body['message']).trim();
      if (e.isNotEmpty) {
        return e;
      }
      if (m.isNotEmpty) {
        return m;
      }
      final String fallback = _asString(err.message).trim();
      if (fallback.isNotEmpty) {
        return fallback;
      }
    }
    return _asString(err).replaceFirst('Exception: ', '');
  }

  @override
  void initState() {
    super.initState();
    _loadSuperUser();
    _fetchInvoices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuperUser() async {
    if (!Hive.isBoxOpen('auth_box')) {
      await Hive.openBox<dynamic>('auth_box');
    }
    final dynamic value = Hive.box<dynamic>('auth_box').get('superUser');
    if (!mounted) {
      return;
    }
    setState(() {
      _isSuperUser = _asString(value).toLowerCase() == 'true';
    });
  }

  Future<void> _fetchInvoices() async {
    setState(() => _loading = true);
    try {
      final Response<dynamic> res = await ApiClient.create(
        opt: 0,
        token: AuthStorage.token,
      ).get('/listInvoices');
      if (!mounted) {
        return;
      }
      setState(() {
        _invoices = _asMapList(_asMap(res.data)['data']);
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(err)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteInvoice(Map<String, dynamic> invoice) async {
    if (!_isSuperUser) {
      return;
    }
    final String id = _asString(invoice['_id']).trim();
    if (id.isEmpty) {
      return;
    }
    final bool shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: const Text('Delete Invoice'),
            content: Text(
              'Are you sure you want to delete invoice ${_asString(invoice['invoiceNo'])}?',
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: _outlinedButtonStyle(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: _InvoiceListColors.danger,
                  foregroundColor: _InvoiceListColors.pureWhite,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete) {
      return;
    }

    setState(() => _deletingId = id);
    try {
      await ApiClient.create(
        opt: 0,
        token: AuthStorage.token,
      ).delete('/deleteInvoice/$id');
      if (!mounted) {
        return;
      }
      setState(() {
        _invoices.removeWhere((inv) => _asString(inv['_id']) == id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice deleted successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(err)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingId = null);
      }
    }
  }

  List<String> get _uniqueClients {
    final Set<String> values = _invoices
        .map((inv) => _asString(inv['clientName']).trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final List<String> clients = values.toList()..sort();
    return clients;
  }

  List<Map<String, dynamic>> get _filteredInvoices {
    final String query = _searchTerm.trim().toLowerCase();
    final List<Map<String, dynamic>> result = _invoices.where((inv) {
      final String invoiceNo = _asString(inv['invoiceNo']).toLowerCase();
      final String clientName = _asString(inv['clientName']).toLowerCase();
      final bool matchesSearch =
          query.isEmpty ||
          invoiceNo.contains(query) ||
          clientName.contains(query);
      final bool matchesClient =
          _selectedClient == 'all' ||
          _asString(inv['clientName']) == _selectedClient;
      return matchesSearch && matchesClient;
    }).toList();

    result.sort((a, b) {
      final DateTime da =
          DateTime.tryParse(_asString(a['invoiceDate'])) ?? DateTime(1970);
      final DateTime db =
          DateTime.tryParse(_asString(b['invoiceDate'])) ?? DateTime(1970);
      return _sortOrder == 'latest' ? db.compareTo(da) : da.compareTo(db);
    });
    return result;
  }

  _InvoicePaymentStatus _statusOf(Map<String, dynamic> invoice) {
    final double totalAmount = _asDouble(invoice['totalAmount']);
    final double totalReceived = _asDouble(invoice['totalReceived']);
    if (totalAmount > 0 && totalReceived >= totalAmount) {
      return _InvoicePaymentStatus.paid;
    }
    if (totalReceived > 0) {
      return _InvoicePaymentStatus.partial;
    }
    return _InvoicePaymentStatus.unpaid;
  }

  Color _statusColor(_InvoicePaymentStatus status) {
    switch (status) {
      case _InvoicePaymentStatus.paid:
        return _InvoiceListColors.success;
      case _InvoicePaymentStatus.partial:
        return _InvoiceListColors.warningStripe;
      case _InvoicePaymentStatus.unpaid:
        return _InvoiceListColors.danger;
    }
  }

  String _statusLabel(_InvoicePaymentStatus status) {
    switch (status) {
      case _InvoicePaymentStatus.paid:
        return 'Paid';
      case _InvoicePaymentStatus.partial:
        return 'Partial';
      case _InvoicePaymentStatus.unpaid:
        return 'Unpaid';
    }
  }

  BoxDecoration _backgroundGradient() {
    return const BoxDecoration(color: _InvoiceListColors.pageBackground);
  }

  Widget _glassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    bool hoverable = true,
  }) {
    return _HoverCard(
      hoverable: hoverable,
      elevation: 1.5,
      hoverElevation: 4,
      borderRadius: BorderRadius.circular(16),
      borderColor: _InvoiceListColors.lightGray,
      child: Padding(padding: padding, child: child),
    );
  }

  ButtonStyle _outlinedButtonStyle({
    Color color = _InvoiceListColors.primaryBlue,
    Color? borderColor,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: borderColor ?? _InvoiceListColors.mediumGray),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _InvoiceListColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _InvoiceListColors.lightGray),
          ),
          child: Icon(icon, size: 18, color: _InvoiceListColors.primaryBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _InvoiceListColors.darkGray,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _statPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: _InvoiceListColors.textGray,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(_InvoicePaymentStatus status) {
    final Color color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _detailLine({
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: _InvoiceListColors.textGray,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: color ?? _InvoiceListColors.darkGray,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _emptyBlock({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return _HoverCard(
      hoverable: false,
      elevation: 0,
      hoverElevation: 0,
      borderRadius: BorderRadius.circular(14),
      borderColor: _InvoiceListColors.lightGray,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: _InvoiceListColors.mediumGray),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _InvoiceListColors.darkGray,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _InvoiceListColors.textGray,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    double totalInvoiced,
    double totalReceived,
    double totalPending,
  ) {
    return _glassPanel(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _InvoiceListColors.primaryBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invoice Management',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _InvoiceListColors.darkGray,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Manage and track all invoices in one place.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _InvoiceListColors.textGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statPill(
                label: 'Total',
                value: _invoices.length.toString(),
                color: _InvoiceListColors.primaryBlue,
              ),
              _statPill(
                label: 'Invoiced',
                value: _money(totalInvoiced),
                color: _InvoiceListColors.primaryBlue,
              ),
              _statPill(
                label: 'Received',
                value: _money(totalReceived),
                color: _InvoiceListColors.success,
              ),
              _statPill(
                label: 'Pending',
                value: _money(totalPending),
                color: _InvoiceListColors.warningStripe,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(int filteredCount, int totalCount) {
    return _glassPanel(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon: Icons.tune_rounded, title: 'Filters'),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchTerm = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: _InvoiceListColors.textGray,
              ),
              hintText: 'Search invoice number or client',
              hintStyle: const TextStyle(
                color: _InvoiceListColors.textGray,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: _InvoiceListColors.pureWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: _InvoiceListColors.lightGray,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: _InvoiceListColors.lightGray,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: _InvoiceListColors.primaryBlue,
                  width: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _sortOrder,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Sort',
                    labelStyle: const TextStyle(
                      color: _InvoiceListColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                    filled: true,
                    fillColor: _InvoiceListColors.pureWhite,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _InvoiceListColors.lightGray,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _InvoiceListColors.lightGray,
                      ),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'latest',
                      child: Text('Latest First'),
                    ),
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text('Oldest First'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _sortOrder = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedClient,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Client',
                    labelStyle: const TextStyle(
                      color: _InvoiceListColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                    filled: true,
                    fillColor: _InvoiceListColors.pureWhite,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _InvoiceListColors.lightGray,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _InvoiceListColors.lightGray,
                      ),
                    ),
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Clients'),
                    ),
                    ..._uniqueClients.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedClient = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Showing $filteredCount of $totalCount invoices',
            style: const TextStyle(
              fontSize: 12,
              color: _InvoiceListColors.textGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceCard(Map<String, dynamic> invoice, double cardWidth) {
    final String id = _asString(invoice['_id']);
    final double totalAmount = _asDouble(invoice['totalAmount']);
    final double totalReceived = _asDouble(invoice['totalReceived']);
    final double totalHours = _asDouble(invoice['totalHours']);
    final _InvoicePaymentStatus status = _statusOf(invoice);
    final Color statusColor = _statusColor(status);

    final DateTime? invoiceDate = DateTime.tryParse(
      _asString(invoice['invoiceDate']),
    );
    final DateTime? dueDate = DateTime.tryParse(_asString(invoice['dueDate']));
    final String description = _asString(invoice['description']).trim();

    final String invoiceNo = _asString(invoice['invoiceNo']).trim().isEmpty
        ? 'No Invoice No'
        : _asString(invoice['invoiceNo']).trim();
    final String clientName = _asString(invoice['clientName']).trim().isEmpty
        ? 'Unnamed Client'
        : _asString(invoice['clientName']).trim();

    return SizedBox(
      width: cardWidth,
      child: _HoverCard(
        hoverable: true,
        elevation: 1.2,
        hoverElevation: 5,
        borderRadius: BorderRadius.circular(14),
        borderColor: _InvoiceListColors.lightGray,
        leftAccentColor: statusColor,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      invoiceNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _InvoiceListColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _InvoiceListColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _InvoiceListColors.lightGray),
                    ),
                    child: const Icon(
                      Icons.business_rounded,
                      size: 16,
                      color: _InvoiceListColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _InvoiceListColors.darkGray,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _detailLine(
                label: 'Invoice Date',
                value: invoiceDate == null ? '-' : _isoDate(invoiceDate),
              ),
              const SizedBox(height: 6),
              _detailLine(
                label: 'Due Date',
                value: dueDate == null ? '-' : _isoDate(dueDate),
              ),
              const SizedBox(height: 6),
              _detailLine(
                label: 'Total Hours',
                value: totalHours.toStringAsFixed(2),
              ),
              const SizedBox(height: 6),
              _detailLine(label: 'Total Amount', value: _money(totalAmount)),
              const SizedBox(height: 6),
              _detailLine(
                label: 'Received',
                value: _money(totalReceived),
                color: statusColor,
              ),
              const SizedBox(height: 6),
              _detailLine(
                label: 'Pending',
                value: _money(
                  (totalAmount - totalReceived).clamp(0, double.infinity),
                ),
                color: totalAmount > totalReceived
                    ? _InvoiceListColors.warningStripe
                    : _InvoiceListColors.success,
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _InvoiceListColors.textGray,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushNamed(
                          AppRoutes.invoiceView,
                          arguments: <String, dynamic>{
                            'invoiceId': _asString(invoice['_id']),
                            'invoice': invoice,
                          },
                        );
                      },
                      style: _outlinedButtonStyle(),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: !_isSuperUser || _deletingId == id
                          ? null
                          : () => _deleteInvoice(invoice),
                      style: _outlinedButtonStyle(
                        color: _InvoiceListColors.danger,
                        borderColor: _InvoiceListColors.danger.withValues(
                          alpha: 0.34,
                        ),
                      ),
                      icon: _deletingId == id
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoicesSection(List<Map<String, dynamic>> filteredInvoices) {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.receipt_rounded,
            title: 'Invoices',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _InvoiceListColors.surfaceMuted,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _InvoiceListColors.lightGray),
              ),
              child: Text(
                filteredInvoices.length.toString(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _InvoiceListColors.darkGray,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filteredInvoices.isEmpty)
            _emptyBlock(
              icon: Icons.receipt_long_outlined,
              title: 'No invoices found',
              subtitle:
                  'Try changing filters or search with a different keyword.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final bool twoColumns = constraints.maxWidth >= 980;
                const double spacing = 12;
                final double cardWidth = twoColumns
                    ? (constraints.maxWidth - spacing) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: filteredInvoices
                      .map((invoice) => _buildInvoiceCard(invoice, cardWidth))
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> filteredInvoices = _filteredInvoices;
    final double totalInvoiced = _invoices.fold<double>(
      0,
      (sum, inv) => sum + _asDouble(inv['totalAmount']),
    );
    final double totalReceived = _invoices.fold<double>(
      0,
      (sum, inv) => sum + _asDouble(inv['totalReceived']),
    );
    final double totalPending = totalInvoiced - totalReceived;

    return Scaffold(
      backgroundColor: _InvoiceListColors.pageBackground,
      body: Container(
        decoration: _backgroundGradient(),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _fetchInvoices,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        _buildHeader(
                          totalInvoiced,
                          totalReceived,
                          totalPending,
                        ),
                        const SizedBox(height: 16),
                        _buildFilterSection(
                          filteredInvoices.length,
                          _invoices.length,
                        ),
                        const SizedBox(height: 16),
                        _buildInvoicesSection(filteredInvoices),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: -1),
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({
    required this.child,
    this.hoverable = true,
    this.elevation = 1,
    this.hoverElevation = 4,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.borderColor = Colors.transparent,
    this.leftAccentColor,
  });

  final Widget child;
  final bool hoverable;
  final double elevation;
  final double hoverElevation;
  final BorderRadius borderRadius;
  final Color borderColor;
  final Color? leftAccentColor;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovering = false;

  bool get _canHover {
    if (!widget.hoverable) {
      return false;
    }
    if (kIsWeb) {
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double elevation = _canHover && _hovering
        ? widget.hoverElevation
        : widget.elevation;
    final double offsetY = _canHover && _hovering ? -1.5 : 0;

    return MouseRegion(
      onEnter: _canHover ? (_) => setState(() => _hovering = true) : null,
      onExit: _canHover ? (_) => setState(() => _hovering = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, offsetY, 0),
        child: Material(
          color: _InvoiceListColors.pureWhite,
          elevation: elevation,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          borderRadius: widget.borderRadius,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(color: widget.borderColor),
              ),
              child: Stack(
                children: [
                  if (widget.leftAccentColor != null)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 4, color: widget.leftAccentColor),
                    ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: widget.leftAccentColor != null ? 4 : 0,
                    ),
                    child: widget.child,
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
