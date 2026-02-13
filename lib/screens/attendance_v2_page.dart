import 'dart:io';

import 'package:dio/dio.dart';
import 'package:excel/excel.dart' show CellValue, Excel, Sheet, TextCellValue;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../app_routes.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/tester_data_service.dart';
import '../widget/app_bottom_nav_bar.dart';

class _AttendanceV2Colors {
  const _AttendanceV2Colors._();

  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pageBackground = Color(0xFFF3F4F6);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color warningStripe = Color(0xFFD97706);
}

class AttendanceV2Page extends StatefulWidget {
  const AttendanceV2Page({super.key});

  @override
  State<AttendanceV2Page> createState() => _AttendanceV2PageState();
}

class _AttendanceV2PageState extends State<AttendanceV2Page> {
  static const String _authBox = 'auth_box';
  static const String _fromKey = 'attendanceV2DateFrom';
  static const String _toKey = 'attendanceV2DateTo';

  final Map<String, bool> _expandedGuards = <String, bool>{};

  bool _loading = false;
  bool _savingShift = false;

  DateTime? _startDate;
  DateTime? _endDate;

  List<Map<String, dynamic>> _clients = <Map<String, dynamic>>[];

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

  DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _dateKey(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatHours(double decimalHours) {
    if (decimalHours.isNaN) {
      return '0 hrs';
    }
    final int hours = decimalHours.floor();
    final int minutes = ((decimalHours - hours) * 60).round();
    if (minutes == 0) {
      return '$hours ${hours == 1 ? 'hr' : 'hrs'}';
    }
    if (hours == 0) {
      return '$minutes ${minutes == 1 ? 'min' : 'mins'}';
    }
    return '$hours ${hours == 1 ? 'hr' : 'hrs'} $minutes ${minutes == 1 ? 'min' : 'mins'}';
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) {
      return '--';
    }
    final int hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final String amPm = date.hour >= 12 ? 'PM' : 'AM';
    final String minute = date.minute.toString().padLeft(2, '0');
    final List<String> month = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${month[date.month - 1]} ${date.year}, $hour:$minute $amPm';
  }

  double _roundToNearestHalfHour(double hours) {
    final int wholeHours = hours.floor();
    final double minutes = (hours - wholeHours) * 60;
    if (minutes < 15) {
      return wholeHours.toDouble();
    }
    if (minutes < 45) {
      return wholeHours + 0.5;
    }
    return wholeHours + 1;
  }

  String _errorMessage(Object err) {
    if (err is DioException) {
      final Map<String, dynamic> body = _asMap(err.response?.data);
      final String apiError = _asString(body['error']).trim();
      final String apiMessage = _asString(body['message']).trim();
      if (apiError.isNotEmpty) {
        return apiError;
      }
      if (apiMessage.isNotEmpty) {
        return apiMessage;
      }
      if (_asString(err.message).isNotEmpty) {
        return _asString(err.message);
      }
    }
    return _asString(err).replaceFirst('Exception: ', '');
  }

  @override
  void initState() {
    super.initState();
    _initDates();
  }

  Future<void> _initDates() async {
    final DateTime now = DateTime.now();
    DateTime start = DateTime(now.year, now.month, 1);
    DateTime end = _normalize(now);
    if (!Hive.isBoxOpen(_authBox)) {
      await Hive.openBox<dynamic>(_authBox);
    }
    final Box<dynamic> box = Hive.box<dynamic>(_authBox);
    final DateTime? savedFrom = DateTime.tryParse(_asString(box.get(_fromKey)));
    final DateTime? savedTo = DateTime.tryParse(_asString(box.get(_toKey)));
    if (savedFrom != null && savedTo != null) {
      start = _normalize(savedFrom);
      end = _normalize(savedTo);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  Future<void> _saveDates() async {
    if (_startDate == null || _endDate == null) {
      return;
    }
    if (!Hive.isBoxOpen(_authBox)) {
      await Hive.openBox<dynamic>(_authBox);
    }
    final Box<dynamic> box = Hive.box<dynamic>(_authBox);
    await box.put(_fromKey, _dateKey(_startDate!));
    await box.put(_toKey, _dateKey(_endDate!));
  }

  Future<void> _pickStartDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _startDate = _normalize(picked);
      if (_endDate != null && _endDate!.isBefore(_startDate!)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final DateTime now = DateTime.now();
    final DateTime minDate = _startDate ?? DateTime(now.year - 2);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? minDate,
      firstDate: minDate,
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _endDate = _normalize(picked);
    });
  }

  List<Map<String, dynamic>> _processAttendanceByContract(
    List<Map<String, dynamic>> rawData,
  ) {
    return rawData.map((client) {
      final Map<String, dynamic> updatedClient = <String, dynamic>{...client};
      final List<Map<String, dynamic>> guards = _asMapList(client['guards']);
      updatedClient['guards'] = guards.map((guard) {
        final Map<String, dynamic> updatedGuard = <String, dynamic>{...guard};
        final List<Map<String, dynamic>> shifts = _asMapList(guard['shifts']);
        updatedGuard['shifts'] = shifts.map((shift) {
          final Map<String, dynamic> updatedShift = <String, dynamic>{...shift};
          final double actualHours = _asDouble(shift['hours']);
          final double roundedHours = _roundToNearestHalfHour(actualHours);
          updatedShift['hours'] = roundedHours;
          updatedShift['actualHours'] = double.parse(
            actualHours.toStringAsFixed(2),
          );
          return updatedShift;
        }).toList();
        updatedGuard['totalHours'] = _asMapList(
          updatedGuard['shifts'],
        ).fold<double>(0, (sum, shift) => sum + _asDouble(shift['hours']));
        return updatedGuard;
      }).toList();
      updatedClient['totalHours'] = _asMapList(
        updatedClient['guards'],
      ).fold<double>(0, (sum, guard) => sum + _asDouble(guard['totalHours']));
      return updatedClient;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchTesterContractReport() async {
    final List<Map<String, dynamic>> guards =
        await TesterDataService.getGuards();
    final Map<String, Map<String, dynamic>> clientsById =
        <String, Map<String, dynamic>>{};

    for (final Map<String, dynamic> guard in guards) {
      final Map<String, dynamic> attendance =
          await TesterDataService.getAttendanceReportForGuard(
            guardId: _asString(guard['_id']),
            startDate: _dateKey(_startDate!),
            endDate: _dateKey(_endDate!),
          );
      for (final Map<String, dynamic> client in _asMapList(
        attendance['clients'],
      )) {
        final String clientId = _asString(client['clientId']).trim();
        if (clientId.isEmpty) {
          continue;
        }
        clientsById.putIfAbsent(clientId, () {
          return <String, dynamic>{
            'clientId': clientId,
            'clientName': _asString(client['clientName']),
            'totalHours': 0.0,
            'guards': <Map<String, dynamic>>[],
          };
        });
        final Map<String, dynamic> bucket = clientsById[clientId]!;
        final List<Map<String, dynamic>> bucketGuards = _asMapList(
          bucket['guards'],
        );
        final List<Map<String, dynamic>> guardShifts =
            _asMapList(client['shifts']).map((shift) {
              return <String, dynamic>{
                'shiftId': _asString(shift['shiftId']),
                'contractId': '',
                'rosterId': '',
                'date': _formatDateTime(
                  DateTime.tryParse(_asString(shift['start'])),
                ),
                'checkInAt': _asString(shift['checkInAt']),
                'checkOutAt': _asString(shift['checkOutAt']),
                'hours': _asDouble(shift['hours']),
                'actualHours': _asDouble(shift['hours']),
              };
            }).toList();
        bucketGuards.add(<String, dynamic>{
          'guardId': _asString(guard['_id']),
          'name': _asString(guard['name']),
          'totalHours': _asDouble(client['totalHours']),
          'shifts': guardShifts,
        });
        bucket['guards'] = bucketGuards;
      }
    }

    return clientsById.values.toList();
  }

  Future<void> _fetchReport() async {
    if (_startDate == null || _endDate == null) {
      return;
    }
    setState(() {
      _loading = true;
      _clients = <Map<String, dynamic>>[];
      _expandedGuards.clear();
    });
    try {
      await _saveDates();

      final List<Map<String, dynamic>> rawData;
      if (AuthStorage.isTester) {
        rawData = await _fetchTesterContractReport();
      } else {
        final Response<dynamic> res =
            await ApiClient.create(opt: 0, token: AuthStorage.token).post(
              '/attendanceByContract',
              data: <String, dynamic>{
                'startDate': _dateKey(_startDate!),
                'endDate': _dateKey(_endDate!),
              },
            );
        rawData = _asMapList(_asMap(res.data)['data']);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _clients = _processAttendanceByContract(rawData);
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
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _toggleGuard(String clientId, String guardId) {
    final String key = '$clientId-$guardId';
    setState(() {
      _expandedGuards[key] = !(_expandedGuards[key] ?? false);
    });
  }

  Future<void> _exportToExcel() async {
    if (_clients.isEmpty) {
      return;
    }
    try {
      final Excel excel = Excel.createExcel();
      final Sheet sheet = excel['Attendance Report'];
      sheet.appendRow(<CellValue>[
        TextCellValue('Client Name'),
        TextCellValue('Guard Name'),
        TextCellValue('Shift Date'),
        TextCellValue('Check-In'),
        TextCellValue('Check-Out'),
        TextCellValue('Rounded Hours'),
        TextCellValue('Actual Hours'),
      ]);

      for (final Map<String, dynamic> client in _clients) {
        for (final Map<String, dynamic> guard in _asMapList(client['guards'])) {
          for (final Map<String, dynamic> shift in _asMapList(
            guard['shifts'],
          )) {
            sheet.appendRow(<CellValue>[
              TextCellValue(_asString(client['clientName'])),
              TextCellValue(_asString(guard['name'])),
              TextCellValue(_asString(shift['date'])),
              TextCellValue(
                _formatDateTime(
                  DateTime.tryParse(_asString(shift['checkInAt'])),
                ),
              ),
              TextCellValue(
                _formatDateTime(
                  DateTime.tryParse(_asString(shift['checkOutAt'])),
                ),
              ),
              TextCellValue(_asDouble(shift['hours']).toStringAsFixed(2)),
              TextCellValue(_asDouble(shift['actualHours']).toStringAsFixed(2)),
            ]);
          }
        }
      }

      final List<int>? bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Failed to encode Excel file');
      }
      final Directory dir = await getApplicationDocumentsDirectory();
      final String path =
          '${dir.path}/Attendance_By_Client_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final File file = File(path);
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel exported to: $path'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${_errorMessage(err)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 2),
    );
    if (date == null) {
      return null;
    }
    if (!mounted) {
      return null;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (pickerContext, child) {
        return MediaQuery(
          data: MediaQuery.of(
            pickerContext,
          ).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _openEditShift(Map<String, dynamic> shift) async {
    DateTime checkIn =
        DateTime.tryParse(_asString(shift['checkInAt'])) ?? DateTime.now();
    DateTime checkOut =
        DateTime.tryParse(_asString(shift['checkOutAt'])) ?? DateTime.now();
    final String contractId = _asString(shift['contractId']).trim();
    final String rosterId = _asString(shift['rosterId']).trim();
    final String shiftId = _asString(shift['shiftId']).trim();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Shift Timing'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Check-In'),
                    subtitle: Text(_formatDateTime(checkIn)),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final DateTime? picked = await _pickDateTime(checkIn);
                      if (picked != null) {
                        setDialogState(() => checkIn = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Check-Out'),
                    subtitle: Text(_formatDateTime(checkOut)),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final DateTime? picked = await _pickDateTime(checkOut);
                      if (picked != null) {
                        setDialogState(() => checkOut = picked);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _savingShift
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _savingShift
                      ? null
                      : () async {
                          if (checkOut.isBefore(checkIn)) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Check-out must be after check-in',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          if (AuthStorage.isTester ||
                              contractId.isEmpty ||
                              rosterId.isEmpty ||
                              shiftId.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Editing shift timing is unavailable for this record.',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          setState(() => _savingShift = true);
                          try {
                            await ApiClient.create(
                              opt: 0,
                              token: AuthStorage.token,
                            ).put(
                              '/updateShiftTiming/$contractId/$rosterId/$shiftId',
                              data: <String, dynamic>{
                                'checkInAt': checkIn.toIso8601String(),
                                'checkOutAt': checkOut.toIso8601String(),
                              },
                            );

                            final double hours =
                                checkOut.difference(checkIn).inMinutes / 60;
                            final double rounded = _roundToNearestHalfHour(
                              hours,
                            );

                            setState(() {
                              for (final Map<String, dynamic> client
                                  in _clients) {
                                for (final Map<String, dynamic> guard
                                    in _asMapList(client['guards'])) {
                                  for (final Map<String, dynamic> rowShift
                                      in _asMapList(guard['shifts'])) {
                                    if (_asString(rowShift['shiftId']) ==
                                        shiftId) {
                                      rowShift['checkInAt'] = checkIn
                                          .toIso8601String();
                                      rowShift['checkOutAt'] = checkOut
                                          .toIso8601String();
                                      rowShift['hours'] = rounded;
                                      rowShift['actualHours'] = double.parse(
                                        hours.toStringAsFixed(2),
                                      );
                                    }
                                  }
                                  guard['totalHours'] =
                                      _asMapList(guard['shifts']).fold<double>(
                                        0,
                                        (sum, s) => sum + _asDouble(s['hours']),
                                      );
                                }
                                client['totalHours'] =
                                    _asMapList(client['guards']).fold<double>(
                                      0,
                                      (sum, g) =>
                                          sum + _asDouble(g['totalHours']),
                                    );
                              }
                            });

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          } catch (err) {
                            if (!mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(_errorMessage(err)),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _savingShift = false);
                            }
                          }
                        },
                  child: _savingShift
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _generateInvoice(Map<String, dynamic> client) {
    final Map<String, dynamic> clientData = <String, dynamic>{
      'clientId': _asString(client['clientId']),
      'clientName': _asString(client['clientName']),
      'totalHours': _asDouble(client['totalHours']),
      'periodFrom': _startDate == null ? '' : _dateKey(_startDate!),
      'periodTo': _endDate == null ? '' : _dateKey(_endDate!),
      'guards': _asMapList(client['guards']).map((guard) {
        return <String, dynamic>{
          'guardId': _asString(guard['guardId']),
          'name': _asString(guard['name']),
          'shifts': _asMapList(guard['shifts']).map((shift) {
            return <String, dynamic>{
              'date': _asString(shift['date']),
              'hours': _asDouble(shift['hours']),
              'checkInAt': _asString(shift['checkInAt']),
              'checkOutAt': _asString(shift['checkOutAt']),
            };
          }).toList(),
        };
      }).toList(),
    };
    Navigator.of(context).pushNamed(
      AppRoutes.generateInvoice,
      arguments: <String, dynamic>{'clientData': clientData},
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _AttendanceV2Colors.pureWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _AttendanceV2Colors.lightGray),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: _AttendanceV2Colors.primaryBlue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _AttendanceV2Colors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value == null ? '--' : _dateKey(value),
                    style: const TextStyle(
                      fontSize: 13,
                      color: _AttendanceV2Colors.darkGray,
                      fontWeight: FontWeight.w600,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AttendanceV2Colors.pageBackground,
      appBar: AppBar(
        title: const Text('Attendance by Client'),
        backgroundColor: _AttendanceV2Colors.pureWhite,
        surfaceTintColor: _AttendanceV2Colors.pureWhite,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchReport,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _AttendanceV2Colors.pureWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _AttendanceV2Colors.lightGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Date Filters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _AttendanceV2Colors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _dateField(
                      label: 'From Date',
                      value: _startDate,
                      onTap: _pickStartDate,
                    ),
                    const SizedBox(height: 8),
                    _dateField(
                      label: 'To Date',
                      value: _endDate,
                      onTap: _pickEndDate,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _fetchReport,
                            icon: const Icon(
                              Icons.analytics_outlined,
                              size: 18,
                            ),
                            label: const Text('Generate Report'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clients.isEmpty ? null : _exportToExcel,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Export Excel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_clients.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _AttendanceV2Colors.pureWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _AttendanceV2Colors.lightGray),
                  ),
                  child: const Text(
                    'No clients found. Select date range and click Generate Report.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _AttendanceV2Colors.textGray),
                  ),
                )
              else
                ..._clients.map((client) {
                  final String clientId = _asString(client['clientId']);
                  final List<Map<String, dynamic>> guards = _asMapList(
                    client['guards'],
                  );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _AttendanceV2Colors.pureWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _AttendanceV2Colors.lightGray),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _asString(client['clientName']).isEmpty
                                        ? 'Unnamed Client'
                                        : _asString(client['clientName']),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: _AttendanceV2Colors.darkGray,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Total Guards: ${guards.length}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _AttendanceV2Colors.textGray,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatHours(_asDouble(client['totalHours'])),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _AttendanceV2Colors.primaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                OutlinedButton(
                                  onPressed: () => _generateInvoice(client),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        _AttendanceV2Colors.warningStripe,
                                    side: const BorderSide(
                                      color: _AttendanceV2Colors.warningStripe,
                                    ),
                                    minimumSize: const Size(0, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                  ),
                                  child: const Text('Generate Invoice'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final Map<String, dynamic> guard in guards)
                          Builder(
                            builder: (context) {
                              final String guardId = _asString(
                                guard['guardId'],
                              );
                              final String key = '$clientId-$guardId';
                              final bool expanded =
                                  _expandedGuards[key] ?? false;
                              final List<Map<String, dynamic>> shifts =
                                  _asMapList(guard['shifts']);

                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _AttendanceV2Colors.lightGray,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          _toggleGuard(clientId, guardId),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _asString(guard['name']).isEmpty
                                                    ? 'Guard'
                                                    : _asString(guard['name']),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: _AttendanceV2Colors
                                                      .darkGray,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatHours(
                                                _asDouble(guard['totalHours']),
                                              ),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: _AttendanceV2Colors
                                                    .textGray,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              expanded
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                              size: 18,
                                              color:
                                                  _AttendanceV2Colors.textGray,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (expanded)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          0,
                                          10,
                                          8,
                                        ),
                                        child: Column(
                                          children: shifts.isEmpty
                                              ? const [
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 6,
                                                          ),
                                                      child: Text(
                                                        'No shifts recorded.',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              _AttendanceV2Colors
                                                                  .textGray,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ]
                                              : shifts.map((shift) {
                                                  return Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          top: 6,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: _AttendanceV2Colors
                                                          .pageBackground,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                _asString(
                                                                  shift['date'],
                                                                ),
                                                                style: const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: _AttendanceV2Colors
                                                                      .darkGray,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 2,
                                                              ),
                                                              Text(
                                                                'In: ${_formatDateTime(DateTime.tryParse(_asString(shift['checkInAt'])))}',
                                                                style: const TextStyle(
                                                                  fontSize: 11,
                                                                  color: _AttendanceV2Colors
                                                                      .textGray,
                                                                ),
                                                              ),
                                                              Text(
                                                                'Out: ${_formatDateTime(DateTime.tryParse(_asString(shift['checkOutAt'])))}',
                                                                style: const TextStyle(
                                                                  fontSize: 11,
                                                                  color: _AttendanceV2Colors
                                                                      .textGray,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              Text(
                                                                '${_formatHours(_asDouble(shift['hours']))} (actual: ${_formatHours(_asDouble(shift['actualHours']))})',
                                                                style: const TextStyle(
                                                                  fontSize: 11,
                                                                  color: _AttendanceV2Colors
                                                                      .darkGray,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        IconButton(
                                                          onPressed: () =>
                                                              _openEditShift(
                                                                shift,
                                                              ),
                                                          icon: const Icon(
                                                            Icons.edit_outlined,
                                                            size: 18,
                                                            color:
                                                                _AttendanceV2Colors
                                                                    .primaryBlue,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }).toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: -1),
    );
  }
}
