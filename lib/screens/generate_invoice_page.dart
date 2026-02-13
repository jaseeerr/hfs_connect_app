import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';

class _InvoiceColors {
  const _InvoiceColors._();

  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pageBackground = Color(0xFFF3F4F6);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color warningStripe = Color(0xFFD97706);
}

class GenerateInvoicePage extends StatefulWidget {
  const GenerateInvoicePage({super.key, this.clientData});

  final dynamic clientData;

  @override
  State<GenerateInvoicePage> createState() => _GenerateInvoicePageState();
}

class _GenerateInvoicePageState extends State<GenerateInvoicePage> {
  bool _includeDueDate = false;
  bool _includeTax = false;
  bool _saving = false;
  bool _loadingClientAddress = false;
  String _currentView = 'invoice';

  Map<String, dynamic> _invoice = <String, dynamic>{};

  Map<String, dynamic> get _clientData => widget.clientData is Map
      ? Map<String, dynamic>.from(widget.clientData as Map)
      : <String, dynamic>{};

  String _asString(dynamic value) => value == null ? '' : value.toString();

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_asString(value)) ?? 0;
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

  String _isoDate(DateTime date) {
    final String y = date.year.toString().padLeft(4, '0');
    final String m = date.month.toString().padLeft(2, '0');
    final String d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatHours(double decimalHours) {
    if (decimalHours.isNaN) {
      return '0 hrs';
    }
    final int hours = decimalHours.floor();
    final int minutes = ((decimalHours - hours) * 60).round();
    if (minutes == 0) {
      return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    }
    return '$hours ${hours == 1 ? 'hour' : 'hours'} '
        '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }

  String _errorMessage(Object err) {
    if (err is DioException) {
      final dynamic data = err.response?.data;
      if (data is Map) {
        final String e = _asString(data['error']).trim();
        final String m = _asString(data['message']).trim();
        if (e.isNotEmpty) {
          return e;
        }
        if (m.isNotEmpty) {
          return m;
        }
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
    _initializeInvoice();
    _fetchClientAddress();
  }

  void _initializeInvoice() {
    final DateTime now = DateTime.now();
    final DateTime due = now.add(const Duration(days: 30));
    final double qty = _asDouble(_clientData['totalHours']);
    final String resolvedClientName =
        _asString(_clientData['invoiceName']).trim().isNotEmpty
        ? _asString(_clientData['invoiceName']).trim()
        : _asString(_clientData['clientName']).trim();
    final int randomNo = math.Random().nextInt(10000);
    final String description = _buildDescription(resolvedClientName);

    _invoice = <String, dynamic>{
      'invoiceNo': 'INV-${now.year}/${randomNo.toString().padLeft(4, '0')}',
      'invoiceDate': _isoDate(now),
      'dueDate': _isoDate(due),
      'vatRate': 5.0,
      'clientName': resolvedClientName,
      'clientAddress': '',
      'clientTRN': '',
      'companyName': 'Honor First Security LLC',
      'companyAddress':
          'Jumeirah Lake Towers, Dubai\n'
          'Email: info@honorfirstsecurity.com\n'
          'Website: www.honorfirstsecurity.com',
      'companyTRN': '',
      'location': resolvedClientName,
      'bankName': 'Abu Dhabi Commercial Bank',
      'bankBranch': '',
      'accountNo': '14355603820001',
      'iban': 'AE790030014355603820001',
      'swiftCode': 'ADCBAEAA',
      'invoiceItems': <Map<String, dynamic>>[
        <String, dynamic>{
          'description': description,
          'qty': qty,
          'unitPrice': 75.0,
        },
      ],
    };
  }

  String _buildDescription(String locationName) {
    final String periodFrom = _asString(_clientData['periodFrom']);
    final String periodTo = _asString(_clientData['periodTo']);
    return 'SECURITY GUARDS SERVICE\n'
        'PERIOD: $periodFrom to $periodTo\n'
        'LOCATION: ${locationName.toUpperCase()}';
  }

  Future<void> _fetchClientAddress() async {
    final String clientId = _asString(_clientData['clientId']).trim();
    if (clientId.isEmpty || AuthStorage.isTester) {
      return;
    }

    setState(() => _loadingClientAddress = true);
    try {
      final Response<dynamic> res = await ApiClient.create(
        opt: 0,
        token: AuthStorage.token,
      ).get('/getClientAddress/$clientId');

      final dynamic body = res.data;
      if (body is! Map) {
        return;
      }
      final String formattedAddress = _asString(body['address'])
          .split(',')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join(',\n');
      final String invoiceName = _asString(body['invoiceName']).trim();
      final String fallbackName = _asString(body['name']).trim();
      final String backendName = invoiceName.isNotEmpty
          ? invoiceName
          : fallbackName;

      if (!mounted) {
        return;
      }
      setState(() {
        _invoice['clientAddress'] = formattedAddress.isNotEmpty
            ? formattedAddress
            : _invoice['clientAddress'];
        if (backendName.isNotEmpty) {
          _invoice['clientName'] = backendName;
          _invoice['location'] = backendName;
          final List<Map<String, dynamic>> items = _asMapList(
            _invoice['invoiceItems'],
          );
          if (items.isNotEmpty) {
            items[0] = <String, dynamic>{
              ...items[0],
              'description': _buildDescription(backendName),
            };
            _invoice['invoiceItems'] = items;
          }
        }
      });
    } catch (_) {
      // Keep local fallback values.
    } finally {
      if (mounted) {
        setState(() => _loadingClientAddress = false);
      }
    }
  }

  List<Map<String, dynamic>> _invoiceItems() =>
      _asMapList(_invoice['invoiceItems']);

  double get _subtotal {
    return _invoiceItems().fold<double>(
      0,
      (sum, item) =>
          sum + (_asDouble(item['qty']) * _asDouble(item['unitPrice'])),
    );
  }

  double get _vatAmount {
    final double rate = _asDouble(_invoice['vatRate']);
    return _includeTax ? (_subtotal * rate / 100) : 0;
  }

  double get _total => _subtotal + _vatAmount;

  void _setInvoiceField(String key, dynamic value) {
    setState(() => _invoice[key] = value);
  }

  void _updateItem(int index, String key, dynamic value) {
    final List<Map<String, dynamic>> items = _invoiceItems();
    if (index < 0 || index >= items.length) {
      return;
    }
    items[index] = <String, dynamic>{...items[index], key: value};
    setState(() => _invoice['invoiceItems'] = items);
  }

  void _addItem() {
    final List<Map<String, dynamic>> items = _invoiceItems();
    items.add(<String, dynamic>{
      'description': '',
      'qty': 1.0,
      'unitPrice': 0.0,
    });
    setState(() => _invoice['invoiceItems'] = items);
  }

  void _removeItem(int index) {
    final List<Map<String, dynamic>> items = _invoiceItems();
    if (items.length <= 1) {
      return;
    }
    items.removeAt(index);
    setState(() => _invoice['invoiceItems'] = items);
  }

  List<Map<String, dynamic>> _aggregateTimesheetByDate() {
    final List<Map<String, dynamic>> guards = _asMapList(_clientData['guards']);
    final Map<String, Map<String, dynamic>> dateMap =
        <String, Map<String, dynamic>>{};

    for (final Map<String, dynamic> guard in guards) {
      final String guardName = _asString(guard['name']);
      for (final Map<String, dynamic> shift in _asMapList(guard['shifts'])) {
        final String date = _asString(shift['date']).trim();
        if (date.isEmpty) {
          continue;
        }
        dateMap.putIfAbsent(date, () {
          return <String, dynamic>{
            'date': date,
            'guardSet': <String>{},
            'totalHours': 0.0,
          };
        });
        final Map<String, dynamic> bucket = dateMap[date]!;
        (bucket['guardSet'] as Set<String>).add(guardName);
        bucket['totalHours'] =
            _asDouble(bucket['totalHours']) + _asDouble(shift['hours']);
      }
    }

    final List<Map<String, dynamic>> result = dateMap.values.map((item) {
      return <String, dynamic>{
        'date': _asString(item['date']),
        'guardCount': (item['guardSet'] as Set<String>).length,
        'totalHours': _asDouble(item['totalHours']),
      };
    }).toList();

    result.sort((a, b) {
      final DateTime? da = DateTime.tryParse(_asString(a['date']));
      final DateTime? db = DateTime.tryParse(_asString(b['date']));
      if (da == null || db == null) {
        return _asString(a['date']).compareTo(_asString(b['date']));
      }
      return da.compareTo(db);
    });
    return result;
  }

  Future<void> _pickDateField(String key) async {
    final DateTime current =
        DateTime.tryParse(_asString(_invoice[key])) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) {
      _setInvoiceField(key, _isoDate(picked));
    }
  }

  Future<void> _saveInvoice() async {
    if (_saving) {
      return;
    }
    final String clientId = _asString(_clientData['clientId']).trim();
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing client data for invoice'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final List<Map<String, dynamic>> items = _invoiceItems();
      final List<Map<String, dynamic>> guards = _asMapList(
        _clientData['guards'],
      );

      final List<Map<String, dynamic>> timesheet = guards.map((guard) {
        return <String, dynamic>{
          'guardId': _asString(guard['guardId']).isEmpty
              ? _asString(guard['_id'])
              : _asString(guard['guardId']),
          'name': _asString(guard['name']),
          'shifts': _asMapList(guard['shifts']).map((shift) {
            return <String, dynamic>{
              'date': _asString(shift['date']),
              'hours': _asDouble(shift['hours']),
              'checkInAt': _asString(shift['checkInAt']).isEmpty
                  ? null
                  : _asString(shift['checkInAt']),
              'checkOutAt': _asString(shift['checkOutAt']).isEmpty
                  ? null
                  : _asString(shift['checkOutAt']),
            };
          }).toList(),
        };
      }).toList();

      final Response<dynamic> res =
          await ApiClient.create(opt: 0, token: AuthStorage.token).post(
            '/addInvoice',
            data: <String, dynamic>{
              'clientId': clientId,
              'invoiceNo': _asString(_invoice['invoiceNo']),
              'invoiceDate': _asString(_invoice['invoiceDate']),
              'dueDate': _includeDueDate
                  ? _asString(_invoice['dueDate'])
                  : null,
              'periodFrom': _asString(_clientData['periodFrom']),
              'periodTo': _asString(_clientData['periodTo']),
              'invoiceItems': items.map((item) {
                final double qty = _asDouble(item['qty']);
                final double unitPrice = _asDouble(item['unitPrice']);
                return <String, dynamic>{
                  'description': _asString(item['description']),
                  'qty': qty,
                  'unitPrice': unitPrice,
                  'amount': qty * unitPrice,
                };
              }).toList(),
              'totalHours': items.fold<double>(
                0,
                (sum, item) => sum + _asDouble(item['qty']),
              ),
              'ratePerHour': items.length == 1
                  ? _asDouble(items.first['unitPrice'])
                  : 0,
              'vatEnabled': _includeTax,
              'vatRate': _asDouble(_invoice['vatRate']),
              'subtotal': _subtotal,
              'vatAmount': _vatAmount,
              'totalAmount': _total,
              'timesheet': timesheet,
            },
          );

      final bool ok = (res.data is Map && res.data['success'] == true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Invoice saved successfully' : 'Error saving invoice',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (ok) {
        Navigator.of(context).pop();
      }
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
        setState(() => _saving = false);
      }
    }
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _InvoiceColors.pureWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _InvoiceColors.lightGray),
      ),
      child: child,
    );
  }

  Widget _labeledField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: _InvoiceColors.textGray,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          onChanged: onChanged,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _InvoiceColors.pureWhite,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _InvoiceColors.lightGray),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _InvoiceColors.lightGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _InvoiceColors.primaryBlue),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_clientData.isEmpty) {
      return Scaffold(
        backgroundColor: _InvoiceColors.pageBackground,
        body: Center(
          child: _panel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No client data found.',
                  style: TextStyle(color: _InvoiceColors.textGray),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<Map<String, dynamic>> dailyTimesheet =
        _aggregateTimesheetByDate();
    final String periodFrom = _asString(_clientData['periodFrom']);
    final String periodTo = _asString(_clientData['periodTo']);

    return Scaffold(
      backgroundColor: _InvoiceColors.pageBackground,
      appBar: AppBar(
        title: const Text('Generate Invoice'),
        backgroundColor: _InvoiceColors.pureWhite,
        surfaceTintColor: _InvoiceColors.pureWhite,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sections',
                        style: TextStyle(
                          fontSize: 12,
                          color: _InvoiceColors.textGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Invoice'),
                            selected: _currentView == 'invoice',
                            onSelected: (_) =>
                                setState(() => _currentView = 'invoice'),
                          ),
                          ChoiceChip(
                            label: const Text('Timesheet'),
                            selected: _currentView == 'timesheet',
                            onSelected: (_) =>
                                setState(() => _currentView = 'timesheet'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Invoice Options',
                        style: TextStyle(
                          fontSize: 12,
                          color: _InvoiceColors.textGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('Include Due Date'),
                            selected: _includeDueDate,
                            onSelected: (value) =>
                                setState(() => _includeDueDate = value),
                          ),
                          FilterChip(
                            label: const Text('Include Tax'),
                            selected: _includeTax,
                            onSelected: (value) =>
                                setState(() => _includeTax = value),
                          ),
                          if (_loadingClientAddress)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_currentView == 'invoice') ...[
                  _panel(
                    child: Column(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final bool stacked = constraints.maxWidth < 760;
                            final Widget left = Column(
                              children: [
                                _labeledField(
                                  label: 'Client Name',
                                  value: _asString(_invoice['clientName']),
                                  onChanged: (v) =>
                                      _setInvoiceField('clientName', v),
                                ),
                                const SizedBox(height: 10),
                                _labeledField(
                                  label: 'Client Address',
                                  value: _asString(_invoice['clientAddress']),
                                  onChanged: (v) =>
                                      _setInvoiceField('clientAddress', v),
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 10),
                                _labeledField(
                                  label: 'Client TRN',
                                  value: _asString(_invoice['clientTRN']),
                                  onChanged: (v) =>
                                      _setInvoiceField('clientTRN', v),
                                ),
                              ],
                            );
                            final Widget right = Column(
                              children: [
                                _labeledField(
                                  label: 'Company Name',
                                  value: _asString(_invoice['companyName']),
                                  onChanged: (v) =>
                                      _setInvoiceField('companyName', v),
                                ),
                                const SizedBox(height: 10),
                                _labeledField(
                                  label: 'Company Address',
                                  value: _asString(_invoice['companyAddress']),
                                  onChanged: (v) =>
                                      _setInvoiceField('companyAddress', v),
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 10),
                                _labeledField(
                                  label: 'Company TRN',
                                  value: _asString(_invoice['companyTRN']),
                                  onChanged: (v) =>
                                      _setInvoiceField('companyTRN', v),
                                ),
                              ],
                            );
                            if (stacked) {
                              return Column(
                                children: [
                                  left,
                                  const SizedBox(height: 12),
                                  right,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: left),
                                const SizedBox(width: 12),
                                Expanded(child: right),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Invoice Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _InvoiceColors.textGray,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  _asString(_invoice['invoiceDate']),
                                ),
                                trailing: IconButton(
                                  onPressed: () =>
                                      _pickDateField('invoiceDate'),
                                  icon: const Icon(
                                    Icons.edit_calendar_outlined,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: _labeledField(
                                label: 'Invoice Number',
                                value: _asString(_invoice['invoiceNo']),
                                onChanged: (v) =>
                                    _setInvoiceField('invoiceNo', v),
                              ),
                            ),
                          ],
                        ),
                        if (_includeDueDate) ...[
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Due Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: _InvoiceColors.textGray,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(_asString(_invoice['dueDate'])),
                            trailing: IconButton(
                              onPressed: () => _pickDateField('dueDate'),
                              icon: const Icon(Icons.edit_calendar_outlined),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Invoice Items',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _InvoiceColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._invoiceItems().asMap().entries.map((entry) {
                          final int index = entry.key;
                          final Map<String, dynamic> item = entry.value;
                          final double amount =
                              _asDouble(item['qty']) *
                              _asDouble(item['unitPrice']);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _InvoiceColors.pageBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _InvoiceColors.lightGray,
                              ),
                            ),
                            child: Column(
                              children: [
                                _labeledField(
                                  label: 'Description',
                                  value: _asString(item['description']),
                                  onChanged: (v) =>
                                      _updateItem(index, 'description', v),
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _labeledField(
                                        label: 'Quantity',
                                        value: _asDouble(
                                          item['qty'],
                                        ).toStringAsFixed(2),
                                        onChanged: (v) => _updateItem(
                                          index,
                                          'qty',
                                          double.tryParse(v) ?? 0,
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _labeledField(
                                        label: 'Unit Price',
                                        value: _asDouble(
                                          item['unitPrice'],
                                        ).toStringAsFixed(2),
                                        onChanged: (v) => _updateItem(
                                          index,
                                          'unitPrice',
                                          double.tryParse(v) ?? 0,
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      'Amount: AED ${amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _InvoiceColors.darkGray,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => _removeItem(index),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _addItem,
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Item'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _InvoiceColors.mediumGray,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Text('Subtotal'),
                                  const Spacer(),
                                  Text('AED ${_subtotal.toStringAsFixed(2)}'),
                                ],
                              ),
                              if (_includeTax) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Text(
                                      'VAT ${_asDouble(_invoice['vatRate']).toStringAsFixed(0)}%',
                                    ),
                                    const Spacer(),
                                    Text(
                                      'AED ${_vatAmount.toStringAsFixed(2)}',
                                    ),
                                  ],
                                ),
                              ],
                              const Divider(height: 18),
                              Row(
                                children: [
                                  const Text(
                                    'TOTAL AED',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _total.toStringAsFixed(2),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bank Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _InvoiceColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _labeledField(
                          label: 'Bank Name',
                          value: _asString(_invoice['bankName']),
                          onChanged: (v) => _setInvoiceField('bankName', v),
                        ),
                        const SizedBox(height: 10),
                        _labeledField(
                          label: 'Branch & Address',
                          value: _asString(_invoice['bankBranch']),
                          onChanged: (v) => _setInvoiceField('bankBranch', v),
                        ),
                        const SizedBox(height: 10),
                        _labeledField(
                          label: 'A/c No',
                          value: _asString(_invoice['accountNo']),
                          onChanged: (v) => _setInvoiceField('accountNo', v),
                        ),
                        const SizedBox(height: 10),
                        _labeledField(
                          label: 'IBAN',
                          value: _asString(_invoice['iban']),
                          onChanged: (v) => _setInvoiceField('iban', v),
                        ),
                        const SizedBox(height: 10),
                        _labeledField(
                          label: 'Swift Code',
                          value: _asString(_invoice['swiftCode']),
                          onChanged: (v) => _setInvoiceField('swiftCode', v),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labeledField(
                          label: 'Location',
                          value: _asString(_invoice['location']),
                          onChanged: (v) => _setInvoiceField('location', v),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Service: Security Guards',
                          style: TextStyle(
                            fontSize: 13,
                            color: _InvoiceColors.textGray,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Period: $periodFrom to $periodTo',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _InvoiceColors.textGray,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Daily Timesheet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _InvoiceColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (dailyTimesheet.isEmpty)
                          const Text(
                            'No timesheet entries found.',
                            style: TextStyle(color: _InvoiceColors.textGray),
                          )
                        else
                          ...dailyTimesheet.map((day) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _InvoiceColors.lightGray,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _asString(day['date']),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _InvoiceColors.darkGray,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${day['guardCount']} guards',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _InvoiceColors.textGray,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatHours(_asDouble(day['totalHours'])),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _InvoiceColors.warningStripe,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        const Divider(height: 18),
                        Text(
                          'TOTAL WORKING HOURS: '
                          '${_formatHours(_asDouble(_clientData['totalHours']))}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _InvoiceColors.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveInvoice,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save Invoice'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
