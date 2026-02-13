import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/roster_pdf_service.dart';
import '../widget/app_bottom_nav_bar.dart';

enum _SortOrder { desc, asc }

class _RosterColors {
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF8FAFC);
  static const Color lightGray = Color(0xFFE5E7EB);
  static const Color mediumGray = Color(0xFFD1D5DB);
  static const Color textGray = Color(0xFF6B7280);
  static const Color darkGray = Color(0xFF1F2937);
  static const Color dangerRed = Color(0xFFDC2626);
}

class _DeleteRosterDialog extends StatefulWidget {
  const _DeleteRosterDialog();

  @override
  State<_DeleteRosterDialog> createState() => _DeleteRosterDialogState();
}

class _DeleteRosterDialogState extends State<_DeleteRosterDialog> {
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
      content: const Text('Are you sure you want to delete this roster?'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canDelete
              ? () {
                  Navigator.of(context).pop(true);
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
          ),
          child: Text(_canDelete ? 'Delete' : 'Delete ($_countdownLabel)'),
        ),
      ],
    );
  }
}

class RosterPage extends StatefulWidget {
  const RosterPage({super.key});

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {
  final List<Map<String, dynamic>> _rosters = <Map<String, dynamic>>[];
  final Set<String> _downloadingRosterIds = <String>{};

  bool _loading = true;
  _SortOrder _sortOrder = _SortOrder.desc;
  String _searchQuery = '';

  Dio _api() => ApiClient.create(opt: 0, token: AuthStorage.token);

  @override
  void initState() {
    super.initState();
    _fetchRosters();
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

  List<dynamic> _asList(dynamic value) {
    if (value is List) {
      return value;
    }
    return <dynamic>[];
  }

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  DateTime? _asDate(dynamic value) {
    final String raw = _asString(value).trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
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

  String _formatDayMonthYear(DateTime? date) {
    if (date == null) {
      return '--';
    }
    return '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) {
      return '--';
    }

    final int hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final String amPm = date.hour >= 12 ? 'PM' : 'AM';
    final String minute = date.minute.toString().padLeft(2, '0');
    return '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)}, $hour:$minute $amPm';
  }

  String _dateKey(DateTime date) {
    final DateTime normalized = DateTime(date.year, date.month, date.day);
    final String year = normalized.year.toString().padLeft(4, '0');
    final String month = normalized.month.toString().padLeft(2, '0');
    final String day = normalized.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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

  String _guardNameFromAssignment(Map<String, dynamic> assignment) {
    final String explicitName = _asString(assignment['guardName']).trim();
    if (explicitName.isNotEmpty) {
      return explicitName;
    }

    final dynamic guardValue = assignment['guardId'];
    if (guardValue is Map) {
      final Map<String, dynamic> guardMap = _asMap(guardValue);
      final String name = _asString(guardMap['name']).trim();
      if (name.isNotEmpty) {
        return name;
      }
    }

    final String fallbackName = _asString(assignment['name']).trim();
    if (fallbackName.isNotEmpty) {
      return fallbackName;
    }

    return 'Unknown';
  }

  String _clientNameFromEntry(Map<String, dynamic> clientMap) {
    final String explicitName = _asString(clientMap['name']).trim();
    if (explicitName.isNotEmpty) {
      return explicitName;
    }

    final dynamic clientIdValue = clientMap['clientId'];
    if (clientIdValue is Map) {
      final Map<String, dynamic> nestedClient = _asMap(clientIdValue);
      final String nestedName = _asString(nestedClient['name']).trim();
      if (nestedName.isNotEmpty) {
        return nestedName;
      }
    }

    return 'Unknown Venue';
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

  Future<void> _fetchRosters() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final Response<dynamic> res = await _api().get('/getRosters');
      final Map<String, dynamic> body = _asMap(res.data);
      if (body['ok'] == true) {
        final List<Map<String, dynamic>> list = _asMapList(body['rosters']);
        if (mounted) {
          setState(() {
            _rosters
              ..clear()
              ..addAll(list);
          });
        }
      } else {
        throw Exception(
          _asString(body['error']).isNotEmpty
              ? _asString(body['error'])
              : 'Unable to fetch rosters',
        );
      }
    } catch (err) {
      _showSnack(_errorMessage(err), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openNewRoster() async {
    await Navigator.pushNamed(context, AppRoutes.newRoster);
    if (mounted) {
      _fetchRosters();
    }
  }

  Future<void> _deleteRoster(String id) async {
    final bool shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (_) => const _DeleteRosterDialog(),
        ) ??
        false;

    if (!shouldDelete) {
      return;
    }

    try {
      final Response<dynamic> res = await _api().delete('/deleteRoster/$id');
      final Map<String, dynamic> body = _asMap(res.data);
      if (body['ok'] == true) {
        if (mounted) {
          setState(() {
            _rosters.removeWhere((item) => _asString(item['_id']) == id);
          });
        }
        _showSnack('Roster deleted');
      } else {
        throw Exception(
          _asString(body['error']).isNotEmpty
              ? _asString(body['error'])
              : 'Unable to delete roster',
        );
      }
    } catch (err) {
      _showSnack(_errorMessage(err), isError: true);
    }
  }

  int _totalClients(Map<String, dynamic> roster) {
    return _asList(roster['clients']).length;
  }

  int _totalAssignments(Map<String, dynamic> roster) {
    int total = 0;

    final List<dynamic> clients = _asList(roster['clients']);
    for (final dynamic client in clients) {
      final Map<String, dynamic> clientMap = _asMap(client);
      final List<dynamic> dates = _asList(clientMap['dates']);
      for (final dynamic dateEntry in dates) {
        final Map<String, dynamic> dateMap = _asMap(dateEntry);
        total += _asList(dateMap['assignments']).length;
      }
    }

    return total;
  }

  String _rosterCode(String id) {
    if (id.isEmpty) {
      return '-----';
    }
    if (id.length <= 5) {
      return id.toUpperCase();
    }
    return id.substring(id.length - 5).toUpperCase();
  }

  void _showRosterDetails(Map<String, dynamic> roster) {
    final String id = _asString(roster['_id']);
    if (id.isEmpty) {
      _showSnack('Unable to open roster details', isError: true);
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.rosterView,
      arguments: <String, dynamic>{'rosterId': id},
    ).then((_) {
      if (mounted) {
        _fetchRosters();
      }
    });
  }

  List<RosterPdfClient> _buildPdfClientsForRoster({
    required Map<String, dynamic> roster,
    required List<DateTime> dateRange,
  }) {
    final Set<String> validDateKeys = dateRange.map(_dateKey).toSet();
    final List<dynamic> rosterClients = _asList(roster['clients']);
    final List<RosterPdfClient> clients = <RosterPdfClient>[];

    for (final dynamic clientValue in rosterClients) {
      final Map<String, dynamic> clientMap = _asMap(clientValue);
      final String clientName = _clientNameFromEntry(clientMap);

      final Map<String, List<RosterPdfAssignment>> assignmentsByDate =
          <String, List<RosterPdfAssignment>>{
            for (final DateTime date in dateRange)
              _dateKey(date): <RosterPdfAssignment>[],
          };

      final List<dynamic> dateEntries = _asList(clientMap['dates']);
      for (final dynamic dateValue in dateEntries) {
        final Map<String, dynamic> dateMap = _asMap(dateValue);
        final String dateKey = _normalizeDateKey(_asString(dateMap['date']));
        if (!validDateKeys.contains(dateKey)) {
          continue;
        }

        final List<dynamic> assignmentsRaw = _asList(dateMap['assignments']);
        final List<RosterPdfAssignment> parsed = <RosterPdfAssignment>[];
        for (final dynamic assignmentValue in assignmentsRaw) {
          final Map<String, dynamic> assignmentMap = _asMap(assignmentValue);
          parsed.add(
            RosterPdfAssignment(
              guardName: _guardNameFromAssignment(assignmentMap),
              checkInTime:
                  _asString(assignmentMap['checkInTime']).trim().isEmpty
                  ? '09:00'
                  : _asString(assignmentMap['checkInTime']).trim(),
            ),
          );
        }
        assignmentsByDate[dateKey] = parsed;
      }

      clients.add(
        RosterPdfClient(name: clientName, assignmentsByDate: assignmentsByDate),
      );
    }

    return clients;
  }

  Future<void> _downloadRosterPdf(Map<String, dynamic> roster) async {
    final String rosterId = _asString(roster['_id']).trim();
    if (rosterId.isEmpty || _downloadingRosterIds.contains(rosterId)) {
      return;
    }

    final DateTime? startDate = _asDate(roster['startDate']);
    final DateTime? endDate = _asDate(roster['endDate']);
    if (startDate == null || endDate == null) {
      _showSnack(
        'Unable to export this roster: missing date range',
        isError: true,
      );
      return;
    }

    final List<DateTime> dateRange = _buildDateRange(startDate, endDate);
    final List<RosterPdfClient> clients = _buildPdfClientsForRoster(
      roster: roster,
      dateRange: dateRange,
    );

    if (clients.isEmpty) {
      _showSnack('No roster data found to export', isError: true);
      return;
    }

    setState(() {
      _downloadingRosterIds.add(rosterId);
    });

    try {
      await RosterPdfService.shareRosterPdf(
        startDate: DateTime(startDate.year, startDate.month, startDate.day),
        endDate: DateTime(endDate.year, endDate.month, endDate.day),
        dateRange: dateRange,
        clients: clients,
        logoAssetPath: 'assets/LogoNoBg.png',
        logoWidth: 60,
        filename:
            'roster_${_rosterCode(rosterId)}_${_dateKey(startDate)}_to_${_dateKey(endDate)}.pdf',
      );
    } catch (err) {
      _showSnack('Failed to export PDF: ${_errorMessage(err)}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _downloadingRosterIds.remove(rosterId);
        });
      }
    }
  }

  List<Map<String, dynamic>> get _sortedRosters {
    final List<Map<String, dynamic>> copied = _rosters
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    copied.sort((a, b) {
      final DateTime aDate = _asDate(a['createdAt']) ?? DateTime(1970);
      final DateTime bDate = _asDate(b['createdAt']) ?? DateTime(1970);
      if (_sortOrder == _SortOrder.desc) {
        return bDate.compareTo(aDate);
      }
      return aDate.compareTo(bDate);
    });

    return copied;
  }

  List<Map<String, dynamic>> get _visibleRosters {
    final List<Map<String, dynamic>> list = _sortedRosters;
    final String q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return list;
    }

    return list.where((roster) {
      final String id = _asString(roster['_id']);
      final DateTime? startDate = _asDate(roster['startDate']);
      final DateTime? endDate = _asDate(roster['endDate']);

      final String code = _rosterCode(id).toLowerCase();
      final String startText = _formatDayMonthYear(startDate).toLowerCase();
      final String endText = _formatDayMonthYear(endDate).toLowerCase();

      return id.toLowerCase().contains(q) ||
          code.contains(q) ||
          startText.contains(q) ||
          endText.contains(q);
    }).toList();
  }

  int get _totalAssignmentsAcrossAll {
    int total = 0;
    for (final Map<String, dynamic> roster in _rosters) {
      total += _totalAssignments(roster);
    }
    return total;
  }

  BoxDecoration _buildBackgroundGradient() {
    return const BoxDecoration(color: _RosterColors.offWhite);
  }

  ButtonStyle _primaryButtonStyle({bool compact = false}) {
    return FilledButton.styleFrom(
      backgroundColor: _RosterColors.primaryBlue,
      foregroundColor: _RosterColors.pureWhite,
      minimumSize: Size(0, compact ? 42 : 46),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600),
    );
  }

  ButtonStyle _secondaryButtonStyle({
    bool compact = false,
    Color borderColor = _RosterColors.mediumGray,
    Color foreground = _RosterColors.darkGray,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      minimumSize: Size(0, compact ? 42 : 46),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 13),
      side: BorderSide(color: borderColor.withValues(alpha: 0.72), width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600),
      backgroundColor: _RosterColors.pureWhite,
    );
  }

  Widget _buildCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    bool hoverable = false,
    double radius = 16,
  }) {
    return _HoverCard(
      hoverable: hoverable,
      borderRadius: BorderRadius.circular(radius),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _buildTopStat({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    final Color toned = color.withValues(alpha: 0.78);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _RosterColors.pureWhite,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _RosterColors.lightGray.withValues(alpha: 0.82),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: toned),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: toned,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final bool newestFirst = _sortOrder == _SortOrder.desc;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: _buildCard(
        radius: 16,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _RosterColors.primaryBlue,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Roster Planner',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: _RosterColors.darkGray,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage, sort and edit saved rosters',
                        style: TextStyle(
                          fontSize: 13,
                          color: _RosterColors.textGray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
                hintText: 'Search by roster code or date',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _RosterColors.primaryBlue,
                ),
                filled: true,
                fillColor: _RosterColors.pureWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: _RosterColors.lightGray,
                    width: 1.0,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: _RosterColors.lightGray,
                    width: 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: _RosterColors.primaryBlue,
                    width: 1.0,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _sortOrder = newestFirst
                          ? _SortOrder.asc
                          : _SortOrder.desc;
                    });
                  },
                  style: _secondaryButtonStyle(compact: true),
                  icon: Icon(
                    newestFirst
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 16,
                  ),
                  label: Text(newestFirst ? 'Newest First' : 'Oldest First'),
                ),
                _buildTopStat(
                  icon: Icons.event_note_outlined,
                  text: '${_rosters.length} Rosters',
                  color: _RosterColors.primaryBlue,
                ),
                _buildTopStat(
                  icon: Icons.shield_outlined,
                  text: '$_totalAssignmentsAcrossAll Assignments',
                  color: _RosterColors.textGray,
                ),
                FilledButton.icon(
                  onPressed: _openNewRoster,
                  style: _primaryButtonStyle(compact: true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Roster'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    final Color toned = color.withValues(alpha: 0.78);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _RosterColors.pureWhite,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _RosterColors.lightGray.withValues(alpha: 0.82),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: toned),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: toned,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRosterCard(Map<String, dynamic> roster) {
    final String id = _asString(roster['_id']);
    final DateTime? startDate = _asDate(roster['startDate']);
    final DateTime? endDate = _asDate(roster['endDate']);
    final DateTime? createdAt = _asDate(roster['createdAt']);

    final int clients = _totalClients(roster);
    final int assignments = _totalAssignments(roster);
    final bool downloadingPdf = _downloadingRosterIds.contains(id);

    return _HoverCard(
      hoverable: true,
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showRosterDetails(roster),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _RosterColors.primaryBlue.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Roster #${_rosterCode(id)}',
                        style: const TextStyle(
                          color: _RosterColors.primaryBlue,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: _RosterColors.textGray,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _formatDateTime(createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _RosterColors.textGray,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _RosterColors.offWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _RosterColors.lightGray.withValues(alpha: 0.65),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: _RosterColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_formatDayMonthYear(startDate)}  •  ${_formatDayMonthYear(endDate)}',
                          style: const TextStyle(
                            color: _RosterColors.darkGray,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricChip(
                      icon: Icons.business_outlined,
                      text: '$clients Clients',
                      color: _RosterColors.darkGray,
                    ),
                    _metricChip(
                      icon: Icons.shield_outlined,
                      text: '$assignments Assignments',
                      color: _RosterColors.textGray,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showRosterDetails(roster),
                        style: _primaryButtonStyle(compact: true),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View & Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: id.isEmpty || downloadingPdf
                          ? null
                          : () => _downloadRosterPdf(roster),
                      style: _secondaryButtonStyle(
                        compact: true,
                        borderColor: _RosterColors.primaryBlue.withValues(
                          alpha: 0.45,
                        ),
                        foreground: _RosterColors.primaryBlue,
                      ),
                      icon: downloadingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(downloadingPdf ? '...' : 'PDF'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: id.isEmpty ? null : () => _deleteRoster(id),
                      style: _secondaryButtonStyle(
                        compact: true,
                        borderColor: _RosterColors.dangerRed.withValues(
                          alpha: 0.55,
                        ),
                        foreground: _RosterColors.dangerRed,
                      ),
                      child: const Icon(Icons.delete_outline_rounded, size: 19),
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

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 16),
          Text(
            'Loading rosters...',
            style: TextStyle(
              color: _RosterColors.textGray,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty({required bool fromSearch}) {
    final String title = fromSearch ? 'No matching rosters' : 'No rosters yet';
    final String subtitle = fromSearch
        ? 'Try another search keyword or clear search.'
        : 'Create your first roster and assign guards to clients.';

    return RefreshIndicator(
      onRefresh: _fetchRosters,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 98,
                    height: 98,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _RosterColors.lightGray.withValues(alpha: 0.7),
                    ),
                    child: const Icon(
                      Icons.event_note_outlined,
                      size: 44,
                      color: _RosterColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _RosterColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _RosterColors.textGray,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (fromSearch)
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      style: _secondaryButtonStyle(compact: true),
                      child: const Text('Clear Search'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _openNewRoster,
                      style: _primaryButtonStyle(compact: true),
                      icon: const Icon(Icons.add),
                      label: const Text('Create New Roster'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _buildLoading();
    }

    if (_rosters.isEmpty) {
      return _buildEmpty(fromSearch: false);
    }

    final List<Map<String, dynamic>> visible = _visibleRosters;
    if (visible.isEmpty) {
      return _buildEmpty(fromSearch: true);
    }

    return RefreshIndicator(
      onRefresh: _fetchRosters,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemBuilder: (_, index) => _buildRosterCard(visible[index]),
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemCount: visible.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _RosterColors.offWhite,
      body: Container(
        decoration: _buildBackgroundGradient(),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 1),
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({
    required this.child,
    required this.borderRadius,
    this.hoverable = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool hoverable;

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
    final double elevation = _canHover && _hovering ? 3 : 1.5;
    final double offsetY = _canHover && _hovering ? -0.5 : 0;

    return MouseRegion(
      onEnter: _canHover ? (_) => setState(() => _hovering = true) : null,
      onExit: _canHover ? (_) => setState(() => _hovering = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, offsetY, 0),
        child: Material(
          color: _RosterColors.pureWhite,
          elevation: elevation,
          shadowColor: Colors.black.withValues(alpha: 0.04),
          borderRadius: widget.borderRadius,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
