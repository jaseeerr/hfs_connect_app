import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/roster_pdf_service.dart';
import '../services/tester_data_service.dart';
import '../widget/app_bottom_nav_bar.dart';

class AppColors {
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF8FAFC);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color dangerRed = Color(0xFFDC2626);
}

class _DeleteRosterCountdownDialog extends StatefulWidget {
  const _DeleteRosterCountdownDialog();

  @override
  State<_DeleteRosterCountdownDialog> createState() =>
      _DeleteRosterCountdownDialogState();
}

class _DeleteRosterCountdownDialogState
    extends State<_DeleteRosterCountdownDialog> {
  static const int _initialCountdownMs = 3500;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Delete Roster'),
      content: const Text(
        'Are you sure you want to delete this roster? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canDelete ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
          ),
          child: Text(_canDelete ? 'Delete' : _countdownLabel),
        ),
      ],
    );
  }
}

class _RosterAssignment {
  _RosterAssignment({
    required this.id,
    required this.guardId,
    required this.checkInTime,
  });

  final String id;
  final String guardId;
  final String checkInTime;

  _RosterAssignment copyWith({String? checkInTime}) {
    return _RosterAssignment(
      id: id,
      guardId: guardId,
      checkInTime: checkInTime ?? this.checkInTime,
    );
  }
}

class _LoadedRosterData {
  _LoadedRosterData({
    required this.startDate,
    required this.endDate,
    required this.dateRange,
    required this.roster,
  });

  final DateTime startDate;
  final DateTime endDate;
  final List<DateTime> dateRange;
  final Map<String, Map<String, List<_RosterAssignment>>> roster;
}

class NewRosterPage extends StatefulWidget {
  const NewRosterPage({super.key, this.rosterId});

  final String? rosterId;

  @override
  State<NewRosterPage> createState() => _NewRosterPageState();
}

class _NewRosterPageState extends State<NewRosterPage>
    with TickerProviderStateMixin {
  final List<Map<String, dynamic>> _clients = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _guards = <Map<String, dynamic>>[];

  final Map<String, Map<String, List<_RosterAssignment>>> _roster =
      <String, Map<String, List<_RosterAssignment>>>{};
  final Map<String, Map<String, List<_RosterAssignment>>> _originalRoster =
      <String, Map<String, List<_RosterAssignment>>>{};

  bool _loadingSetup = true;
  bool _saving = false;
  bool _downloadingPdf = false;

  int _currentStep = 1;

  DateTime? _startDate;
  DateTime? _endDate;
  List<DateTime> _dateRange = <DateTime>[];

  String? _selectedClientId;
  String _clientSearch = '';
  String _originalStartDateKey = '';
  String _originalEndDateKey = '';
  int _assignmentSeed = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  Dio _api() => ApiClient.create(opt: 0, token: AuthStorage.token);

  String get _editRosterId => _asString(widget.rosterId).trim();

  bool get _isEditMode => _editRosterId.isNotEmpty;

  String _newAssignmentId() {
    _assignmentSeed += 1;
    return 'asg_${DateTime.now().microsecondsSinceEpoch}_$_assignmentSeed';
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    _fetchSetup();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
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

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) {
      return value;
    }
    return <dynamic>[];
  }

  DateTime? _asDate(dynamic value) {
    final String raw = _asString(value).trim();
    if (raw.isEmpty) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _extractId(dynamic value) {
    if (value is Map) {
      return _asString(_asMap(value)['_id']).trim();
    }
    return _asString(value).trim();
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

  bool _isRouteNotFound(DioException err) {
    final int? statusCode = err.response?.statusCode;
    return statusCode == 404 || statusCode == 405;
  }

  List<DateTime> _buildDateRange(DateTime start, DateTime end) {
    final DateTime normalizedStart = DateTime(
      start.year,
      start.month,
      start.day,
    );
    final DateTime normalizedEnd = DateTime(end.year, end.month, end.day);
    final List<DateTime> days = <DateTime>[];

    DateTime current = normalizedStart;
    while (!current.isAfter(normalizedEnd)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }

    return days;
  }

  String _normalizeDateKey(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final DateTime? parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return _dateKey(parsed);
    }

    if (trimmed.length >= 10) {
      return trimmed.substring(0, 10);
    }
    return trimmed;
  }

  Map<String, Map<String, List<_RosterAssignment>>> _cloneRoster(
    Map<String, Map<String, List<_RosterAssignment>>> source,
  ) {
    final Map<String, Map<String, List<_RosterAssignment>>> copy =
        <String, Map<String, List<_RosterAssignment>>>{};

    for (final MapEntry<String, Map<String, List<_RosterAssignment>>>
        clientEntry
        in source.entries) {
      final Map<String, List<_RosterAssignment>> copiedDates =
          <String, List<_RosterAssignment>>{};
      for (final MapEntry<String, List<_RosterAssignment>> dateEntry
          in clientEntry.value.entries) {
        copiedDates[dateEntry.key] = dateEntry.value
            .map(
              (a) => _RosterAssignment(
                id: a.id,
                guardId: a.guardId,
                checkInTime: a.checkInTime,
              ),
            )
            .toList();
      }
      copy[clientEntry.key] = copiedDates;
    }

    return copy;
  }

  String _rosterSignature(
    Map<String, Map<String, List<_RosterAssignment>>> source, {
    required String startDateKey,
    required String endDateKey,
  }) {
    final Map<String, dynamic> serializedRoster = <String, dynamic>{};
    final List<String> clientIds = source.keys.toList()..sort();

    for (final String clientId in clientIds) {
      final Map<String, List<_RosterAssignment>> clientRoster =
          source[clientId] ?? <String, List<_RosterAssignment>>{};
      final List<String> dates = clientRoster.keys.toList()..sort();
      final Map<String, dynamic> serializedDates = <String, dynamic>{};

      for (final String dateKey in dates) {
        final List<_RosterAssignment> assignments =
            List<_RosterAssignment>.from(
              clientRoster[dateKey] ?? <_RosterAssignment>[],
            )..sort((a, b) {
              final int guardCompare = a.guardId.compareTo(b.guardId);
              if (guardCompare != 0) {
                return guardCompare;
              }
              return a.checkInTime.compareTo(b.checkInTime);
            });

        serializedDates[dateKey] = assignments
            .map(
              (a) => <String, String>{
                'guardId': a.guardId,
                'checkInTime': a.checkInTime,
              },
            )
            .toList();
      }

      serializedRoster[clientId] = serializedDates;
    }

    return jsonEncode(<String, dynamic>{
      'startDate': startDateKey,
      'endDate': endDateKey,
      'roster': serializedRoster,
    });
  }

  void _captureOriginalSnapshot() {
    if (_startDate == null || _endDate == null) {
      _originalStartDateKey = '';
      _originalEndDateKey = '';
      _originalRoster.clear();
      return;
    }

    _originalStartDateKey = _dateKey(_startDate!);
    _originalEndDateKey = _dateKey(_endDate!);
    _originalRoster
      ..clear()
      ..addAll(_cloneRoster(_roster));
  }

  bool get _hasChanges {
    if (!_isEditMode) {
      return false;
    }
    if (_startDate == null || _endDate == null) {
      return true;
    }

    final String currentSignature = _rosterSignature(
      _roster,
      startDateKey: _dateKey(_startDate!),
      endDateKey: _dateKey(_endDate!),
    );
    final String originalSignature = _rosterSignature(
      _originalRoster,
      startDateKey: _originalStartDateKey,
      endDateKey: _originalEndDateKey,
    );

    return currentSignature != originalSignature;
  }

  Future<_LoadedRosterData> _fetchRosterForEdit(String rosterId) async {
    final Map<String, dynamic> rosterMap;
    if (AuthStorage.isTester) {
      rosterMap = _asMap(await TesterDataService.getRosterById(rosterId));
    } else {
      final Response<dynamic> rosterRes = await _api().get(
        '/getRoster/$rosterId',
      );
      final Map<String, dynamic> body = _asMap(rosterRes.data);
      rosterMap = _asMap(body['roster']);
    }

    final DateTime? startDate = _asDate(rosterMap['startDate']);
    final DateTime? endDate = _asDate(rosterMap['endDate']);
    if (startDate == null || endDate == null) {
      throw Exception('Roster is missing valid start/end dates');
    }

    final List<DateTime> days = _buildDateRange(startDate, endDate);

    final Map<String, Map<String, List<_RosterAssignment>>> transformedRoster =
        <String, Map<String, List<_RosterAssignment>>>{};
    final List<dynamic> rosterClients = _asList(rosterMap['clients']);

    for (final dynamic client in rosterClients) {
      final Map<String, dynamic> clientMap = _asMap(client);
      final String clientId = _extractId(clientMap['clientId']);
      if (clientId.isEmpty) {
        continue;
      }

      final Map<String, List<_RosterAssignment>> clientRoster =
          <String, List<_RosterAssignment>>{};
      final List<dynamic> dateEntries = _asList(clientMap['dates']);

      for (final dynamic dateEntry in dateEntries) {
        final Map<String, dynamic> dateMap = _asMap(dateEntry);
        final String dateKey = _normalizeDateKey(_asString(dateMap['date']));
        if (dateKey.isEmpty) {
          continue;
        }

        final List<Map<String, dynamic>> assignmentsMap = _asMapList(
          dateMap['assignments'],
        );
        final List<_RosterAssignment> assignments = assignmentsMap
            .map((assignment) {
              final String guardId = _extractId(assignment['guardId']);
              return _RosterAssignment(
                id: _newAssignmentId(),
                guardId: guardId,
                checkInTime: _asString(assignment['checkInTime']).trim().isEmpty
                    ? '09:00'
                    : _asString(assignment['checkInTime']).trim(),
              );
            })
            .where((assignment) => assignment.guardId.isNotEmpty)
            .toList();

        clientRoster[dateKey] = assignments;
      }

      transformedRoster[clientId] = clientRoster;
    }

    return _LoadedRosterData(
      startDate: startDate,
      endDate: endDate,
      dateRange: days,
      roster: transformedRoster,
    );
  }

  Future<void> _fetchSetup() async {
    if (mounted) {
      setState(() {
        _loadingSetup = true;
      });
    }

    try {
      final Map<String, dynamic> body = AuthStorage.isTester
          ? await TesterDataService.getDateForRosterData()
          : _asMap((await _api().get('/getDateForRoster')).data);

      final List<Map<String, dynamic>> clients = _asMapList(body['clients']);
      final List<Map<String, dynamic>> guards = _asMapList(body['guards']);
      _LoadedRosterData? loadedRosterData;

      if (_isEditMode) {
        try {
          loadedRosterData = await _fetchRosterForEdit(_editRosterId);
        } catch (err) {
          _showSnack(_errorMessage(err), isError: true);
        }
      }

      if (mounted) {
        setState(() {
          _clients
            ..clear()
            ..addAll(clients);
          _guards
            ..clear()
            ..addAll(guards);

          if (loadedRosterData != null) {
            _startDate = loadedRosterData.startDate;
            _endDate = loadedRosterData.endDate;
            _dateRange = loadedRosterData.dateRange;
            _currentStep = 2;

            _roster
              ..clear()
              ..addAll(_cloneRoster(loadedRosterData.roster));

            String? selectedClient;
            for (final Map<String, dynamic> client in clients) {
              final String clientId = _asString(client['_id']);
              final bool hasAssignments =
                  _roster[clientId]?.values.any((items) => items.isNotEmpty) ??
                  false;
              if (hasAssignments) {
                selectedClient = clientId;
                break;
              }
            }
            _selectedClientId =
                selectedClient ??
                (clients.isNotEmpty ? _asString(clients.first['_id']) : null);
            _captureOriginalSnapshot();
          } else {
            _selectedClientId = clients.isNotEmpty
                ? _asString(clients.first['_id'])
                : null;
          }
        });
      }
    } catch (err) {
      _showSnack(_errorMessage(err), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loadingSetup = false;
        });
      }
    }
  }

  Future<void> _pickStartDate() async {
    final DateTime now = DateTime.now();
    final DateTime initial = _startDate ?? now;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryBlue,
              onPrimary: AppColors.pureWhite,
              surface: AppColors.pureWhite,
              onSurface: AppColors.darkGray,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _startDate = picked;
      if (_endDate != null && _endDate!.isBefore(picked)) {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final DateTime now = DateTime.now();
    final DateTime min = _startDate ?? DateTime(now.year - 2);
    final DateTime initial = _endDate ?? _startDate ?? now;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(min) ? min : initial,
      firstDate: min,
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryBlue,
              onPrimary: AppColors.pureWhite,
              surface: AppColors.pureWhite,
              onSurface: AppColors.darkGray,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _endDate = picked;
    });
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
    if (month < 1 || month > 12) {
      return 'Jan';
    }
    return names[month - 1];
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Select date';
    }
    return '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';
  }

  String _dateKey(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _weekday(DateTime date) {
    const List<String> names = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return names[date.weekday - 1];
  }

  Map<String, Map<String, List<_RosterAssignment>>> _trimRosterToDateRange(
    Map<String, Map<String, List<_RosterAssignment>>> source,
    List<DateTime> days,
  ) {
    final Set<String> validDateKeys = days.map(_dateKey).toSet();
    final Map<String, Map<String, List<_RosterAssignment>>> trimmed =
        <String, Map<String, List<_RosterAssignment>>>{};

    for (final MapEntry<String, Map<String, List<_RosterAssignment>>>
        clientEntry
        in source.entries) {
      final Map<String, List<_RosterAssignment>> dates =
          <String, List<_RosterAssignment>>{};
      for (final MapEntry<String, List<_RosterAssignment>> dateEntry
          in clientEntry.value.entries) {
        if (!validDateKeys.contains(dateEntry.key)) {
          continue;
        }
        dates[dateEntry.key] = dateEntry.value
            .map(
              (a) => _RosterAssignment(
                id: a.id,
                guardId: a.guardId,
                checkInTime: a.checkInTime,
              ),
            )
            .toList();
      }
      trimmed[clientEntry.key] = dates;
    }

    return trimmed;
  }

  void _generateDateRange() {
    if (_startDate == null || _endDate == null) {
      return;
    }

    final List<DateTime> days = _buildDateRange(_startDate!, _endDate!);
    final Map<String, Map<String, List<_RosterAssignment>>> trimmedRoster =
        _trimRosterToDateRange(_roster, days);

    setState(() {
      _dateRange = days;
      _roster
        ..clear()
        ..addAll(trimmedRoster);
      _currentStep = 2;
      if (_clients.isNotEmpty &&
          (_selectedClientId == null || _selectedClientId!.isEmpty)) {
        _selectedClientId = _asString(_clients.first['_id']);
      }
    });
  }

  String _guardName(String guardId) {
    for (final Map<String, dynamic> guard in _guards) {
      if (_asString(guard['_id']) == guardId) {
        final String name = _asString(guard['name']);
        return name.isNotEmpty ? name : 'Unknown';
      }
    }
    return 'Unknown';
  }

  String _clientName(String clientId) {
    for (final Map<String, dynamic> client in _clients) {
      if (_asString(client['_id']) == clientId) {
        final String name = _asString(client['name']);
        return name.isNotEmpty ? name : 'Unknown';
      }
    }
    return 'Unknown';
  }

  List<_RosterAssignment> _assignmentsFor(String clientId, String dateKey) {
    return _roster[clientId]?[dateKey] ?? <_RosterAssignment>[];
  }

  void _addGuard({
    required String clientId,
    required String date,
    required String guardId,
    required String checkInTime,
  }) {
    setState(() {
      final Map<String, List<_RosterAssignment>> clientRoster =
          Map<String, List<_RosterAssignment>>.from(
            _roster[clientId] ?? <String, List<_RosterAssignment>>{},
          );

      final List<_RosterAssignment> dateRoster = List<_RosterAssignment>.from(
        clientRoster[date] ?? <_RosterAssignment>[],
      );

      dateRoster.add(
        _RosterAssignment(
          id: _newAssignmentId(),
          guardId: guardId,
          checkInTime: checkInTime,
        ),
      );

      clientRoster[date] = dateRoster;
      _roster[clientId] = clientRoster;
    });
  }

  void _updateGuardTime({
    required String clientId,
    required String date,
    required String assignmentId,
    required String checkInTime,
  }) {
    setState(() {
      final Map<String, List<_RosterAssignment>> clientRoster =
          Map<String, List<_RosterAssignment>>.from(
            _roster[clientId] ?? <String, List<_RosterAssignment>>{},
          );

      final List<_RosterAssignment> dateRoster = List<_RosterAssignment>.from(
        clientRoster[date] ?? <_RosterAssignment>[],
      );

      final List<_RosterAssignment> updated = dateRoster
          .map(
            (assignment) => assignment.id == assignmentId
                ? assignment.copyWith(checkInTime: checkInTime)
                : assignment,
          )
          .toList();

      clientRoster[date] = updated;
      _roster[clientId] = clientRoster;
    });
  }

  void _removeGuard({
    required String clientId,
    required String date,
    required String assignmentId,
  }) {
    setState(() {
      final Map<String, List<_RosterAssignment>> clientRoster =
          Map<String, List<_RosterAssignment>>.from(
            _roster[clientId] ?? <String, List<_RosterAssignment>>{},
          );

      final List<_RosterAssignment> dateRoster = List<_RosterAssignment>.from(
        clientRoster[date] ?? <_RosterAssignment>[],
      );

      dateRoster.removeWhere((a) => a.id == assignmentId);
      clientRoster[date] = dateRoster;
      _roster[clientId] = clientRoster;
    });
  }

  int _totalAssignments() {
    int count = 0;
    for (final Map<String, List<_RosterAssignment>> clientRoster
        in _roster.values) {
      for (final List<_RosterAssignment> dateRoster in clientRoster.values) {
        count += dateRoster.length;
      }
    }
    return count;
  }

  bool _hasAssignmentsForClient(String clientId) {
    final Map<String, List<_RosterAssignment>> clientRoster =
        _roster[clientId] ?? <String, List<_RosterAssignment>>{};
    return clientRoster.values.any((dateRoster) => dateRoster.isNotEmpty);
  }

  List<Map<String, dynamic>> get _clientsSortedBySearch {
    final String query = _clientSearch.trim().toLowerCase();
    if (query.isEmpty) {
      return List<Map<String, dynamic>>.from(_clients);
    }

    final List<Map<String, dynamic>> startsWith = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> contains = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> others = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> client in _clients) {
      final String name = _asString(client['name']).toLowerCase();
      if (name.startsWith(query)) {
        startsWith.add(client);
      } else if (name.contains(query)) {
        contains.add(client);
      } else {
        others.add(client);
      }
    }

    return <Map<String, dynamic>>[...startsWith, ...contains, ...others];
  }

  List<Map<String, dynamic>> get _clientsWithAssignments {
    return _clients
        .where((client) => _hasAssignmentsForClient(_asString(client['_id'])))
        .toList();
  }

  Future<void> _saveRoster() async {
    if (_startDate == null || _endDate == null) {
      _showSnack('Please select start and end dates', isError: true);
      return;
    }

    if (_totalAssignments() == 0) {
      _showSnack('Please add at least one assignment', isError: true);
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final List<Map<String, dynamic>> clients = <Map<String, dynamic>>[];

      for (final String clientId in _roster.keys) {
        final Map<String, List<_RosterAssignment>> clientRoster =
            _roster[clientId] ?? <String, List<_RosterAssignment>>{};
        if (clientRoster.isEmpty) {
          continue;
        }

        final List<Map<String, dynamic>> dates = <Map<String, dynamic>>[];
        for (final String dateKey in clientRoster.keys) {
          final List<_RosterAssignment> assignments =
              clientRoster[dateKey] ?? <_RosterAssignment>[];
          if (assignments.isEmpty) {
            continue;
          }

          dates.add(<String, dynamic>{
            'date': dateKey,
            'assignments': assignments
                .map(
                  (a) => <String, String>{
                    'guardId': a.guardId,
                    'checkInTime': a.checkInTime,
                  },
                )
                .toList(),
          });
        }

        if (dates.isNotEmpty) {
          clients.add(<String, dynamic>{'clientId': clientId, 'dates': dates});
        }
      }

      final Map<String, dynamic> payload = <String, dynamic>{
        'startDate': _dateKey(_startDate!),
        'endDate': _dateKey(_endDate!),
        'clients': clients,
      };

      if (_isEditMode) {
        if (AuthStorage.isTester) {
          await TesterDataService.upsertRoster(
            payload: payload,
            rosterId: _editRosterId,
          );
        } else {
          try {
            await _api().patch('/updateRoster/$_editRosterId', data: payload);
          } on DioException catch (err) {
            if (!_isRouteNotFound(err)) {
              rethrow;
            }
            await _api().put('/editRoster/$_editRosterId', data: payload);
          }
        }
        _showSnack('Roster updated successfully');
        _captureOriginalSnapshot();
      } else {
        if (AuthStorage.isTester) {
          await TesterDataService.upsertRoster(payload: payload);
        } else {
          try {
            await _api().post('/addRoster', data: payload);
          } on DioException catch (err) {
            if (!_isRouteNotFound(err)) {
              rethrow;
            }
            await _api().post('/createRoster', data: payload);
          }
        }
        _showSnack('Roster created successfully');
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (err) {
      _showSnack(_errorMessage(err), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _downloadPdf() async {
    setState(() {
      _downloadingPdf = true;
    });

    try {
      final List<Map<String, dynamic>> clientsData = <Map<String, dynamic>>[];

      for (final Map<String, dynamic> client in _clientsWithAssignments) {
        final String clientId = _asString(client['_id']);
        final String clientName = _asString(client['name']);
        final Map<String, List<_RosterAssignment>> clientRoster =
            _roster[clientId] ?? <String, List<_RosterAssignment>>{};

        final List<Map<String, dynamic>> dates = <Map<String, dynamic>>[];
        for (final String dateKey in clientRoster.keys) {
          final List<_RosterAssignment> assignments =
              clientRoster[dateKey] ?? <_RosterAssignment>[];
          if (assignments.isEmpty) {
            continue;
          }

          dates.add(<String, dynamic>{
            'date': dateKey,
            'guards': assignments
                .map(
                  (a) => <String, String>{
                    'name': _guardName(a.guardId),
                    'checkInTime': a.checkInTime,
                  },
                )
                .toList(),
          });
        }

        if (dates.isNotEmpty) {
          clientsData.add(<String, dynamic>{
            'clientName': clientName,
            'dates': dates,
          });
        }
      }

      final List<RosterPdfClient> pdfClients = clientsData.map((clientData) {
        final String clientName = _asString(clientData['clientName']);
        final List<Map<String, dynamic>> dateItems = _asMapList(
          clientData['dates'],
        );
        final Map<String, List<RosterPdfAssignment>> assignmentsByDate =
            <String, List<RosterPdfAssignment>>{};

        for (final Map<String, dynamic> dateItem in dateItems) {
          final String dateKey = _asString(dateItem['date']);
          if (dateKey.isEmpty) {
            continue;
          }

          final List<Map<String, dynamic>> guardItems = _asMapList(
            dateItem['guards'],
          );
          assignmentsByDate[dateKey] = guardItems
              .map(
                (guard) => RosterPdfAssignment(
                  guardName: _asString(guard['name']),
                  checkInTime: _asString(guard['checkInTime']),
                ),
              )
              .toList();
        }

        return RosterPdfClient(
          name: clientName,
          assignmentsByDate: assignmentsByDate,
        );
      }).toList();

      await RosterPdfService.shareRosterPdf(
        startDate: _startDate!,
        endDate: _endDate!,
        dateRange: _dateRange,
        clients: pdfClients,
        logoAssetPath: 'assets/LogoNoBg.png',
        logoWidth: 60,
        filename:
            'roster_${_dateKey(_startDate!)}_to_${_dateKey(_endDate!)}.pdf',
      );

      _showSnack('PDF downloaded successfully');
    } catch (err) {
      _showSnack(_errorMessage(err), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _downloadingPdf = false;
        });
      }
    }
  }

  Future<void> _deleteRoster() async {
    if (!_isEditMode) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteRosterCountdownDialog(),
    );

    if (confirmed != true) {
      return;
    }

    try {
      if (AuthStorage.isTester) {
        await TesterDataService.deleteRoster(_editRosterId);
      } else {
        await _api().delete('/deleteRoster/$_editRosterId');
      }
      _showSnack('Roster deleted successfully');
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (err) {
      _showSnack(_errorMessage(err), isError: true);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) {
      return true;
    }

    final bool? shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => _buildDialog(
        title: 'Unsaved Changes',
        message: 'You have unsaved changes. Are you sure you want to leave?',
        confirmText: 'Leave',
        isDestructive: true,
      ),
    );

    return shouldPop ?? false;
  }

  Widget _buildDialog({
    required String title,
    required String message,
    required String confirmText,
    bool isDestructive = false,
  }) {
    final Color confirmColor = isDestructive
        ? AppColors.dangerRed
        : AppColors.primaryBlue;

    return AlertDialog(
      backgroundColor: AppColors.pureWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.darkGray,
        ),
      ),
      content: Text(
        message,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textGray,
          height: 1.4,
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkGray,
            backgroundColor: AppColors.pureWhite,
            minimumSize: const Size(88, 42),
            side: const BorderSide(color: AppColors.mediumGray, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: AppColors.pureWhite,
            minimumSize: const Size(88, 42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(confirmText),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 600;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        appBar: _buildAppBar(context),
        body: _loadingSetup
            ? _buildLoadingView()
            : FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  decoration: _buildBackgroundDecoration(),
                  child: SafeArea(
                    child: Column(
                      children: [
                        if (!isSmallScreen) _buildStepIndicator(),
                        Expanded(
                          child: _currentStep == 1
                              ? _buildDateSelectionStep(isSmallScreen)
                              : _buildRosterManagementStep(isSmallScreen),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        bottomNavigationBar: const AppBottomNavBar(currentIndex: 1),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.pureWhite,
      surfaceTintColor: AppColors.pureWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: AppColors.lightGray),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.darkGray),
        onPressed: () async {
          if (await _onWillPop()) {
            if (mounted) {
              Navigator.of(context).pop();
            }
          }
        },
      ),
      title: Text(
        _isEditMode ? 'Edit Roster' : 'Create Roster',
        style: const TextStyle(
          color: AppColors.darkGray,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        if (_currentStep == 2 && _totalAssignments() > 0)
          _buildAppBarAction(
            icon: Icons.picture_as_pdf_rounded,
            onTap: _downloadingPdf ? null : _downloadPdf,
            isLoading: _downloadingPdf,
          ),
        if (_isEditMode && _currentStep == 2)
          _buildAppBarAction(
            icon: Icons.delete_outline_rounded,
            onTap: _deleteRoster,
            color: AppColors.dangerRed,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildAppBarAction({
    required IconData icon,
    required VoidCallback? onTap,
    bool isLoading = false,
    Color? color,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryBlue,
                ),
              ),
            )
          : Icon(icon, color: color ?? AppColors.primaryBlue, size: 21),
    );
  }

  BoxDecoration _buildBackgroundDecoration() {
    return const BoxDecoration(color: AppColors.offWhite);
  }

  Widget _buildLoadingView() {
    return Container(
      decoration: _buildBackgroundDecoration(),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryBlue,
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Loading roster data...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textGray,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: _buildCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            _buildStepItem(
              stepNumber: 1,
              title: 'Select Dates',
              isActive: _currentStep == 1,
              isCompleted: _currentStep > 1,
            ),
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: _currentStep > 1
                    ? AppColors.primaryBlue
                    : AppColors.mediumGray,
              ),
            ),
            _buildStepItem(
              stepNumber: 2,
              title: 'Assign Guards',
              isActive: _currentStep == 2,
              isCompleted: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem({
    required int stepNumber,
    required String title,
    required bool isActive,
    required bool isCompleted,
  }) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isActive || isCompleted
                ? AppColors.primaryBlue
                : AppColors.lightGray,
            borderRadius: BorderRadius.circular(17),
          ),
          alignment: Alignment.center,
          child: isCompleted
              ? const Icon(
                  Icons.check_rounded,
                  color: AppColors.pureWhite,
                  size: 18,
                )
              : Text(
                  '$stepNumber',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.pureWhite : AppColors.textGray,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? AppColors.primaryBlue : AppColors.textGray,
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelectionStep(bool isSmallScreen) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSmallScreen) _buildMobileStepIndicator(),
          _buildCard(
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
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: AppColors.primaryBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Date Range',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkGray,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Choose start and end dates for your roster',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildDateSelector(
                  label: 'Start Date',
                  date: _startDate,
                  onTap: _pickStartDate,
                  icon: Icons.event_available_rounded,
                ),
                const SizedBox(height: 16),
                _buildDateSelector(
                  label: 'End Date',
                  date: _endDate,
                  onTap: _pickEndDate,
                  icon: Icons.event_busy_rounded,
                ),
                if (_startDate != null && _endDate != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.lightGray, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.primaryBlue,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_buildDateRange(_startDate!, _endDate!).length} days selected',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.darkGray,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildButton(
            text: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onTap: _startDate != null && _endDate != null
                ? _generateDateRange
                : null,
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileStepIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: _buildCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: Text(
                '$_currentStep',
                style: const TextStyle(
                  color: AppColors.pureWhite,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _currentStep == 1
                  ? 'Step 1: Select Dates'
                  : 'Step 2: Assign Guards',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.darkGray,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textGray,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: date != null
                      ? AppColors.primaryBlue
                      : AppColors.lightGray,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: date != null
                        ? AppColors.primaryBlue
                        : AppColors.textGray,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _formatDate(date),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: date != null
                            ? AppColors.darkGray
                            : AppColors.textGray,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textGray,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRosterManagementStep(bool isSmallScreen) {
    if (_clients.isEmpty) {
      return _buildEmptyState(
        icon: Icons.business_outlined,
        title: 'No Clients Available',
        message: 'Add clients to your system before creating rosters.',
      );
    }

    return Column(
      children: [
        _buildClientSelector(isSmallScreen),
        Expanded(
          child: _selectedClientId == null
              ? _buildEmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'Select a Client',
                  message:
                      'Choose a client to manage their roster assignments.',
                )
              : _buildRosterGrid(isSmallScreen),
        ),
        _buildBottomActionBar(isSmallScreen),
      ],
    );
  }

  Widget _buildClientSelector(bool isSmallScreen) {
    final List<Map<String, dynamic>> visibleClients = _clientsSortedBySearch;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isSmallScreen ? 12 : 20,
        isSmallScreen ? 12 : 20,
        isSmallScreen ? 12 : 20,
        0,
      ),
      child: _buildCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.lightGray,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.business_rounded,
                      color: AppColors.primaryBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Client',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkGray,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.lightGray),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _clientSearch = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search client...',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textGray,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.primaryBlue,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: AppColors.pureWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.lightGray,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.lightGray,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 1,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  isDense: true,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.darkGray,
                ),
              ),
            ),
            SizedBox(
              height: isSmallScreen ? 104 : 88,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                scrollDirection: Axis.horizontal,
                itemCount: visibleClients.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final Map<String, dynamic> client = visibleClients[index];
                  final String clientId = _asString(client['_id']);
                  final String clientName = _asString(client['name']);
                  final bool isSelected = _selectedClientId == clientId;
                  final bool hasAssignments = _hasAssignmentsForClient(
                    clientId,
                  );

                  return _buildClientChip(
                    clientName: clientName,
                    isSelected: isSelected,
                    hasAssignments: hasAssignments,
                    onTap: () {
                      setState(() {
                        _selectedClientId = clientId;
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientChip({
    required String clientName,
    required bool isSelected,
    required bool hasAssignments,
    required VoidCallback onTap,
  }) {
    return _HoverSurface(
      hoverable: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      backgroundColor: isSelected ? AppColors.primaryBlue : AppColors.pureWhite,
      border: Border.all(
        color: isSelected ? AppColors.primaryBlue : AppColors.mediumGray,
        width: 1,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            clientName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.pureWhite : AppColors.darkGray,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasAssignments) ...[
            const SizedBox(height: 4),
            Text(
              'Has roster',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? AppColors.pureWhite.withValues(alpha: 0.9)
                    : AppColors.textGray,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRosterGrid(bool isSmallScreen) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isSmallScreen ? 12 : 20,
        0,
        isSmallScreen ? 12 : 20,
        isSmallScreen ? 12 : 20,
      ),
      child: _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_dateRange.isEmpty)
              _buildEmptyState(
                icon: Icons.calendar_today_outlined,
                title: 'No Dates Available',
                message: 'Please select a date range to continue.',
              )
            else
              ..._dateRange.map((date) {
                final String dateKey = _dateKey(date);
                final List<_RosterAssignment> assignments = _assignmentsFor(
                  _selectedClientId!,
                  dateKey,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _buildDateCard(
                    date: date,
                    dateKey: dateKey,
                    assignments: assignments,
                    isSmallScreen: isSmallScreen,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDateCard({
    required DateTime date,
    required String dateKey,
    required List<_RosterAssignment> assignments,
    required bool isSmallScreen,
  }) {
    return _HoverSurface(
      hoverable: true,
      borderRadius: BorderRadius.circular(16),
      backgroundColor: AppColors.pureWhite,
      border: Border.all(color: AppColors.lightGray, width: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        date.day.toString(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.pureWhite,
                        ),
                      ),
                      Text(
                        _monthName(date.month),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.pureWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _weekday(date),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkGray,
                        ),
                      ),
                      Text(
                        '${assignments.length} guard${assignments.length != 1 ? 's' : ''} assigned',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_rounded),
                  color: AppColors.primaryBlue,
                  iconSize: 24,
                  onPressed: () => _showGuardPicker(dateKey),
                ),
              ],
            ),
          ),
          if (assignments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: assignments.map((assignment) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildGuardAssignmentCard(
                      assignment: assignment,
                      dateKey: dateKey,
                      isSmallScreen: isSmallScreen,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGuardAssignmentCard({
    required _RosterAssignment assignment,
    required String dateKey,
    required bool isSmallScreen,
  }) {
    return _HoverSurface(
      hoverable: true,
      borderRadius: BorderRadius.circular(12),
      backgroundColor: AppColors.pureWhite,
      border: Border.all(color: AppColors.lightGray, width: 1),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.lightGray,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _guardName(assignment.guardId),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkGray,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 13,
                      color: AppColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      assignment.checkInTime,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showTimePickerForGuard(assignment, dateKey),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.edit_rounded,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _removeGuard(
                clientId: _selectedClientId!,
                date: dateKey,
                assignmentId: assignment.id,
              ),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.dangerRed,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGuardPicker(String dateKey) {
    String guardSearch = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pureWhite,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final String search = guardSearch.trim().toLowerCase();
            final List<Map<String, dynamic>> availableGuards = _guards.where((
              guard,
            ) {
              final String guardName = _asString(guard['name']).toLowerCase();
              final bool matchesSearch =
                  search.isEmpty || guardName.contains(search);
              return matchesSearch;
            }).toList();

            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.mediumGray,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
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
                              Icons.person_add_rounded,
                              color: AppColors.primaryBlue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Select Guard',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.lightGray,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      child: TextField(
                        autofocus: true,
                        onChanged: (value) {
                          setModalState(() {
                            guardSearch = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search guards...',
                          hintStyle: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: AppColors.primaryBlue,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.lightGray,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.lightGray,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.primaryBlue,
                              width: 1,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          isDense: true,
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.darkGray,
                        ),
                      ),
                    ),
                    Expanded(
                      child: availableGuards.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_off_outlined,
                                      size: 36,
                                      color: AppColors.textGray,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'No guards found',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.darkGray,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'No guards match your search.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textGray,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              itemCount: availableGuards.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final Map<String, dynamic> guard =
                                    availableGuards[index];
                                final String guardId = _asString(guard['_id']);
                                final String guardName = _asString(
                                  guard['name'],
                                );
                                final bool isAlreadyAssigned = _assignmentsFor(
                                  _selectedClientId!,
                                  dateKey,
                                ).any((a) => a.guardId == guardId);

                                return _HoverSurface(
                                  hoverable: true,
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _addGuard(
                                      clientId: _selectedClientId!,
                                      date: dateKey,
                                      guardId: guardId,
                                      checkInTime: '09:00',
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.lightGray,
                                    width: 1,
                                  ),
                                  backgroundColor: AppColors.pureWhite,
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: const BoxDecoration(
                                          color: AppColors.lightGray,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.person_rounded,
                                          color: AppColors.primaryBlue,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              guardName,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.darkGray,
                                              ),
                                            ),
                                            if (isAlreadyAssigned)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Text(
                                                  'Already assigned',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppColors.textGray,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        color: AppColors.textGray,
                                        size: 14,
                                      ),
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
      },
    );
  }

  void _showTimePickerForGuard(
    _RosterAssignment assignment,
    String dateKey,
  ) async {
    final TimeOfDay initialTime = TimeOfDay(
      hour: int.tryParse(assignment.checkInTime.split(':')[0]) ?? 9,
      minute: int.tryParse(assignment.checkInTime.split(':')[1]) ?? 0,
    );

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      orientation: Orientation.portrait,
      builder: (context, child) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.1),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: AppColors.primaryBlue,
                onPrimary: AppColors.pureWhite,
                surface: AppColors.pureWhite,
                onSurface: AppColors.darkGray,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      final String formattedTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      _updateGuardTime(
        clientId: _selectedClientId!,
        date: dateKey,
        assignmentId: assignment.id,
        checkInTime: formattedTime,
      );
    }
  }

  Widget _buildBottomActionBar(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: const BoxDecoration(
        color: AppColors.pureWhite,
        border: Border(top: BorderSide(color: AppColors.lightGray, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 1)
              Expanded(
                child: _buildButton(
                  text: 'Back',
                  icon: Icons.arrow_back_rounded,
                  onTap: () {
                    setState(() {
                      _currentStep = 1;
                    });
                  },
                  isPrimary: false,
                ),
              ),
            if (_currentStep > 1) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _buildButton(
                text: _saving
                    ? 'Saving...'
                    : (_isEditMode ? 'Update Roster' : 'Create Roster'),
                icon: _saving ? null : Icons.check_rounded,
                onTap: _saving ? null : _saveRoster,
                isPrimary: true,
                isLoading: _saving,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    bool hoverable = false,
    double radius = 16,
  }) {
    return _HoverSurface(
      hoverable: hoverable,
      borderRadius: BorderRadius.circular(radius),
      padding: padding,
      backgroundColor: AppColors.pureWhite,
      child: child,
    );
  }

  Widget _buildButton({
    required String text,
    IconData? icon,
    required VoidCallback? onTap,
    required bool isPrimary,
    bool isDestructive = false,
    bool isLoading = false,
  }) {
    final bool isDisabled = onTap == null;
    final bool isFilled = isPrimary || isDestructive;
    final Color backgroundColor = isDisabled
        ? AppColors.lightGray
        : isDestructive
        ? AppColors.dangerRed
        : isPrimary
        ? AppColors.primaryBlue
        : AppColors.pureWhite;
    final Color borderColor = isDisabled
        ? AppColors.mediumGray
        : isFilled
        ? backgroundColor
        : AppColors.mediumGray;
    final Color contentColor = isDisabled
        ? AppColors.textGray
        : isFilled
        ? AppColors.pureWhite
        : AppColors.darkGray;

    return SizedBox(
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: contentColor.withValues(alpha: 0.1),
          highlightColor: contentColor.withValues(alpha: 0.04),
          child: Ink(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(contentColor),
                      ),
                    )
                  else if (icon != null)
                    Icon(icon, color: contentColor, size: 18),
                  if ((icon != null || isLoading) && text.isNotEmpty)
                    const SizedBox(width: 8),
                  if (text.isNotEmpty)
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: contentColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.lightGray,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 48, color: AppColors.primaryBlue),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.darkGray,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textGray,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverSurface extends StatefulWidget {
  const _HoverSurface({
    required this.child,
    required this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.hoverable = false,
    this.onTap,
    this.backgroundColor = AppColors.pureWhite,
    this.border,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final bool hoverable;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final BoxBorder? border;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
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
    final bool hovered = _canHover && _hovering;
    final double offsetY = hovered ? -0.5 : 0;

    return MouseRegion(
      onEnter: _canHover ? (_) => setState(() => _hovering = true) : null,
      onExit: _canHover ? (_) => setState(() => _hovering = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, offsetY, 0),
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: widget.borderRadius,
          border: widget.border,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: hovered ? 0.06 : 0.04),
              blurRadius: hovered ? 14 : 10,
              offset: Offset(0, hovered ? 6 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: widget.borderRadius,
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
