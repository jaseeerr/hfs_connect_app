import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/tester_data_service.dart';
import '../widget/app_bottom_nav_bar.dart';

class _AttendanceColors {
  const _AttendanceColors._();

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

class _GeoPoint {
  const _GeoPoint({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key, required this.guardId});

  final String guardId;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  static const String _authBox = 'auth_box';
  static const String _fromKey = 'attendanceDateFrom';
  static const String _toKey = 'attendanceDateTo';

  bool _loading = false;
  Map<String, dynamic>? _report;
  DateTime? _startDate;
  DateTime? _endDate;

  Map<String, dynamic>? _selectedShift;
  List<Map<String, dynamic>> _salaryPayments = <Map<String, dynamic>>[];
  double _totalPaid = 0;
  double _pendingSalary = 0;

  @override
  void initState() {
    super.initState();
    _initDatesAndLoad();
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

  DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _dateKey(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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

  String _formatHours(double value) {
    final int h = value.floor();
    final int m = ((value - h) * 60).round();
    if (m == 0) {
      return '$h ${h == 1 ? 'hr' : 'hrs'}';
    }
    if (h == 0) {
      return '$m ${m == 1 ? 'min' : 'mins'}';
    }
    return '$h ${h == 1 ? 'hr' : 'hrs'} $m ${m == 1 ? 'min' : 'mins'}';
  }

  String _formatDate(DateTime value) {
    const List<String> month = <String>[
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
    return '${value.day.toString().padLeft(2, '0')} ${month[value.month - 1]} ${value.year}';
  }

  String _formatDateTime(DateTime value) {
    final String date = _formatDate(value);
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String amPm = value.hour >= 12 ? 'PM' : 'AM';
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$date, $hour:$minute $amPm';
  }

  String _formatCurrency(double value) {
    final String safe = value.isNaN ? '0.00' : value.toStringAsFixed(2);
    return 'AED $safe';
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

  Future<void> _openExternalUrl(String raw) async {
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid location URL'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open location'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _shiftImageUrl(Map<String, dynamic> shift, {required bool checkIn}) {
    final List<String> keys = checkIn
        ? <String>[
            'checkInImageUrl',
            'checkInImage',
            'checkinImageUrl',
            'checkinImage',
            'check_in_image_url',
            'check_in_image',
            'imageUrl',
          ]
        : <String>[
            'checkOutImageUrl',
            'checkOutImage',
            'checkoutImageUrl',
            'checkoutImage',
            'checkOutPhoto',
            'check_out_image_url',
            'check_out_image',
          ];

    for (final String key in keys) {
      final String value = _asString(shift[key]).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }

    final List<String> nestedParents = checkIn
        ? <String>['checkIn', 'checkin', 'check_in']
        : <String>['checkOut', 'checkout', 'check_out'];
    const List<String> nestedKeys = <String>[
      'imageUrl',
      'image',
      'photo',
      'url',
      'selfie',
    ];

    for (final String parent in nestedParents) {
      final Map<String, dynamic> nested = _asMap(shift[parent]);
      if (nested.isEmpty) {
        continue;
      }
      for (final String key in nestedKeys) {
        final String value = _asString(nested[key]).trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return '';
  }

  String _shiftLocationUrl(
    Map<String, dynamic> shift, {
    required bool checkIn,
  }) {
    final List<String> keys = checkIn
        ? <String>[
            'checkInLocation',
            'checkinLocation',
            'check_in_location',
            'checkInLocationUrl',
            'checkinLocationUrl',
          ]
        : <String>[
            'checkOutLocation',
            'checkoutLocation',
            'check_out_location',
            'checkOutLocationUrl',
            'checkoutLocationUrl',
          ];

    for (final String key in keys) {
      final String value = _asString(shift[key]).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }

    final List<String> nestedParents = checkIn
        ? <String>['checkIn', 'checkin', 'check_in']
        : <String>['checkOut', 'checkout', 'check_out'];
    const List<String> nestedKeys = <String>[
      'location',
      'locationUrl',
      'mapsUrl',
      'url',
      'link',
    ];

    for (final String parent in nestedParents) {
      final Map<String, dynamic> nested = _asMap(shift[parent]);
      if (nested.isEmpty) {
        continue;
      }
      for (final String key in nestedKeys) {
        final String value = _asString(nested[key]).trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return '';
  }

  _GeoPoint? _extractCoordinates(String? url) {
    if (url == null || url.trim().isEmpty) {
      return null;
    }

    final String raw = url.trim();
    final Uri? uri = Uri.tryParse(raw);
    final String? q = uri?.queryParameters['q'];
    if (q != null) {
      final List<String> parts = q.split(',');
      if (parts.length == 2) {
        final double? lat = double.tryParse(parts[0]);
        final double? lng = double.tryParse(parts[1]);
        if (lat != null && lng != null) {
          return _GeoPoint(lat: lat, lng: lng);
        }
      }
    }

    final RegExp qMatch = RegExp(r'q=([-\d.]+),([-\d.]+)');
    final Match? qm = qMatch.firstMatch(raw);
    if (qm != null) {
      final double? lat = double.tryParse(qm.group(1) ?? '');
      final double? lng = double.tryParse(qm.group(2) ?? '');
      if (lat != null && lng != null) {
        return _GeoPoint(lat: lat, lng: lng);
      }
    }

    final RegExp atMatch = RegExp(r'@([-\d.]+),([-\d.]+)');
    final Match? am = atMatch.firstMatch(raw);
    if (am != null) {
      final double? lat = double.tryParse(am.group(1) ?? '');
      final double? lng = double.tryParse(am.group(2) ?? '');
      if (lat != null && lng != null) {
        return _GeoPoint(lat: lat, lng: lng);
      }
    }

    return null;
  }

  double? _calculateDistanceKm(String? url1, String? url2) {
    final _GeoPoint? p1 = _extractCoordinates(url1);
    final _GeoPoint? p2 = _extractCoordinates(url2);
    if (p1 == null || p2 == null) {
      return null;
    }

    const double radiusKm = 6371;
    final double dLat = _toRad(p2.lat - p1.lat);
    final double dLng = _toRad(p2.lng - p1.lng);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(p1.lat)) *
            math.cos(_toRad(p2.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radiusKm * c;
  }

  double _toRad(double value) {
    return value * math.pi / 180;
  }

  void _openImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.white,
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Check-in Photo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _AttendanceColors.darkGray,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Unable to load image'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _initDatesAndLoad() async {
    final DateTime now = DateTime.now();
    final DateTime defaultStart = DateTime(now.year, now.month, 1);

    DateTime start = defaultStart;
    DateTime end = _normalizeDate(now);

    if (!Hive.isBoxOpen(_authBox)) {
      await Hive.openBox<dynamic>(_authBox);
    }
    final Box<dynamic> box = Hive.box<dynamic>(_authBox);
    final DateTime? savedStart = DateTime.tryParse(
      _asString(box.get(_fromKey)),
    );
    final DateTime? savedEnd = DateTime.tryParse(_asString(box.get(_toKey)));

    if (savedStart != null && savedEnd != null) {
      start = _normalizeDate(savedStart);
      end = _normalizeDate(savedEnd);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _startDate = start;
      _endDate = end;
    });

    await _fetchReport();
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

  Map<String, dynamic> _processReport(Map<String, dynamic> raw) {
    final Map<String, dynamic> guard = _asMap(raw['guard']);
    final List<Map<String, dynamic>> clients = _asMapList(raw['clients']);

    final List<Map<String, dynamic>> processedClients = clients.map((client) {
      final List<Map<String, dynamic>> shifts = _asMapList(client['shifts'])
          .map((shift) {
            final double hours = _asDouble(shift['hours']);
            final double rounded = _roundToNearestHalfHour(hours);
            return <String, dynamic>{
              ...shift,
              'hours': hours,
              'roundOffHours': rounded,
            };
          })
          .toList();

      final double totalHours = shifts.fold<double>(
        0,
        (sum, s) => sum + _asDouble(s['roundOffHours']),
      );
      final double totalPay = shifts.fold<double>(
        0,
        (sum, s) => sum + _asDouble(s['pay']),
      );

      return <String, dynamic>{
        ...client,
        'shifts': shifts,
        'totalShifts': shifts.length,
        'totalHours': totalHours,
        'totalPay': totalPay,
      };
    }).toList();

    final Map<String, dynamic> insights = _asMap(raw['insights']);
    final double totalHours = processedClients.fold<double>(
      0,
      (sum, c) => sum + _asDouble(c['totalHours']),
    );
    final int totalShifts = processedClients.fold<int>(
      0,
      (sum, c) => sum + (_asDouble(c['totalShifts']).toInt()),
    );

    return <String, dynamic>{
      ...raw,
      'guard': guard,
      'clients': processedClients,
      'insights': <String, dynamic>{
        ...insights,
        'totalHours': totalHours,
        'totalShifts': totalShifts,
      },
    };
  }

  bool _isRouteNotFound(DioException err) {
    final int? code = err.response?.statusCode;
    return code == 404 || code == 405;
  }

  Future<Map<String, dynamic>> _fetchFromApi() async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'startDate': _dateKey(_startDate!),
      'endDate': _dateKey(_endDate!),
    };

    final String guardId = widget.guardId.trim();
    if (guardId.isEmpty) {
      throw Exception('Missing guard id');
    }

    try {
      final Response<dynamic> res = await ApiClient.create(
        opt: 0,
        token: AuthStorage.token,
      ).post('/attendance/guard/$guardId', data: payload);
      return _asMap(res.data);
    } on DioException catch (err) {
      if (!_isRouteNotFound(err)) {
        rethrow;
      }
      final Response<dynamic> res = await ApiClient.create(
        opt: 1,
        token: AuthStorage.token,
      ).post('/attendance/guard/$guardId', data: payload);
      return _asMap(res.data);
    }
  }

  Future<void> _fetchReport() async {
    if (_startDate == null || _endDate == null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _saveDates();

      final Map<String, dynamic> raw = AuthStorage.isTester
          ? await TesterDataService.getAttendanceReportForGuard(
              guardId: widget.guardId,
              startDate: _dateKey(_startDate!),
              endDate: _dateKey(_endDate!),
            )
          : await _fetchFromApi();

      final Map<String, dynamic> processed = _processReport(raw);
      await _fetchSalarySummary(processed);

      if (!mounted) {
        return;
      }
      setState(() {
        _report = processed;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(err)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _AttendanceColors.warning,
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

  Future<void> _fetchSalarySummary(Map<String, dynamic> processedReport) async {
    final double totalPay = _asDouble(
      _asMap(processedReport['insights'])['totalPay'],
    );
    List<Map<String, dynamic>> payments = <Map<String, dynamic>>[];

    if (!AuthStorage.isTester) {
      try {
        final Response<dynamic> res =
            await ApiClient.create(opt: 0, token: AuthStorage.token).get(
              '/salary',
              queryParameters: <String, dynamic>{
                'guardId': widget.guardId,
                'from': _dateKey(_startDate!),
                'to': _dateKey(_endDate!),
              },
            );
        final Map<String, dynamic> body = _asMap(res.data);
        payments = _asMapList(body['payments']);
      } catch (_) {
        payments = <Map<String, dynamic>>[];
      }
    }

    final double totalPaid = payments.fold<double>(
      0,
      (sum, p) => sum + _asDouble(p['amount']),
    );
    final double pending = totalPay - totalPaid;

    if (!mounted) {
      return;
    }
    setState(() {
      _salaryPayments = payments;
      _totalPaid = totalPaid;
      _pendingSalary = pending < 0 ? 0 : pending;
    });
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
      _startDate = _normalizeDate(picked);
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
      _endDate = _normalizeDate(picked);
    });
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
      borderColor: _AttendanceColors.lightGray,
      child: Padding(padding: padding, child: child),
    );
  }

  ButtonStyle _outlinedButtonStyle({
    Color color = _AttendanceColors.primaryBlue,
    Color? borderColor,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: borderColor ?? _AttendanceColors.mediumGray),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
      borderColor: _AttendanceColors.lightGray,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: _AttendanceColors.mediumGray),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _AttendanceColors.darkGray,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _AttendanceColors.textGray,
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

  Widget _tinyBadge({
    required String label,
    Color color = _AttendanceColors.primaryBlue,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerSection() {
    return _glassPanel(
      hoverable: false,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _AttendanceColors.primaryBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guard Attendance Report',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _AttendanceColors.darkGray,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Detailed shift and hours summary',
                  style: TextStyle(
                    color: _AttendanceColors.textGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateFiltersSection() {
    Widget dateField({
      required String label,
      required DateTime? value,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: _AttendanceColors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _AttendanceColors.lightGray),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: _AttendanceColors.primaryBlue,
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
                        color: _AttendanceColors.textGray,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value == null ? '--' : _formatDate(value),
                      style: const TextStyle(
                        fontSize: 13,
                        color: _AttendanceColors.darkGray,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: _AttendanceColors.textGray,
              ),
            ],
          ),
        ),
      );
    }

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Date Range',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _AttendanceColors.darkGray,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool stacked = constraints.maxWidth < 640;
              final Widget actions = Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _fetchReport,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        backgroundColor: _AttendanceColors.primaryBlue,
                        disabledBackgroundColor: _AttendanceColors.mediumGray,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.trending_up_rounded, size: 18),
                      label: const Text('Generate'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Export not yet ready'),
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
                    const SizedBox(height: 12),
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

  Widget _guardProfileSection(Map<String, dynamic> guard) {
    final String name = _asString(guard['name']).trim();
    final String phone = _asString(guard['phone']).trim();
    final String guardId = _asString(guard['guardId']).trim();
    final String type = _asString(guard['type']).trim();
    final String photo = _asString(guard['photo']).trim();

    return _HoverCard(
      hoverable: true,
      elevation: 1.5,
      hoverElevation: 4,
      borderRadius: BorderRadius.circular(16),
      borderColor: _AttendanceColors.lightGray,
      leftAccentColor: _AttendanceColors.primaryBlue,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: photo.isEmpty
                  ? Container(
                      width: 72,
                      height: 72,
                      color: _AttendanceColors.primaryBlue.withValues(
                        alpha: 0.14,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        name.isEmpty ? 'G' : name[0].toUpperCase(),
                        style: const TextStyle(
                          color: _AttendanceColors.primaryBlue,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : Image.network(
                      photo,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: _AttendanceColors.primaryBlue.withValues(
                          alpha: 0.14,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          name.isEmpty ? 'G' : name[0].toUpperCase(),
                          style: const TextStyle(
                            color: _AttendanceColors.primaryBlue,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unknown Guard' : name,
                    style: const TextStyle(
                      color: _AttendanceColors.darkGray,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phone.isEmpty ? 'No phone' : phone,
                    style: const TextStyle(
                      color: _AttendanceColors.textGray,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${guardId.isEmpty ? widget.guardId : guardId}',
                    style: const TextStyle(
                      color: _AttendanceColors.textGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (type.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _tinyBadge(
                      label: type,
                      color: _AttendanceColors.warningStripe,
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _tinyBadge(
                  label: guard['emiratesIdVerified'] == true
                      ? 'Emirates ID: OK'
                      : 'Emirates ID: Pending',
                  color: guard['emiratesIdVerified'] == true
                      ? _AttendanceColors.primaryBlue
                      : _AttendanceColors.warningStripe,
                ),
                const SizedBox(height: 6),
                _tinyBadge(
                  label: guard['passportVerified'] == true
                      ? 'Passport: OK'
                      : 'Passport: Pending',
                  color: guard['passportVerified'] == true
                      ? _AttendanceColors.primaryBlue
                      : _AttendanceColors.warningStripe,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _insightCard({
    required IconData icon,
    required String title,
    required String value,
    required Color tint,
  }) {
    return _glassPanel(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _AttendanceColors.textGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _AttendanceColors.darkGray,
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

  Widget _insightsSection(Map<String, dynamic> insights) {
    final List<Widget> cards = [
      _insightCard(
        icon: Icons.access_time_rounded,
        title: 'Total Hours',
        value: _formatHours(_asDouble(insights['totalHours'])),
        tint: _AttendanceColors.primaryBlue,
      ),
      _insightCard(
        icon: Icons.calendar_month_rounded,
        title: 'Total Shifts',
        value: _asDouble(insights['totalShifts']).toInt().toString(),
        tint: _AttendanceColors.primaryBlue,
      ),
      _insightCard(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Total Earnings',
        value: _formatCurrency(_asDouble(insights['totalPay'])),
        tint: _AttendanceColors.warningStripe,
      ),
      _insightCard(
        icon: Icons.payments_outlined,
        title: 'Total Paid',
        value: _formatCurrency(_totalPaid),
        tint: _AttendanceColors.primaryBlue,
      ),
      _insightCard(
        icon: Icons.pending_actions_outlined,
        title: 'Pending Salary',
        value: _formatCurrency(_pendingSalary),
        tint: _AttendanceColors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 900) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map(
                  (card) => SizedBox(
                    width: (constraints.maxWidth - 20) / 3,
                    child: card,
                  ),
                )
                .toList(),
          );
        }
        return Column(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              cards[i],
              if (i < cards.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _clientCard(Map<String, dynamic> client) {
    final String clientName = _asString(client['clientName']).trim();
    final String address = _asString(client['address']).trim();
    final String locationUrl = _asString(client['locationUrl']).trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _HoverCard(
        hoverable: true,
        elevation: 1.5,
        hoverElevation: 4,
        borderRadius: BorderRadius.circular(16),
        borderColor: _AttendanceColors.lightGray,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName.isEmpty ? 'Unnamed Client' : clientName,
                      style: const TextStyle(
                        color: _AttendanceColors.darkGray,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address.isEmpty ? 'No address provided' : address,
                      style: const TextStyle(
                        color: _AttendanceColors.textGray,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tinyBadge(
                          label:
                              '${_asDouble(client['totalShifts']).toInt()} shifts',
                        ),
                        _tinyBadge(
                          label: _formatHours(_asDouble(client['totalHours'])),
                          color: _AttendanceColors.warningStripe,
                        ),
                      ],
                    ),
                    if (locationUrl.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _openExternalUrl(locationUrl),
                        style: _outlinedButtonStyle(),
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label: const Text('Open Location'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Pay',
                    style: TextStyle(
                      fontSize: 11,
                      color: _AttendanceColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatCurrency(_asDouble(client['totalPay'])),
                    style: const TextStyle(
                      color: _AttendanceColors.darkGray,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openShifts(client),
                    style: _outlinedButtonStyle(
                      color: _AttendanceColors.darkGray,
                      borderColor: _AttendanceColors.mediumGray,
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View Shifts'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSalaryPaymentsModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _AttendanceColors.offWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Salary Payments',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _AttendanceColors.darkGray,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _AttendanceColors.lightGray),
                Expanded(
                  child: _salaryPayments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: _emptyBlock(
                            icon: Icons.receipt_long_outlined,
                            title: 'No payments found',
                            subtitle:
                                'No salary payments exist for this range.',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _salaryPayments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final Map<String, dynamic> payment =
                                _salaryPayments[index];
                            final DateTime? date = DateTime.tryParse(
                              _asString(payment['date']),
                            );
                            final DateTime? from = DateTime.tryParse(
                              _asString(payment['from']),
                            );
                            final DateTime? to = DateTime.tryParse(
                              _asString(payment['to']),
                            );
                            return _glassPanel(
                              hoverable: true,
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatCurrency(
                                      _asDouble(payment['amount']),
                                    ),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: _AttendanceColors.darkGray,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Date: ${date == null ? '-' : _formatDate(date)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _AttendanceColors.textGray,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Period: ${from == null ? '-' : _formatDate(from)} -> ${to == null ? '-' : _formatDate(to)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _AttendanceColors.textGray,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (_asString(
                                    payment['description'],
                                  ).trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Note: ${_asString(payment['description'])}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _AttendanceColors.darkGray,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openShifts(Map<String, dynamic> client) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _AttendanceColors.offWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final List<Map<String, dynamic>> shifts = _asMapList(client['shifts']);
        final String clientLocationUrl = _asString(
          client['locationUrl'],
        ).trim();
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.88,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Shift Details',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: _AttendanceColors.darkGray,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _asString(client['clientName']),
                              style: const TextStyle(
                                color: _AttendanceColors.textGray,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _AttendanceColors.lightGray),
                Expanded(
                  child: shifts.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: _emptyBlock(
                            icon: Icons.event_busy_outlined,
                            title: 'No shifts found',
                            subtitle: 'No shift records exist for this client.',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: shifts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final Map<String, dynamic> shift = shifts[index];
                            final DateTime? start = DateTime.tryParse(
                              _asString(shift['start']),
                            );
                            final DateTime? checkIn = DateTime.tryParse(
                              _asString(shift['checkInAt']),
                            );
                            final DateTime? checkOut = DateTime.tryParse(
                              _asString(shift['checkOutAt']),
                            );
                            final String checkInLocation = _shiftLocationUrl(
                              shift,
                              checkIn: true,
                            );
                            final String checkOutLocation = _shiftLocationUrl(
                              shift,
                              checkIn: false,
                            );
                            final String checkInImage = _shiftImageUrl(
                              shift,
                              checkIn: true,
                            );
                            final String checkOutImage = _shiftImageUrl(
                              shift,
                              checkIn: false,
                            );
                            final double? checkInDistanceKm =
                                _calculateDistanceKm(
                                  clientLocationUrl,
                                  checkInLocation,
                                );
                            final double? checkOutDistanceKm =
                                _calculateDistanceKm(
                                  clientLocationUrl,
                                  checkOutLocation,
                                );
                            final bool checkInWarning =
                                checkInDistanceKm != null &&
                                checkInDistanceKm > 0.8;
                            final bool checkOutWarning =
                                checkOutDistanceKm != null &&
                                checkOutDistanceKm > 0.8;
                            return _HoverCard(
                              hoverable: true,
                              elevation: 1.5,
                              hoverElevation: 4,
                              borderRadius: BorderRadius.circular(14),
                              borderColor: _AttendanceColors.lightGray,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedShift = shift;
                                  });
                                  _openShiftDetail();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        start == null
                                            ? '--'
                                            : _formatDate(start),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: _AttendanceColors.darkGray,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Check-in: ${checkIn == null ? '--' : _formatDateTime(checkIn)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _AttendanceColors.textGray,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'Check-out: ${checkOut == null ? '--' : _formatDateTime(checkOut)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _AttendanceColors.textGray,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Rounded hours: ${_formatHours(_asDouble(shift['roundOffHours']))}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: _AttendanceColors.darkGray,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (checkInDistanceKm != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Check-in: ${checkInDistanceKm.toStringAsFixed(1)} km away from client location',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: _AttendanceColors.textGray,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      if (checkOutDistanceKm != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Check-out: ${checkOutDistanceKm.toStringAsFixed(1)} km away from client location',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: _AttendanceColors.textGray,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      if (checkInWarning ||
                                          checkOutWarning) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: _AttendanceColors.warning
                                                .withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: _AttendanceColors
                                                  .warningStripe
                                                  .withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Text(
                                            checkInWarning && checkOutWarning
                                                ? 'Warning: both check-in and check-out are more than 0.8 km from client location.'
                                                : checkInWarning
                                                ? 'Warning: check-in is more than 0.8 km from client location.'
                                                : 'Warning: check-out is more than 0.8 km from client location.',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: _AttendanceColors.warning,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (checkInLocation.isNotEmpty)
                                            OutlinedButton.icon(
                                              onPressed: () => _openExternalUrl(
                                                checkInLocation,
                                              ),
                                              style: _outlinedButtonStyle(),
                                              icon: const Icon(
                                                Icons.place_outlined,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Check-in Location',
                                              ),
                                            ),
                                          if (checkOutLocation.isNotEmpty)
                                            OutlinedButton.icon(
                                              onPressed: () => _openExternalUrl(
                                                checkOutLocation,
                                              ),
                                              style: _outlinedButtonStyle(),
                                              icon: const Icon(
                                                Icons.location_on_outlined,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Check-out Location',
                                              ),
                                            ),
                                          if (checkInImage.isNotEmpty)
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _openImagePreview(
                                                    checkInImage,
                                                  ),
                                              style: _outlinedButtonStyle(),
                                              icon: const Icon(
                                                Icons.image_outlined,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Check-in Photo',
                                              ),
                                            ),
                                          if (checkOutImage.isNotEmpty)
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _openImagePreview(
                                                    checkOutImage,
                                                  ),
                                              style: _outlinedButtonStyle(),
                                              icon: const Icon(
                                                Icons.image_search_outlined,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Check-out Photo',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openShiftDetail() {
    final Map<String, dynamic>? shift = _selectedShift;
    if (shift == null) {
      return;
    }

    final DateTime? checkIn = DateTime.tryParse(_asString(shift['checkInAt']));
    final DateTime? checkOut = DateTime.tryParse(
      _asString(shift['checkOutAt']),
    );
    final String checkInLocation = _shiftLocationUrl(shift, checkIn: true);
    final String checkOutLocation = _shiftLocationUrl(shift, checkIn: false);
    final String checkInImage = _shiftImageUrl(shift, checkIn: true);
    final String checkOutImage = _shiftImageUrl(shift, checkIn: false);

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Shift Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _AttendanceColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: _AttendanceColors.lightGray),
                    const SizedBox(height: 12),
                    Text(
                      'Check-in: ${checkIn == null ? '--' : _formatDateTime(checkIn)}',
                      style: const TextStyle(
                        color: _AttendanceColors.textGray,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check-out: ${checkOut == null ? '--' : _formatDateTime(checkOut)}',
                      style: const TextStyle(
                        color: _AttendanceColors.textGray,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Actual: ${_formatHours(_asDouble(shift['hours']))}',
                      style: const TextStyle(
                        color: _AttendanceColors.darkGray,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Rounded: ${_formatHours(_asDouble(shift['roundOffHours']))}',
                      style: const TextStyle(
                        color: _AttendanceColors.darkGray,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pay/hr: ${_formatCurrency(_asDouble(shift['payPerHour']))}',
                      style: const TextStyle(
                        color: _AttendanceColors.textGray,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Total Pay: ${_formatCurrency(_asDouble(shift['pay']))}',
                      style: const TextStyle(
                        color: _AttendanceColors.darkGray,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (checkInLocation.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _openExternalUrl(checkInLocation),
                            style: _outlinedButtonStyle(),
                            icon: const Icon(Icons.place_outlined, size: 16),
                            label: const Text('Check-in Location'),
                          ),
                        if (checkOutLocation.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _openExternalUrl(checkOutLocation),
                            style: _outlinedButtonStyle(),
                            icon: const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                            ),
                            label: const Text('Check-out Location'),
                          ),
                        if (checkInImage.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _openImagePreview(checkInImage),
                            style: _outlinedButtonStyle(),
                            icon: const Icon(Icons.image_outlined, size: 16),
                            label: const Text('Check-in Photo'),
                          ),
                        if (checkOutImage.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _openImagePreview(checkOutImage),
                            style: _outlinedButtonStyle(),
                            icon: const Icon(
                              Icons.image_search_outlined,
                              size: 16,
                            ),
                            label: const Text('Check-out Photo'),
                          ),
                      ],
                    ),
                    if (_asString(shift['note']).trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Note: ${_asString(shift['note'])}',
                        style: const TextStyle(
                          color: _AttendanceColors.textGray,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: _outlinedButtonStyle(
                          color: _AttendanceColors.darkGray,
                          borderColor: _AttendanceColors.mediumGray,
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? report = _report;
    final List<Map<String, dynamic>> clients = _asMapList(report?['clients']);
    final Map<String, dynamic> insights = _asMap(report?['insights']);
    final Map<String, dynamic> guard = _asMap(report?['guard']);

    return Scaffold(
      backgroundColor: _AttendanceColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: RefreshIndicator(
              onRefresh: _fetchReport,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _headerSection(),
                  const SizedBox(height: 16),
                  _dateFiltersSection(),
                  const SizedBox(height: 16),
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            CircularProgressIndicator(strokeWidth: 3),
                            SizedBox(height: 10),
                            Text(
                              'Loading attendance report...',
                              style: TextStyle(
                                color: _AttendanceColors.textGray,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (report == null)
                    _emptyBlock(
                      icon: Icons.inbox_outlined,
                      title: 'No report generated yet',
                      subtitle:
                          'Select a date range and generate the guard report.',
                    )
                  else ...[
                    _guardProfileSection(guard),
                    const SizedBox(height: 16),
                    _insightsSection(insights),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _openSalaryPaymentsModal,
                        style: _outlinedButtonStyle(),
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        label: const Text('See Payment Details'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Client Assignments',
                      style: TextStyle(
                        color: _AttendanceColors.darkGray,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (clients.isEmpty)
                      _emptyBlock(
                        icon: Icons.business_outlined,
                        title: 'No client assignments',
                        subtitle: 'No client shifts available in this range.',
                      )
                    else
                      ...clients.map(_clientCard),
                  ],
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
          color: _AttendanceColors.pureWhite,
          elevation: elevation,
          shadowColor: _AttendanceColors.darkGray.withValues(alpha: 0.1),
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
