import 'package:dio/dio.dart';
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
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color warning = Color(0xFFB45309);
}

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
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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
            title: const Text('Delete Invoice'),
            content: Text(
              'Are you sure you want to delete invoice ${_asString(invoice['invoiceNo'])}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
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
      appBar: AppBar(
        title: const Text('Invoice Management'),
        backgroundColor: _InvoiceListColors.pureWhite,
        surfaceTintColor: _InvoiceListColors.pureWhite,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: RefreshIndicator(
              onRefresh: _fetchInvoices,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _InvoiceListColors.pureWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _InvoiceListColors.lightGray),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Invoices',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _InvoiceListColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Manage and track all invoices in one place.',
                          style: TextStyle(
                            fontSize: 13,
                            color: _InvoiceListColors.textGray,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _tinyStat(
                              'Total',
                              _invoices.length.toString(),
                              _InvoiceListColors.primaryBlue,
                            ),
                            _tinyStat(
                              'Invoiced',
                              'AED ${totalInvoiced.toStringAsFixed(2)}',
                              _InvoiceListColors.primaryBlue,
                            ),
                            _tinyStat(
                              'Received',
                              'AED ${totalReceived.toStringAsFixed(2)}',
                              _InvoiceListColors.primaryBlue,
                            ),
                            _tinyStat(
                              'Pending',
                              'AED ${totalPending.toStringAsFixed(2)}',
                              _InvoiceListColors.warning,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _InvoiceListColors.pureWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _InvoiceListColors.lightGray),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchTerm = value),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search invoice number or client',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _InvoiceListColors.lightGray,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _sortOrder,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Sort',
                                  border: OutlineInputBorder(),
                                  isDense: true,
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedClient,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Client',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: <DropdownMenuItem<String>>[
                                  const DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Clients'),
                                  ),
                                  ..._uniqueClients.map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
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
                        if (_searchTerm.isNotEmpty ||
                            _selectedClient != 'all') ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Showing ${filteredInvoices.length} of ${_invoices.length} invoices',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _InvoiceListColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (filteredInvoices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _InvoiceListColors.pureWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _InvoiceListColors.lightGray),
                      ),
                      child: const Text(
                        'No invoices found.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _InvoiceListColors.textGray,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    ...filteredInvoices.map((invoice) {
                      final String id = _asString(invoice['_id']);
                      final double totalAmount = _asDouble(
                        invoice['totalAmount'],
                      );
                      final double totalReceived = _asDouble(
                        invoice['totalReceived'],
                      );
                      final Color receivedColor = totalReceived >= totalAmount
                          ? Colors.green
                          : totalReceived > 0
                          ? _InvoiceListColors.warning
                          : Colors.red;

                      final DateTime? invoiceDate = DateTime.tryParse(
                        _asString(invoice['invoiceDate']),
                      );
                      final DateTime? dueDate = DateTime.tryParse(
                        _asString(invoice['dueDate']),
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _InvoiceListColors.pureWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _InvoiceListColors.lightGray,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _asString(invoice['invoiceNo']),
                                    style: const TextStyle(
                                      color: _InvoiceListColors.primaryBlue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Text(
                                  'AED ${totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: _InvoiceListColors.darkGray,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _asString(invoice['clientName']).isEmpty
                                  ? '-'
                                  : _asString(invoice['clientName']),
                              style: const TextStyle(
                                color: _InvoiceListColors.darkGray,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                Text(
                                  'Invoice: ${invoiceDate == null ? '-' : _isoDate(invoiceDate)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _InvoiceListColors.textGray,
                                  ),
                                ),
                                Text(
                                  'Due: ${dueDate == null ? '-' : _isoDate(dueDate)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _InvoiceListColors.textGray,
                                  ),
                                ),
                                Text(
                                  'Hours: ${_asDouble(invoice['totalHours']).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _InvoiceListColors.textGray,
                                  ),
                                ),
                                Text(
                                  'Received: ${totalReceived.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: receivedColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _asString(invoice['description']).isEmpty
                                  ? '-'
                                  : _asString(invoice['description']),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _InvoiceListColors.textGray,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).pushNamed(
                                        AppRoutes.invoiceView,
                                        arguments: <String, dynamic>{
                                          'invoiceId': _asString(
                                            invoice['_id'],
                                          ),
                                          'invoice': invoice,
                                        },
                                      );
                                    },
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('View'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed:
                                        !_isSuperUser || _deletingId == id
                                        ? null
                                        : () => _deleteInvoice(invoice),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    icon: _deletingId == id
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.delete_outline),
                                    label: const Text('Delete'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: -1),
    );
  }

  Widget _tinyStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _InvoiceListColors.lightGray),
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
}
