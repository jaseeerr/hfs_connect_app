import 'package:dio/dio.dart';
import 'dart:typed_data';

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
  static const Color pageBackground = Color(0xFFF3F4F6);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color warning = Color(0xFFB45309);
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

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _InvoiceViewColors.pureWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _InvoiceViewColors.lightGray),
      ),
      child: child,
    );
  }

  Widget _buildTopControls() {
    return _sectionCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'invoice', label: Text('Invoice')),
                    ButtonSegment(value: 'timesheet', label: Text('Timesheet')),
                    ButtonSegment(value: 'receipts', label: Text('Receipts')),
                  ],
                  selected: <String>{_currentView},
                  onSelectionChanged: (values) {
                    setState(() => _currentView = values.first);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Due Date'),
                selected: _includeDueDate,
                onSelected: (v) => setState(() => _includeDueDate = v),
              ),
              FilterChip(
                label: const Text('Tax'),
                selected: _includeTax,
                onSelected: (v) => setState(() => _includeTax = v),
              ),
              FilterChip(
                label: const Text('Stamp'),
                selected: _includeStamp,
                onSelected: (v) => setState(() => _includeStamp = v),
              ),
              FilterChip(
                label: const Text('Signature'),
                selected: _includeSignature,
                onSelected: (v) => setState(() => _includeSignature = v),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Recalc'),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    onPressed: _exportingPdf ? null : _exportPdf,
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
        ],
      ),
    );
  }

  Widget _buildInvoiceView() {
    final Map<String, dynamic>? invoice = _invoice;
    if (invoice == null) {
      return _sectionCard(child: const Text('Invoice not found'));
    }
    final List<Map<String, dynamic>> items = _asMapList(
      invoice['invoiceItems'],
    );
    final Map<String, dynamic> client = _asMap(invoice['clientId']);

    return Column(
      children: [
        _sectionCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool stacked = constraints.maxWidth < 760;
              final Widget left = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _clientDisplayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _InvoiceViewColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _asString(client['address']),
                    style: const TextStyle(
                      color: _InvoiceViewColors.textGray,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _asString(client['trn']).isEmpty
                        ? ''
                        : 'TRN: ${_asString(client['trn'])}',
                    style: const TextStyle(
                      color: _InvoiceViewColors.textGray,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
              final Widget right = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invoice Date',
                    style: TextStyle(
                      fontSize: 12,
                      color: _InvoiceViewColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_asString(invoice['invoiceDate'])),
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
                      title: const Text('Due Date'),
                      subtitle: Text(_asString(invoice['dueDate'])),
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
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 12),
                  Expanded(child: right),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Invoice Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _InvoiceViewColors.darkGray,
                ),
              ),
              const SizedBox(height: 10),
              ...items.asMap().entries.map((entry) {
                final int index = entry.key;
                final Map<String, dynamic> item = entry.value;
                final double amount =
                    _asDouble(item['qty']) * _asDouble(item['unitPrice']);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _InvoiceViewColors.lightGray),
                  ),
                  child: Column(
                    children: [
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
                              initialValue: _asDouble(item['qty']).toString(),
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
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Amount: ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _InvoiceViewColors.darkGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Item'),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _InvoiceViewColors.mediumGray),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Subtotal'),
                        const Spacer(),
                        Text(_subtotal.toStringAsFixed(2)),
                      ],
                    ),
                    if (_includeTax) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'VAT ${(_asDouble(invoice['vatRate']) == 0 ? 5 : _asDouble(invoice['vatRate'])).toStringAsFixed(0)}%',
                          ),
                          const Spacer(),
                          Text(_vatAmount.toStringAsFixed(2)),
                        ],
                      ),
                    ],
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Text(
                          'TOTAL AED',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          _total.toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
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
      return _sectionCard(child: const Text('No invoice loaded'));
    }
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Location: ${_clientDisplayName.isEmpty ? '-' : _clientDisplayName}',
            style: const TextStyle(
              color: _InvoiceViewColors.darkGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Service: Security Guards',
            style: TextStyle(color: _InvoiceViewColors.textGray, fontSize: 12),
          ),
          Text(
            'Period: ${_asString(invoice['periodFrom'])} to ${_asString(invoice['periodTo'])}',
            style: const TextStyle(
              color: _InvoiceViewColors.textGray,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          if (_processedTimesheet.isEmpty)
            const Text(
              'No timesheet data available.',
              style: TextStyle(color: _InvoiceViewColors.textGray),
            )
          else
            ..._processedTimesheet.map((day) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _InvoiceViewColors.lightGray),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _asString(day['date']),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
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
              );
            }),
          const Divider(height: 18),
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
        _sectionCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Receipts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _InvoiceViewColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Invoice: ${_asString(_invoice?['invoiceNo'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _InvoiceViewColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _openReceiptModal,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('New Receipt'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _sectionCard(
          child: Row(
            children: [
              Expanded(
                child: _summaryBox(
                  'Invoice Total',
                  _total,
                  _InvoiceViewColors.darkGray,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox('Received', _totalReceived, Colors.green),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryBox(
                  'Pending',
                  _pending,
                  _InvoiceViewColors.warning,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_receipts.isEmpty)
          _sectionCard(
            child: const Text(
              'No receipts yet.',
              style: TextStyle(color: _InvoiceViewColors.textGray),
            ),
          )
        else
          ..._receipts.map((receipt) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _sectionCard(
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
                    const SizedBox(height: 4),
                    Text(
                      _dateKey(
                        _tryDate(receipt['paymentDate']) ?? DateTime.now(),
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _InvoiceViewColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mode: ${_asString(receipt['paymentMode'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _InvoiceViewColors.textGray,
                      ),
                    ),
                    if (_asString(receipt['note']).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _asString(receipt['note']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _InvoiceViewColors.darkGray,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _deleteReceipt(_asString(receipt['_id']).trim()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _summaryBox(String label, double value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _InvoiceViewColors.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: _InvoiceViewColors.textGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'AED ${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReceiptModal() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Payment Receipt',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _InvoiceViewColors.darkGray,
                  ),
                ),
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
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
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
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
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
      appBar: AppBar(
        title: const Text('Invoice View'),
        backgroundColor: _InvoiceViewColors.pureWhite,
        surfaceTintColor: _InvoiceViewColors.pureWhite,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _buildTopControls(),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_invoice == null)
                  _sectionCard(
                    child: const Text(
                      'Invoice not found or deleted.',
                      style: TextStyle(color: _InvoiceViewColors.textGray),
                    ),
                  )
                else if (_currentView == 'invoice')
                  _buildInvoiceView()
                else if (_currentView == 'timesheet')
                  _buildTimesheetView()
                else
                  _buildReceiptsView(),
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
      bottomNavigationBar: const AppBottomNavBar(currentIndex: -1),
    );
  }
}
