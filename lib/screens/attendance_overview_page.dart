import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_routes.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/tester_data_service.dart';
import '../widget/app_bottom_nav_bar.dart';

class _OverviewColors {
  const _OverviewColors._();

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

class AttendanceOverviewPage extends StatefulWidget {
  const AttendanceOverviewPage({super.key});

  @override
  State<AttendanceOverviewPage> createState() => _AttendanceOverviewPageState();
}

class _AttendanceOverviewPageState extends State<AttendanceOverviewPage> {
  static const String _authBox = 'auth_box';
  static const String _fromKey = 'attendanceDateFrom';
  static const String _toKey = 'attendanceDateTo';

  bool _loading = false;
  int _progressCurrent = 0;
  int _progressTotal = 0;

  DateTime? _startDate;
  DateTime? _endDate;

  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];

  int _totalGuards = 0;
  double _totalHours = 0;
  double _avgHours = 0;

  @override
  void initState() {
    super.initState();
    _initDates();
  }

  String _asString(dynamic value) => value == null ? '' : value.toString();

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

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_asString(value)) ?? 0;
  }

  DateTime _normalize(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dateKey(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _monthName(int month) {
    const List<String> names = <String>[
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
    return names[(month.clamp(1, 12)) - 1];
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';
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

  double _roundToNearestHalfHour(double hours) {
    final int whole = hours.floor();
    final double minutes = (hours - whole) * 60;
    if (minutes < 15) {
      return whole.toDouble();
    }
    if (minutes < 45) {
      return whole + 0.5;
    }
    return whole + 1.0;
  }

  String _errorMessage(Object err) {
    if (err is DioException) {
      final Map<String, dynamic> body = _asMap(err.response?.data);
      final String error = _asString(body['error']).trim();
      final String message = _asString(body['message']).trim();
      if (error.isNotEmpty) {
        return error;
      }
      if (message.isNotEmpty) {
        return message;
      }
      final String fallback = _asString(err.message).trim();
      if (fallback.isNotEmpty) {
        return fallback;
      }
    }
    return _asString(err).replaceFirst('Exception: ', '');
  }

  Future<void> _initDates() async {
    final DateTime now = DateTime.now();
    DateTime from = DateTime(now.year, now.month, 1);
    DateTime to = _normalize(now);

    if (!Hive.isBoxOpen(_authBox)) {
      await Hive.openBox<dynamic>(_authBox);
    }
    final Box<dynamic> box = Hive.box<dynamic>(_authBox);
    final DateTime? savedFrom = DateTime.tryParse(_asString(box.get(_fromKey)));
    final DateTime? savedTo = DateTime.tryParse(_asString(box.get(_toKey)));

    if (savedFrom != null && savedTo != null) {
      from = _normalize(savedFrom);
      to = _normalize(savedTo);
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _startDate = from;
      _endDate = to;
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
    final DateTime min = _startDate ?? DateTime(now.year - 2);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? min,
      firstDate: min,
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _endDate = _normalize(picked);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchGuards() async {
    if (AuthStorage.isTester) {
      return TesterDataService.getGuards();
    }

    final Response<dynamic> response = await ApiClient.create(
      opt: 0,
      token: AuthStorage.token,
    ).get('/guards');
    final Map<String, dynamic> body = _asMap(response.data);
    if (body['ok'] != true) {
      throw Exception(
        _asString(body['error']).isNotEmpty
            ? _asString(body['error'])
            : 'Failed to fetch guards',
      );
    }
    return _asMapList(body['data']);
  }

  Future<Map<String, dynamic>?> _fetchGuardAttendance(
    Map<String, dynamic> guard,
  ) async {
    final String guardId = _asString(guard['_id']).trim();
    if (guardId.isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic> data;
      if (AuthStorage.isTester) {
        data = await TesterDataService.getAttendanceReportForGuard(
          guardId: guardId,
          startDate: _dateKey(_startDate!),
          endDate: _dateKey(_endDate!),
        );
      } else {
        final Response<dynamic> response =
            await ApiClient.create(opt: 0, token: AuthStorage.token).post(
              '/attendance/guard/$guardId',
              data: <String, dynamic>{
                'startDate': _dateKey(_startDate!),
                'endDate': _dateKey(_endDate!),
              },
            );
        data = _asMap(response.data);
      }

      final List<Map<String, dynamic>> clients = _asMapList(data['clients']);
      double totalHours = 0;
      int totalShifts = 0;

      for (final Map<String, dynamic> client in clients) {
        final List<Map<String, dynamic>> shifts = _asMapList(client['shifts']);
        totalShifts += shifts.length;
        for (final Map<String, dynamic> shift in shifts) {
          final double hrs = _asDouble(shift['hours']);
          totalHours += _roundToNearestHalfHour(hrs);
        }
      }

      if (totalHours <= 0) {
        return null;
      }

      return <String, dynamic>{
        'guardId': guardId,
        'name': _asString(guard['name']),
        'phone': _asString(guard['phone']),
        'type': _asString(guard['type']),
        'photo': _asString(guard['photo']),
        'totalHours': totalHours,
        'totalShifts': totalShifts,
        'clientsWorked': clients.length,
      };
    } catch (_) {
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _progressCurrent += 1;
        });
      }
    }
  }

  Future<void> _fetchReport() async {
    if (_startDate == null || _endDate == null) {
      return;
    }

    setState(() {
      _loading = true;
      _records = <Map<String, dynamic>>[];
      _progressCurrent = 0;
      _progressTotal = 0;
      _totalGuards = 0;
      _totalHours = 0;
      _avgHours = 0;
    });

    try {
      await _saveDates();
      final List<Map<String, dynamic>> guards = await _fetchGuards();

      if (!mounted) {
        return;
      }
      setState(() {
        _progressTotal = guards.length;
      });

      final List<Map<String, dynamic>?> all = await Future.wait(
        guards.map(_fetchGuardAttendance),
      );

      final List<Map<String, dynamic>> records =
          all.whereType<Map<String, dynamic>>().toList()..sort(
            (a, b) => _asDouble(
              b['totalHours'],
            ).compareTo(_asDouble(a['totalHours'])),
          );

      final int totalGuards = records.length;
      final double totalHours = records.fold<double>(
        0,
        (sum, item) => sum + _asDouble(item['totalHours']),
      );
      final double avgHours = totalGuards == 0 ? 0 : totalHours / totalGuards;

      if (!mounted) {
        return;
      }
      setState(() {
        _records = records;
        _totalGuards = totalGuards;
        _totalHours = totalHours;
        _avgHours = avgHours;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(err)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _OverviewColors.warning,
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
      borderColor: _OverviewColors.lightGray,
      child: Padding(padding: padding, child: child),
    );
  }

  ButtonStyle _outlinedButtonStyle({
    Color color = _OverviewColors.primaryBlue,
    Color? borderColor,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: borderColor ?? _OverviewColors.mediumGray),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  Widget _emptyBlock({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return _HoverCard(
      hoverable: false,
      elevation: 0,
      hoverElevation: 0,
      borderRadius: BorderRadius.circular(14),
      borderColor: _OverviewColors.lightGray,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: _OverviewColors.mediumGray),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _OverviewColors.darkGray,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _OverviewColors.textGray,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerSection() {
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
                  color: _OverviewColors.primaryBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.analytics_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Overview',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: _OverviewColors.darkGray,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Combined summary of all guards\' hours and shifts',
                      style: TextStyle(
                        fontSize: 13,
                        color: _OverviewColors.textGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tinyChip(
                icon: Icons.people_outline,
                text: '$_totalGuards Active Guards',
                color: _OverviewColors.primaryBlue,
              ),
              _tinyChip(
                icon: Icons.schedule_rounded,
                text: _formatHours(_totalHours),
                color: _OverviewColors.primaryBlue,
              ),
              _tinyChip(
                icon: Icons.query_stats_rounded,
                text: 'Avg ${_formatHours(_avgHours)}',
                color: _OverviewColors.warningStripe,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tinyChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _OverviewColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _OverviewColors.lightGray),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtersSection() {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Date Filters',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _OverviewColors.darkGray,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool stacked = constraints.maxWidth < 620;

              Widget dateField({
                required String label,
                required DateTime? value,
                required VoidCallback onTap,
              }) {
                return InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: _OverviewColors.offWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _OverviewColors.lightGray),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: _OverviewColors.primaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _OverviewColors.textGray,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                value == null ? '--' : _formatDate(value),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _OverviewColors.darkGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.expand_more_rounded,
                          color: _OverviewColors.textGray,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              }

              Widget actions = Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _fetchReport,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        backgroundColor: _OverviewColors.primaryBlue,
                        disabledBackgroundColor: _OverviewColors.mediumGray,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.trending_up_rounded, size: 18),
                      label: const Text('Generate Report'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _records.isEmpty
                          ? null
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Export to Excel not yet ready',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                      style: _outlinedButtonStyle(),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
                ],
              );

              if (stacked) {
                return Column(
                  children: [
                    dateField(
                      label: 'From Date',
                      value: _startDate,
                      onTap: _pickStartDate,
                    ),
                    const SizedBox(height: 8),
                    dateField(
                      label: 'To Date',
                      value: _endDate,
                      onTap: _pickEndDate,
                    ),
                    const SizedBox(height: 10),
                    actions,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: dateField(
                      label: 'From Date',
                      value: _startDate,
                      onTap: _pickStartDate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: dateField(
                      label: 'To Date',
                      value: _endDate,
                      onTap: _pickEndDate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: actions),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statsSection() {
    final List<Widget> cards = [
      _statCard(
        icon: Icons.people_alt_outlined,
        label: 'Total Guards',
        value: _totalGuards.toString(),
        color: _OverviewColors.primaryBlue,
      ),
      _statCard(
        icon: Icons.schedule_rounded,
        label: 'Total Hours',
        value: _formatHours(_totalHours),
        color: _OverviewColors.primaryBlue,
      ),
      _statCard(
        icon: Icons.bar_chart_rounded,
        label: 'Avg Hours / Guard',
        value: _formatHours(_avgHours),
        color: _OverviewColors.warningStripe,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        }
        return Column(
          children: [
            cards[0],
            const SizedBox(height: 8),
            cards[1],
            const SizedBox(height: 8),
            cards[2],
          ],
        );
      },
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return _glassPanel(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _OverviewColors.textGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _OverviewColors.darkGray,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordsSection() {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Summary (${_records.length})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _OverviewColors.darkGray,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(strokeWidth: 3),
                    const SizedBox(height: 10),
                    Text(
                      _progressTotal > 0
                          ? 'Fetching guard $_progressCurrent of $_progressTotal...'
                          : 'Loading guards...',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _OverviewColors.textGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_records.isEmpty)
            _emptyBlock(
              icon: Icons.inbox_outlined,
              title: 'No records found',
              subtitle:
                  'Select date range and click Generate Report to load attendance.',
            )
          else
            ..._records.map(_guardRecordCard),
        ],
      ),
    );
  }

  Widget _guardRecordCard(Map<String, dynamic> record) {
    final String guardId = _asString(record['guardId']).trim();
    final String name = _asString(record['name']).trim();
    final String phone = _asString(record['phone']).trim();
    final String type = _asString(record['type']).trim();
    final String photo = _asString(record['photo']).trim();

    Widget badge(String text, {Color color = _OverviewColors.primaryBlue}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _HoverCard(
        hoverable: true,
        elevation: 0,
        hoverElevation: 3,
        borderRadius: BorderRadius.circular(14),
        borderColor: _OverviewColors.lightGray,
        leftAccentColor: _OverviewColors.primaryBlue,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: photo.isEmpty
                        ? Container(
                            width: 40,
                            height: 40,
                            color: _OverviewColors.surfaceMuted,
                            alignment: Alignment.center,
                            child: Text(
                              name.isEmpty
                                  ? 'G'
                                  : name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: _OverviewColors.primaryBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : Image.network(
                            photo,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: _OverviewColors.surfaceMuted,
                              alignment: Alignment.center,
                              child: Text(
                                name.isEmpty
                                    ? 'G'
                                    : name.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: _OverviewColors.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Unknown Guard' : name,
                          style: const TextStyle(
                            color: _OverviewColors.darkGray,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          phone.isEmpty ? 'N/A' : phone,
                          style: const TextStyle(
                            color: _OverviewColors.textGray,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (type.isNotEmpty)
                              badge(type, color: _OverviewColors.warningStripe),
                            badge(
                              '${_asDouble(record['totalShifts']).toInt()} shifts',
                              color: _OverviewColors.primaryBlue,
                            ),
                            badge(
                              '${_asDouble(record['clientsWorked']).toInt()} clients',
                              color: _OverviewColors.primaryBlue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total Hours',
                        style: TextStyle(
                          fontSize: 11,
                          color: _OverviewColors.textGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatHours(_asDouble(record['totalHours'])),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 14,
                          color: _OverviewColors.darkGray,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: guardId.isEmpty
                      ? null
                      : () => _openGuardDetails(guardId),
                  style: _outlinedButtonStyle(
                    color: _OverviewColors.darkGray,
                    borderColor: _OverviewColors.mediumGray,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: const Text('View'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openGuardDetails(String guardId) {
    Navigator.of(context).pushNamed(
      AppRoutes.attendanceGuard,
      arguments: <String, dynamic>{'guardId': guardId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _OverviewColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: RefreshIndicator(
              onRefresh: _fetchReport,
              child: ListView(
                padding: const EdgeInsets.all(14),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _headerSection(),
                  const SizedBox(height: 16),
                  _filtersSection(),
                  const SizedBox(height: 16),
                  _statsSection(),
                  const SizedBox(height: 16),
                  _recordsSection(),
                ],
              ),
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
          color: _OverviewColors.pureWhite,
          elevation: elevation,
          shadowColor: _OverviewColors.darkGray.withValues(alpha: 0.1),
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
