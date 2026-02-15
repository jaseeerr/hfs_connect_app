import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../widget/app_bottom_nav_bar.dart';

class _InvoiceViewColors {
  const _InvoiceViewColors._();

  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF8FAFC);
  static const Color pageBackground = Color(0xFFF3F4F6);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color surfaceMuted = Color(0xFFF8FAFC);
  static const Color warning = Color(0xFFB45309);
  static const Color warningStripe = Color(0xFFD97706);
}

class InvoiceViewPage extends StatefulWidget {
  const InvoiceViewPage({
    super.key,
    required this.invoiceId,
    this.initialInvoice,
  });

  final String invoiceId;
  final dynamic initialInvoice;

  @override
  State<InvoiceViewPage> createState() => _InvoiceViewPageState();
}

class _InvoiceViewPageState extends State<InvoiceViewPage> {
  bool _loading = true;
  bool _saving = false;
  bool _exportingPdf = false;

  bool _includeDueDate = false;
  bool _includeTax = false;
  bool _includeStamp = false;
  bool _includeSignature = false;

  String _currentView = 'invoice';

  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _receipts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _processedTimesheet = <Map<String, dynamic>>[];

  final Map<String, dynamic> _receiptForm = <String, dynamic>{
    'amountReceived': '',
    'paymentMode': 'cash',
    'paymentDate': '',
    'note': '',
    'description': '',
  };

  String _asString(dynamic value) => value == null ? '' : value.toString();

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_asString(value)) ?? 0;
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

  String _dateKey(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  DateTime? _tryDate(dynamic value) {
    final String raw = _asString(value).trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  String _formatHours(double decimalHours) {
    final int hours = decimalHours.floor();
    final int minutes = ((decimalHours - hours) * 60).round();
    if (minutes == 0) {
      return '$hours hours';
    }
    return '$hours hours $minutes minutes';
  }

  Future<pw.MemoryImage> _assetImage(String path) async {
    final ByteData data = await rootBundle.load(path);
    return pw.MemoryImage(data.buffer.asUint8List());
  }

  List<String> _clientAddressLines(String rawAddress) {
    return rawAddress
        .split(',')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _receiptForm['paymentDate'] = _dateKey(DateTime.now());
    if (widget.initialInvoice is Map) {
      _invoice = Map<String, dynamic>.from(widget.initialInvoice as Map);
    }
    _fetchInvoice();
  }

  double get _subtotal {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return 0;
    }
    return _asMapList(invoice['invoiceItems']).fold<double>(
      0,
      (sum, item) =>
          sum + _asDouble(item['qty']) * _asDouble(item['unitPrice']),
    );
  }

  double get _vatAmount {
    final Map<String, dynamic>? invoice = _invoice;
    if (!_includeTax || invoice == null) {
      return 0;
    }
    final double vatRate = _asDouble(invoice['vatRate']) == 0
        ? 5
        : _asDouble(invoice['vatRate']);
    return _subtotal * vatRate / 100;
  }

  double get _total => _subtotal + _vatAmount;

  double get _totalReceived {
    return _receipts.fold<double>(
      0,
      (sum, receipt) => sum + _asDouble(receipt['amountReceived']),
    );
  }

  double get _pending => _total - _totalReceived;

  String get _clientDisplayName {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return '';
    }
    final Map<String, dynamic> client = _asMap(invoice['clientId']);
    final String invoiceName = _asString(client['invoiceName']).trim();
    final String name = _asString(client['name']).trim();
    if (invoiceName.isNotEmpty) {
      return invoiceName;
    }
    if (name.isNotEmpty) {
      return name;
    }
    return _asString(invoice['clientName']).trim();
  }

  List<Map<String, dynamic>> _aggregateTimesheetByDate(
    List<Map<String, dynamic>> guards,
  ) {
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
            'guardCount': 0,
            'totalHours': 0.0,
            'guardNames': <String>{},
          };
        });
        final Map<String, dynamic> bucket = dateMap[date]!;
        bucket['totalHours'] =
            _asDouble(bucket['totalHours']) + _asDouble(shift['hours']);
        final Set<String> names = bucket['guardNames'] as Set<String>;
        if (!names.contains(guardName)) {
          names.add(guardName);
          bucket['guardCount'] = _asDouble(bucket['guardCount']).toInt() + 1;
        }
      }
    }

    final List<Map<String, dynamic>> rows =
        dateMap.values
            .map(
              (item) => <String, dynamic>{
                'date': _asString(item['date']),
                'guardCount': _asDouble(item['guardCount']).toInt(),
                'totalHours': _asDouble(item['totalHours']),
              },
            )
            .toList()
          ..sort((a, b) {
            final DateTime? da = DateTime.tryParse(_asString(a['date']));
            final DateTime? db = DateTime.tryParse(_asString(b['date']));
            if (da == null || db == null) {
              return _asString(a['date']).compareTo(_asString(b['date']));
            }
            return da.compareTo(db);
          });
    return rows;
  }

  Future<void> _fetchInvoice() async {
    final String invoiceId = widget.invoiceId.trim();
    if (invoiceId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
      setState(() => _loading = true);
      final List<Response<dynamic>> responses = await Future.wait([
        ApiClient.create(
          opt: 0,
          token: AuthStorage.token,
        ).get('/invoice/$invoiceId'),
        ApiClient.create(
          opt: 0,
          token: AuthStorage.token,
        ).get('/receipts/$invoiceId'),
      ]);

      final Map<String, dynamic> invoiceData = _asMap(
        _asMap(responses[0].data)['data'],
      );
      final List<Map<String, dynamic>> receiptsData = _asMapList(
        _asMap(responses[1].data)['data'],
      );

      final List<Map<String, dynamic>> timesheetRows =
          _aggregateTimesheetByDate(_asMapList(invoiceData['timesheet']));

      if (!mounted) {
        return;
      }
      setState(() {
        _invoice = invoiceData;
        _receipts = receiptsData;
        _processedTimesheet = timesheetRows;
        if (invoiceData['vatEnabled'] != null) {
          _includeTax = invoiceData['vatEnabled'] == true;
        }
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

  Future<void> _pickInvoiceDate(String key) async {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return;
    }
    final DateTime initial = _tryDate(invoice[key]) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      invoice[key] = _dateKey(picked);
    });
  }

  void _setInvoiceField(String key, dynamic value) {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return;
    }
    setState(() {
      invoice[key] = value;
    });
  }

  void _updateInvoiceItem(int index, String key, dynamic value) {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return;
    }
    final List<Map<String, dynamic>> items = _asMapList(
      invoice['invoiceItems'],
    );
    if (index < 0 || index >= items.length) {
      return;
    }
    items[index] = <String, dynamic>{...items[index], key: value};
    setState(() {
      invoice['invoiceItems'] = items;
    });
  }

  void _addItem() {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return;
    }
    final List<Map<String, dynamic>> items = _asMapList(
      invoice['invoiceItems'],
    );
    items.add(<String, dynamic>{
      'description': '',
      'qty': 1.0,
      'unitPrice': 0.0,
    });
    setState(() {
      invoice['invoiceItems'] = items;
    });
  }

  Future<void> _saveInvoice() async {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null || _saving) {
      return;
    }
    final String id = _asString(invoice['_id']).trim();
    if (id.isEmpty) {
      return;
    }

    try {
      setState(() => _saving = true);
      final List<Map<String, dynamic>> items = _asMapList(
        invoice['invoiceItems'],
      );
      final Response<dynamic> res =
          await ApiClient.create(opt: 0, token: AuthStorage.token).put(
            '/editInvoice/$id',
            data: <String, dynamic>{
              'invoiceNo': _asString(invoice['invoiceNo']),
              'invoiceDate': _asString(invoice['invoiceDate']),
              'dueDate': _asString(invoice['dueDate']),
              'periodFrom': _asString(invoice['periodFrom']),
              'periodTo': _asString(invoice['periodTo']),
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
              'vatEnabled': _includeTax,
              'vatRate': _asDouble(invoice['vatRate']) == 0
                  ? 5
                  : _asDouble(invoice['vatRate']),
            },
          );

      final bool success = _asMap(res.data)['success'] == true;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Invoice updated successfully' : 'Error updating invoice',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (success) {
        await _fetchInvoice();
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

  Future<bool> _saveReceipt() async {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null || _saving) {
      return false;
    }
    final String amountRaw = _asString(_receiptForm['amountReceived']).trim();
    final double amount = double.tryParse(amountRaw) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    try {
      setState(() => _saving = true);
      final Map<String, dynamic> client = _asMap(invoice['clientId']);
      final Response<dynamic> res =
          await ApiClient.create(opt: 0, token: AuthStorage.token).post(
            '/addReceiptFromInvoice',
            data: <String, dynamic>{
              'invoiceId': _asString(invoice['_id']),
              'invoiceNo': _asString(invoice['invoiceNo']),
              'clientId': _asString(client['_id']),
              'clientName': _clientDisplayName.isEmpty
                  ? 'Unknown Client'
                  : _clientDisplayName,
              'amountReceived': amount,
              'paymentMode': _asString(_receiptForm['paymentMode']),
              'paymentDate': _asString(_receiptForm['paymentDate']),
              'note': _asString(_receiptForm['note']),
              'description': _asString(_receiptForm['description']).isEmpty
                  ? 'Payment received for ${_asString(invoice['invoiceNo'])}'
                  : _asString(_receiptForm['description']),
            },
          );

      final bool success = _asMap(res.data)['success'] == true;
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Receipt added successfully' : 'Error adding receipt',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (success) {
        setState(() {
          _receiptForm['amountReceived'] = '';
          _receiptForm['paymentMode'] = 'cash';
          _receiptForm['paymentDate'] = _dateKey(DateTime.now());
          _receiptForm['note'] = '';
          _receiptForm['description'] = '';
        });
        await _fetchInvoice();
        return true;
      }
      return false;
    } catch (err) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(err)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteReceipt(String receiptId) async {
    if (receiptId.trim().isEmpty) {
      return;
    }
    final bool shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Receipt'),
            content: const Text('Delete this receipt?'),
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
    try {
      await ApiClient.create(
        opt: 0,
        token: AuthStorage.token,
      ).delete('/deleteReceipt/$receiptId');
      await _fetchInvoice();
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
    }
  }

  Future<void> _exportPdf() async {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null || _exportingPdf) {
      return;
    }

    try {
      setState(() => _exportingPdf = true);
      final pw.Document doc = pw.Document();

      final pw.MemoryImage logoImage = await _assetImage('assets/LogoNoBg.png');
      pw.MemoryImage? stampImage;
      pw.MemoryImage? signatureImage;

      if (_includeStamp) {
        stampImage = await _assetImage('assets/stamp.jpeg');
      }
      if (_includeSignature) {
        signatureImage = await _assetImage('assets/altajiSignature.jpeg');
      }

      final Map<String, dynamic> client = _asMap(invoice['clientId']);
      final String clientName = _clientDisplayName;
      final List<String> clientLines = _clientAddressLines(
        _asString(client['address']),
      );
      final String clientTrn = _asString(client['trn']);

      const String companyName = 'Honor First Security LLC';
      const List<String> companyLines = <String>[
        'Jumeirah Lake Towers, Dubai',
        'Email: info@honorfirstsecurity.com',
        'Website: www.honorfirstsecurity.com',
      ];
      const String companyTrn = '';

      final List<Map<String, dynamic>> items = _asMapList(
        invoice['invoiceItems'],
      );
      final double subtotal = _subtotal;
      final double vatAmount = _vatAmount;
      final double total = _total;
      final double vatRate = _asDouble(invoice['vatRate']) == 0
          ? 5
          : _asDouble(invoice['vatRate']);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(40, 30, 40, 30),
          build: (pw.Context context) {
            return <pw.Widget>[
              pw.Center(child: pw.Image(logoImage, width: 100)),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          clientName,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        ...clientLines.map((line) => pw.Text(line)),
                        if (clientTrn.trim().isNotEmpty)
                          pw.Text(
                            'TRN: $clientTrn',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          companyName,
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        ...companyLines.map(
                          (line) =>
                              pw.Text(line, textAlign: pw.TextAlign.right),
                        ),
                        if (companyTrn.trim().isNotEmpty)
                          pw.Text(
                            'TRN: $companyTrn',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                children: [
                  pw.Text(
                    'Invoice Date',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(width: 18),
                  pw.Text(
                    'Invoice Number',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Text(_asString(invoice['invoiceDate'])),
                  pw.SizedBox(width: 32),
                  pw.Text(_asString(invoice['invoiceNo'])),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: _includeTax
                    ? const [
                        'Description',
                        'Quantity',
                        'Unit Price',
                        'Tax',
                        'Amount AED',
                      ]
                    : const [
                        'Description',
                        'Quantity',
                        'Unit Price',
                        'Amount AED',
                      ],
                data: items.map((item) {
                  final double qty = _asDouble(item['qty']);
                  final double price = _asDouble(item['unitPrice']);
                  final double amount = qty * price;
                  return _includeTax
                      ? [
                          _asString(item['description']),
                          qty.toStringAsFixed(2),
                          price.toStringAsFixed(2),
                          '${vatRate.toStringAsFixed(0)}%',
                          amount.toStringAsFixed(2),
                        ]
                      : [
                          _asString(item['description']),
                          qty.toStringAsFixed(2),
                          price.toStringAsFixed(2),
                          amount.toStringAsFixed(2),
                        ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.black),
                cellPadding: const pw.EdgeInsets.all(8),
                cellAlignments: {
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  if (_includeTax) 3: pw.Alignment.center,
                },
              ),
              pw.SizedBox(height: 14),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Subtotal  ${subtotal.toStringAsFixed(2)}'),
                    if (_includeTax)
                      pw.Text(
                        'TOTAL VAT ${vatRate.toStringAsFixed(0)}%  ${vatAmount.toStringAsFixed(2)}',
                      ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'TOTAL AED  ${total.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (_includeDueDate) ...[
                pw.SizedBox(height: 14),
                pw.Text('Due Date: ${_asString(invoice['dueDate'])}'),
              ],
              pw.SizedBox(height: 20),
              pw.Text(
                'BANK ACCOUNT DETAILS',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text('A/c Name: HONOR FIRST SECURITY LLC'),
              pw.Text('Bank Name: Abu Dhabi Commercial Bank'),
              pw.Text('Branch: '),
              pw.Text('A/c No: 14355603820001'),
              pw.Text('IBAN: AE790030014355603820001'),
              pw.Text('Swift Code: ADCBAEAA'),
              if (_includeStamp || _includeSignature) ...[
                pw.SizedBox(height: 16),
                pw.Row(
                  children: [
                    if (_includeStamp && stampImage != null)
                      pw.Image(stampImage, height: 90),
                    if (_includeStamp &&
                        stampImage != null &&
                        _includeSignature)
                      pw.SizedBox(width: 20),
                    if (_includeSignature && signatureImage != null)
                      pw.Image(signatureImage, height: 50),
                  ],
                ),
              ],
            ];
          },
        ),
      );

      if (_processedTimesheet.isNotEmpty) {
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(40, 30, 40, 30),
            build: (pw.Context context) {
              return <pw.Widget>[
                pw.Center(child: pw.Image(logoImage, width: 100)),
                pw.SizedBox(height: 18),
                pw.Text('Location: $clientName'),
                pw.Text('Service: Security Guards'),
                pw.Text(
                  'Period: ${_asString(invoice['periodFrom'])} to ${_asString(invoice['periodTo'])}',
                ),
                pw.SizedBox(height: 16),
                pw.TableHelper.fromTextArray(
                  headers: const ['Date', 'No. of Guards', 'Total working Hrs'],
                  data: _processedTimesheet.map((day) {
                    return [
                      _asString(day['date']),
                      _asDouble(day['guardCount']).toInt().toString(),
                      _formatHours(_asDouble(day['totalHours'])),
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  border: pw.TableBorder.all(
                    width: 0.5,
                    color: PdfColors.black,
                  ),
                  cellPadding: const pw.EdgeInsets.all(6),
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  'TIME SHEET SUMMARY',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'TOTAL WORKING HOURS: ${_formatHours(_asDouble(invoice['totalHours']))}',
                ),
              ];
            },
          ),
        );
      }

      final String invoiceNo = _asString(
        invoice['invoiceNo'],
      ).replaceAll('/', '_');
      final String name =
          '${clientName.isEmpty ? 'Invoice' : clientName}_$invoiceNo.pdf';
      final Uint8List bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: name);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF ready to share'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF export failed: ${_errorMessage(err)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  BoxDecoration _backgroundGradient() {
    return const BoxDecoration(color: _InvoiceViewColors.pageBackground);
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
      borderColor: _InvoiceViewColors.lightGray,
      child: Padding(padding: padding, child: child),
    );
  }

  ButtonStyle _outlinedButtonStyle({
    Color color = _InvoiceViewColors.primaryBlue,
    Color? borderColor,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: borderColor ?? _InvoiceViewColors.mediumGray),
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
            color: _InvoiceViewColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _InvoiceViewColors.lightGray),
          ),
          child: Icon(icon, size: 18, color: _InvoiceViewColors.primaryBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _InvoiceViewColors.darkGray,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _tinyStatPill({
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
              color: _InvoiceViewColors.textGray,
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

  Widget _softChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: _InvoiceViewColors.offWhite,
      selectedColor: _InvoiceViewColors.primaryBlue.withValues(alpha: 0.12),
      side: BorderSide(
        color: selected
            ? _InvoiceViewColors.primaryBlue.withValues(alpha: 0.5)
            : _InvoiceViewColors.lightGray,
      ),
      labelStyle: TextStyle(
        color: selected
            ? _InvoiceViewColors.primaryBlue
            : _InvoiceViewColors.darkGray,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
    );
  }

  Widget _detailRow({
    required String label,
    required String value,
    Color valueColor = _InvoiceViewColors.darkGray,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 12,
              color: _InvoiceViewColors.textGray,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
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
      borderColor: _InvoiceViewColors.lightGray,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: _InvoiceViewColors.mediumGray),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _InvoiceViewColors.darkGray,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _InvoiceViewColors.textGray,
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

  Widget _buildHeader() {
    final Map<String, dynamic>? invoice = _invoice;
    final String invoiceNo = invoice == null
        ? '-'
        : _asString(invoice['invoiceNo']).trim().isEmpty
        ? '-'
        : _asString(invoice['invoiceNo']).trim();
    final String client = _clientDisplayName.isEmpty ? '-' : _clientDisplayName;
    final Color pendingColor = _pending > 0
        ? _InvoiceViewColors.warningStripe
        : Colors.green;

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
                  color: _InvoiceViewColors.primaryBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invoice View',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _InvoiceViewColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$invoiceNo • $client',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _InvoiceViewColors.textGray,
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
              _tinyStatPill(
                label: 'Total AED',
                value: _total.toStringAsFixed(2),
                color: _InvoiceViewColors.primaryBlue,
              ),
              _tinyStatPill(
                label: 'Received AED',
                value: _totalReceived.toStringAsFixed(2),
                color: Colors.green,
              ),
              _tinyStatPill(
                label: 'Pending AED',
                value: _pending.toStringAsFixed(2),
                color: pendingColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return _glassPanel(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon: Icons.tune_rounded, title: 'Controls'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'invoice', label: Text('Invoice')),
              ButtonSegment(value: 'timesheet', label: Text('Timesheet')),
              ButtonSegment(value: 'receipts', label: Text('Receipts')),
            ],
            selected: <String>{_currentView},
            onSelectionChanged: (values) {
              setState(() => _currentView = values.first);
            },
            style: ButtonStyle(
              side: WidgetStateProperty.all(
                const BorderSide(color: _InvoiceViewColors.lightGray),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _InvoiceViewColors.primaryBlue.withValues(alpha: 0.12);
                }
                return _InvoiceViewColors.pureWhite;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _InvoiceViewColors.primaryBlue;
                }
                return _InvoiceViewColors.darkGray;
              }),
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _softChip(
                label: 'Due Date',
                selected: _includeDueDate,
                onSelected: (v) => setState(() => _includeDueDate = v),
              ),
              _softChip(
                label: 'Tax',
                selected: _includeTax,
                onSelected: (v) => setState(() => _includeTax = v),
              ),
              _softChip(
                label: 'Stamp',
                selected: _includeStamp,
                onSelected: (v) => setState(() => _includeStamp = v),
              ),
              _softChip(
                label: 'Signature',
                selected: _includeSignature,
                onSelected: (v) => setState(() => _includeSignature = v),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {}),
                style: _outlinedButtonStyle(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Recalc'),
              ),
              FilledButton.icon(
                onPressed: _exportingPdf ? null : _exportPdf,
                style: FilledButton.styleFrom(
                  backgroundColor: _InvoiceViewColors.primaryBlue,
                  foregroundColor: _InvoiceViewColors.pureWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: _exportingPdf
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceView() {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return _emptyBlock(
        icon: Icons.receipt_long_outlined,
        title: 'Invoice not found',
        subtitle: 'The requested invoice is unavailable.',
      );
    }
    final List<Map<String, dynamic>> items = _asMapList(
      invoice['invoiceItems'],
    );
    final Map<String, dynamic> client = _asMap(invoice['clientId']);
    final bool unpaid = _pending > 0;

    return Column(
      children: [
        _HoverCard(
          hoverable: true,
          elevation: 1.2,
          hoverElevation: 5,
          borderRadius: BorderRadius.circular(14),
          borderColor: _InvoiceViewColors.lightGray,
          leftAccentColor: unpaid ? _InvoiceViewColors.warningStripe : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool stacked = constraints.maxWidth < 760;
                final Widget left = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Client Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _InvoiceViewColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _detailRow(
                      label: 'Name',
                      value: _clientDisplayName.isEmpty
                          ? '-'
                          : _clientDisplayName,
                    ),
                    const SizedBox(height: 8),
                    _detailRow(
                      label: 'Address',
                      value: _asString(client['address']).isEmpty
                          ? '-'
                          : _asString(client['address']),
                    ),
                    const SizedBox(height: 8),
                    _detailRow(
                      label: 'TRN',
                      value: _asString(client['trn']).isEmpty
                          ? '-'
                          : _asString(client['trn']),
                    ),
                  ],
                );
                final Widget right = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invoice Meta',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _InvoiceViewColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Invoice Date',
                        style: TextStyle(
                          fontSize: 12,
                          color: _InvoiceViewColors.textGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _asString(invoice['invoiceDate']),
                        style: const TextStyle(
                          color: _InvoiceViewColors.darkGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: IconButton(
                        onPressed: () => _pickInvoiceDate('invoiceDate'),
                        icon: const Icon(Icons.edit_calendar_outlined),
                      ),
                    ),
                    TextFormField(
                      initialValue: _asString(invoice['invoiceNo']),
                      decoration: const InputDecoration(
                        labelText: 'Invoice Number',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => _setInvoiceField('invoiceNo', v),
                    ),
                    if (_includeDueDate) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'Due Date',
                          style: TextStyle(
                            fontSize: 12,
                            color: _InvoiceViewColors.textGray,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _asString(invoice['dueDate']),
                          style: const TextStyle(
                            color: _InvoiceViewColors.darkGray,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: IconButton(
                          onPressed: () => _pickInvoiceDate('dueDate'),
                          icon: const Icon(Icons.edit_calendar_outlined),
                        ),
                      ),
                    ],
                  ],
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [left, const SizedBox(height: 12), right],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 12),
                    Expanded(child: right),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _glassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                icon: Icons.inventory_2_outlined,
                title: 'Invoice Items',
              ),
              const SizedBox(height: 12),
              ...items.asMap().entries.map((entry) {
                final int index = entry.key;
                final Map<String, dynamic> item = entry.value;
                final double amount =
                    _asDouble(item['qty']) * _asDouble(item['unitPrice']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HoverCard(
                    hoverable: true,
                    elevation: 1,
                    hoverElevation: 3,
                    borderRadius: BorderRadius.circular(12),
                    borderColor: _InvoiceViewColors.lightGray,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _InvoiceViewColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _InvoiceViewColors.lightGray,
                                ),
                              ),
                              child: Text(
                                'AED ${amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: _InvoiceViewColors.darkGray,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: _asString(item['description']),
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) =>
                                _updateInvoiceItem(index, 'description', v),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: _asDouble(
                                    item['qty'],
                                  ).toString(),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (v) => _updateInvoiceItem(
                                    index,
                                    'qty',
                                    double.tryParse(v) ?? 0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: _asDouble(
                                    item['unitPrice'],
                                  ).toString(),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Unit Price',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (v) => _updateInvoiceItem(
                                    index,
                                    'unitPrice',
                                    double.tryParse(v) ?? 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: _addItem,
                style: _outlinedButtonStyle(),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Item'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _glassPanel(
          hoverable: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(icon: Icons.calculate_rounded, title: 'Summary'),
              const SizedBox(height: 12),
              _detailRow(
                label: 'Subtotal',
                value: _subtotal.toStringAsFixed(2),
              ),
              if (_includeTax) ...[
                const SizedBox(height: 8),
                _detailRow(
                  label:
                      'VAT ${(_asDouble(invoice['vatRate']) == 0 ? 5 : _asDouble(invoice['vatRate'])).toStringAsFixed(0)}%',
                  value: _vatAmount.toStringAsFixed(2),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              _detailRow(
                label: 'TOTAL AED',
                value: _total.toStringAsFixed(2),
                valueColor: _InvoiceViewColors.primaryBlue,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimesheetView() {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return _emptyBlock(
        icon: Icons.calendar_month_outlined,
        title: 'No invoice loaded',
        subtitle: 'Timesheet cannot be displayed right now.',
      );
    }
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon: Icons.calendar_month_rounded, title: 'Timesheet'),
          const SizedBox(height: 12),
          _detailRow(
            label: 'Location',
            value: _clientDisplayName.isEmpty ? '-' : _clientDisplayName,
          ),
          const SizedBox(height: 8),
          const _TextMeta('Service: Security Guards'),
          const SizedBox(height: 4),
          _TextMeta(
            'Period: ${_asString(invoice['periodFrom'])} to ${_asString(invoice['periodTo'])}',
          ),
          const SizedBox(height: 12),
          if (_processedTimesheet.isEmpty)
            const _TextMeta('No timesheet data available.')
          else
            ..._processedTimesheet.map((day) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HoverCard(
                  hoverable: true,
                  elevation: 1,
                  hoverElevation: 3,
                  borderRadius: BorderRadius.circular(12),
                  borderColor: _InvoiceViewColors.lightGray,
                  leftAccentColor: _InvoiceViewColors.warningStripe,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _asString(day['date']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _InvoiceViewColors.darkGray,
                            ),
                          ),
                        ),
                        Text(
                          '${_asDouble(day['guardCount']).toInt()} guards',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _InvoiceViewColors.textGray,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatHours(_asDouble(day['totalHours'])),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _InvoiceViewColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          Text(
            'TOTAL WORKING HOURS: ${_formatHours(_asDouble(invoice['totalHours']))}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: _InvoiceViewColors.darkGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptsView() {
    return Column(
      children: [
        _glassPanel(
          child: Row(
            children: [
              Expanded(
                child: _sectionTitle(
                  icon: Icons.payments_rounded,
                  title: 'Payment Receipts',
                  trailing: Text(
                    'Invoice: ${_asString(_invoice?['invoiceNo'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _InvoiceViewColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _openReceiptModal,
                style: FilledButton.styleFrom(
                  backgroundColor: _InvoiceViewColors.primaryBlue,
                  foregroundColor: _InvoiceViewColors.pureWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('New Receipt'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _glassPanel(
          hoverable: false,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tinyStatPill(
                label: 'Invoice Total',
                value: _total.toStringAsFixed(2),
                color: _InvoiceViewColors.darkGray,
              ),
              _tinyStatPill(
                label: 'Received',
                value: _totalReceived.toStringAsFixed(2),
                color: Colors.green,
              ),
              _tinyStatPill(
                label: 'Pending',
                value: _pending.toStringAsFixed(2),
                color: _pending > 0
                    ? _InvoiceViewColors.warningStripe
                    : Colors.green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_receipts.isEmpty)
          _emptyBlock(
            icon: Icons.payments_outlined,
            title: 'No receipts yet',
            subtitle: 'Create a receipt to track incoming payments.',
          )
        else
          ..._receipts.map((receipt) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _HoverCard(
                hoverable: true,
                elevation: 1,
                hoverElevation: 3,
                borderRadius: BorderRadius.circular(12),
                borderColor: _InvoiceViewColors.lightGray,
                leftAccentColor: Colors.green,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _asString(receipt['receiptNo']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _InvoiceViewColors.darkGray,
                              ),
                            ),
                          ),
                          Text(
                            'AED ${_asDouble(receipt['amountReceived']).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _detailRow(
                        label: 'Date',
                        value: _dateKey(
                          _tryDate(receipt['paymentDate']) ?? DateTime.now(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _detailRow(
                        label: 'Mode',
                        value: _asString(receipt['paymentMode']),
                      ),
                      if (_asString(receipt['note']).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _detailRow(
                          label: 'Note',
                          value: _asString(receipt['note']),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _deleteReceipt(_asString(receipt['_id']).trim()),
                          style: _outlinedButtonStyle(
                            color: Colors.red,
                            borderColor: Colors.red.withValues(alpha: 0.35),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _openReceiptModal() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: const [
                    Icon(
                      Icons.payments_outlined,
                      color: _InvoiceViewColors.primaryBlue,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Add Payment Receipt',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _InvoiceViewColors.darkGray,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 12),
                TextField(
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount Received (AED)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _receiptForm['amountReceived'] = v,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _asString(_receiptForm['paymentMode']),
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(
                      value: 'bank transfer',
                      child: Text('Bank Transfer'),
                    ),
                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                    DropdownMenuItem(
                      value: 'credit card',
                      child: Text('Credit Card'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _receiptForm['paymentMode'] = v;
                    }
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Payment Date'),
                  subtitle: Text(_asString(_receiptForm['paymentDate'])),
                  trailing: IconButton(
                    onPressed: () async {
                      final DateTime initial =
                          _tryDate(_receiptForm['paymentDate']) ??
                          DateTime.now();
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: DateTime(initial.year - 5),
                        lastDate: DateTime(initial.year + 5),
                      );
                      if (picked != null) {
                        setState(() {
                          _receiptForm['paymentDate'] = _dateKey(picked);
                        });
                      }
                    },
                    icon: const Icon(Icons.edit_calendar_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _receiptForm['note'] = v,
                ),
                const SizedBox(height: 8),
                TextField(
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _receiptForm['description'] = v,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        style: _outlinedButtonStyle(),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final bool saved = await _saveReceipt();
                                if (saved && dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _InvoiceViewColors.primaryBlue,
                          foregroundColor: _InvoiceViewColors.pureWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 16),
                        label: const Text('Save Receipt'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _InvoiceViewColors.pageBackground,
      body: Container(
        decoration: _backgroundGradient(),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: _buildHeader(),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchInvoice,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(
                            children: [
                              _buildTopControls(),
                              const SizedBox(height: 12),
                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 36),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (_invoice == null)
                                _emptyBlock(
                                  icon: Icons.receipt_long_outlined,
                                  title: 'Invoice not found or deleted',
                                  subtitle:
                                      'Please refresh or verify this invoice.',
                                )
                              else if (_currentView == 'invoice')
                                _buildInvoiceView()
                              else if (_currentView == 'timesheet')
                                _buildTimesheetView()
                              else
                                _buildReceiptsView(),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _saving ? null : _saveInvoice,
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        _InvoiceViewColors.primaryBlue,
                                    foregroundColor:
                                        _InvoiceViewColors.pureWhite,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.save_outlined,
                                          size: 16,
                                        ),
                                  label: const Text('Save Invoice'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: -1),
    );
  }
}

class _TextMeta extends StatelessWidget {
  const _TextMeta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _InvoiceViewColors.textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
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
          color: _InvoiceViewColors.pureWhite,
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
