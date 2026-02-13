import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/tester_data_service.dart';
import '../widget/app_bottom_nav_bar.dart';

class _DashboardColors {
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

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const String _allClientsValue = '__all_clients__';

  final List<Map<String, dynamic>> _onDutyGuards = <Map<String, dynamic>>[];

  bool _loadingOnDuty = true;
  bool _loadingRoster = true;
  String _onDutyError = '';
  String _rosterError = '';

  Map<String, dynamic>? _latestRoster;

  String _searchTerm = '';
  String _selectedClientValue = _allClientsValue;

  Dio _api() => ApiClient.create(opt: 0, token: AuthStorage.token);

  @override
  void initState() {
    super.initState();
    _refreshAll();
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

  DateTime? _asDate(dynamic value) {
    final String raw = _asString(value).trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
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

  String _dateKey(DateTime date) {
    final DateTime normalized = DateTime(date.year, date.month, date.day);
    final String year = normalized.year.toString().padLeft(4, '0');
    final String month = normalized.month.toString().padLeft(2, '0');
    final String day = normalized.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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

  String _formatDayMonth(DateTime? date) {
    if (date == null) {
      return '--';
    }
    return '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)}';
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) {
      return 'Not checked in';
    }

    final int hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final String amPm = date.hour >= 12 ? 'PM' : 'AM';
    final String minute = date.minute.toString().padLeft(2, '0');
    return '${_monthName(date.month)} ${date.day}, ${date.year} • $hour:$minute $amPm';
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

  Future<void> _refreshAll() async {
    await Future.wait<void>(<Future<void>>[
      _fetchOnDutyGuards(),
      _fetchLatestRoster(),
    ]);
  }

  Future<void> _fetchOnDutyGuards() async {
    if (mounted) {
      setState(() {
        _loadingOnDuty = true;
        _onDutyError = '';
      });
    }

    try {
      final List<Map<String, dynamic>> guards;
      if (AuthStorage.isTester) {
        guards = await TesterDataService.getOnDutyGuards();
      } else {
        final Response<dynamic> res = await _api().get('/on-duty');
        final Map<String, dynamic> body = _asMap(res.data);
        guards = _asMapList(body['guards']);
      }

      if (mounted) {
        setState(() {
          _onDutyGuards
            ..clear()
            ..addAll(guards);
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _onDutyError = _errorMessage(err);
          _onDutyGuards.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingOnDuty = false;
        });
      }
    }
  }

  Future<void> _fetchLatestRoster() async {
    if (mounted) {
      setState(() {
        _loadingRoster = true;
        _rosterError = '';
      });
    }

    try {
      if (AuthStorage.isTester) {
        final Map<String, dynamic>? roster =
            await TesterDataService.getLatestRoster();
        if (mounted) {
          setState(() {
            _latestRoster = roster;
          });
        }
      } else {
        final Response<dynamic> res = await _api().get('/latestRoster');
        final Map<String, dynamic> body = _asMap(res.data);
        if (body['ok'] == true) {
          final Map<String, dynamic> roster = _asMap(body['roster']);
          if (mounted) {
            setState(() {
              _latestRoster = roster.isEmpty ? null : roster;
            });
          }
        } else {
          throw Exception(
            _asString(body['error']).isNotEmpty
                ? _asString(body['error'])
                : 'Failed to load latest roster',
          );
        }
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _rosterError = _errorMessage(err);
          _latestRoster = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingRoster = false;
        });
      }
    }
  }

  List<String> get _uniqueClients {
    final Set<String> values = <String>{};
    for (final Map<String, dynamic> guard in _onDutyGuards) {
      final String clientName = _asString(guard['clientName']).trim();
      if (clientName.isNotEmpty) {
        values.add(clientName);
      }
    }
    final List<String> sorted = values.toList()..sort();
    return sorted;
  }

  List<Map<String, dynamic>> get _filteredOnDutyGuards {
    final String query = _searchTerm.trim().toLowerCase();
    return _onDutyGuards.where((guard) {
      final String name = _asString(guard['name']).toLowerCase();
      final String clientName = _asString(guard['clientName']).trim();

      final bool matchesSearch = query.isEmpty || name.contains(query);
      final bool matchesClient =
          _selectedClientValue == _allClientsValue ||
          clientName == _selectedClientValue;

      return matchesSearch && matchesClient;
    }).toList();
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
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              color: Colors.white,
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Check-in Image',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _DashboardColors.darkGray,
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
                      maxScale: 4.0,
                      child: Center(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Failed to load image'),
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

  BoxDecoration _backgroundGradient() {
    return const BoxDecoration(color: _DashboardColors.pageBackground);
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
      borderColor: _DashboardColors.lightGray,
      child: Padding(padding: padding, child: child),
    );
  }

  ButtonStyle _outlinedButtonStyle({
    Color color = _DashboardColors.primaryBlue,
    Color? borderColor,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: borderColor ?? _DashboardColors.mediumGray),
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
            color: _DashboardColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _DashboardColors.lightGray),
          ),
          child: Icon(icon, size: 18, color: _DashboardColors.primaryBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _DashboardColors.darkGray,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: _glassPanel(
        hoverable: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _DashboardColors.primaryBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.dashboard_rounded,
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
                        'Admin Dashboard',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _DashboardColors.darkGray,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'On-duty guards and latest roster overview',
                        style: TextStyle(
                          fontSize: 13,
                          color: _DashboardColors.textGray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _tinyStat(
                  icon: Icons.shield_outlined,
                  text: '${_onDutyGuards.length} Guards On Duty',
                  color: _DashboardColors.primaryBlue,
                ),
                _tinyStat(
                  icon: Icons.calendar_month_outlined,
                  text: _latestRoster == null
                      ? 'No Weekly Roster'
                      : 'Latest Roster Ready',
                  color: _DashboardColors.textGray,
                ),
                OutlinedButton.icon(
                  onPressed: _refreshAll,
                  style: _outlinedButtonStyle(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyStat({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _DashboardColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _DashboardColors.lightGray),
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

  Widget _buildOnDutySection() {
    final List<Map<String, dynamic>> filtered = _filteredOnDutyGuards;
    final List<String> clients = _uniqueClients;

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.shield_rounded,
            title: 'Guards On Duty',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _DashboardColors.surfaceMuted,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _DashboardColors.lightGray),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _DashboardColors.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_onDutyGuards.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _DashboardColors.darkGray,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool stacked = constraints.maxWidth < 760;
              final Widget search = TextField(
                onChanged: (value) {
                  setState(() {
                    _searchTerm = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search by guard name',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _DashboardColors.primaryBlue,
                  ),
                  filled: true,
                  fillColor: _DashboardColors.pureWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _DashboardColors.lightGray,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _DashboardColors.lightGray,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _DashboardColors.primaryBlue,
                      width: 1.2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                ),
              );

              final Widget filter = DropdownButtonFormField<String>(
                key: ValueKey<String>(_selectedClientValue),
                initialValue: _selectedClientValue,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.filter_list_rounded,
                    color: _DashboardColors.primaryBlue,
                  ),
                  filled: true,
                  fillColor: _DashboardColors.pureWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _DashboardColors.lightGray,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _DashboardColors.lightGray,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _DashboardColors.primaryBlue,
                      width: 1.2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: _allClientsValue,
                    child: Text(
                      'All Clients (${_onDutyGuards.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...clients.map((clientName) {
                    final int count = _onDutyGuards.where((g) {
                      return _asString(g['clientName']) == clientName;
                    }).length;
                    return DropdownMenuItem<String>(
                      value: clientName,
                      child: Text(
                        '$clientName ($count)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedClientValue = value;
                  });
                },
              );

              if (stacked) {
                return Column(
                  children: [search, const SizedBox(height: 12), filter],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: search),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: filter),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_loadingOnDuty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_onDutyError.isNotEmpty)
            _errorBox(message: _onDutyError, onRetry: _fetchOnDutyGuards)
          else if (_onDutyGuards.isEmpty)
            _emptyBlock(
              icon: Icons.shield_outlined,
              title: 'No guards on duty',
              subtitle: 'No one is currently checked in.',
            )
          else if (filtered.isEmpty)
            _emptyBlock(
              icon: Icons.search_off_rounded,
              title: 'No matching guards',
              subtitle: 'Try another search or change client filter.',
              action: TextButton(
                onPressed: () {
                  setState(() {
                    _searchTerm = '';
                    _selectedClientValue = _allClientsValue;
                  });
                },
                child: const Text('Clear Filters'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final bool twoColumns = constraints.maxWidth >= 980;
                final double spacing = 12;
                final double cardWidth = twoColumns
                    ? (constraints.maxWidth - spacing) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: filtered.map((guard) {
                    return SizedBox(
                      width: cardWidth,
                      child: _buildGuardCard(guard),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGuardCard(Map<String, dynamic> guard) {
    final Map<String, dynamic> shift = _asMap(guard['shift']);

    final String name = _asString(guard['name']).trim().isEmpty
        ? 'Unnamed Guard'
        : _asString(guard['name']).trim();
    final String phone = _asString(guard['phone']).trim();
    final String type = _asString(guard['type']).trim();
    final String photo = _asString(guard['photo']).trim();
    final String clientName = _asString(guard['clientName']).trim();
    final String clientLocationUrl = _asString(
      guard['clientLocationUrl'],
    ).trim();
    final String checkInLocation = _asString(shift['checkInLocation']).trim();
    final String checkInImageUrl = _asString(shift['checkInImageUrl']).trim();
    final DateTime? checkInAt = _asDate(shift['checkInAt']);

    final double? distanceKm = _calculateDistanceKm(
      clientLocationUrl.isEmpty ? null : clientLocationUrl,
      checkInLocation.isEmpty ? null : checkInLocation,
    );
    final bool hasWarning = distanceKm != null && distanceKm > 0.8;
    final String distanceLabel = (distanceKm ?? 0).toStringAsFixed(2);

    return _HoverCard(
      hoverable: true,
      elevation: 1.2,
      hoverElevation: 5,
      borderRadius: BorderRadius.circular(14),
      borderColor: _DashboardColors.lightGray,
      leftAccentColor: hasWarning ? _DashboardColors.warningStripe : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: photo.isEmpty
                      ? Container(
                          width: 48,
                          height: 48,
                          color: _DashboardColors.surfaceMuted,
                          child: const Icon(
                            Icons.person_outline_rounded,
                            color: _DashboardColors.textGray,
                          ),
                        )
                      : Image.network(
                          photo,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: _DashboardColors.surfaceMuted,
                            child: const Icon(
                              Icons.person_outline_rounded,
                              color: _DashboardColors.textGray,
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
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _DashboardColors.darkGray,
                        ),
                      ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _DashboardColors.textGray,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (type.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _DashboardColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _DashboardColors.lightGray,
                            ),
                          ),
                          child: Text(
                            type,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _DashboardColors.darkGray,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasWarning)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: _DashboardColors.warning,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Location Alert',
                          style: TextStyle(
                            color: _DashboardColors.warning,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _DashboardColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _DashboardColors.lightGray),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.business_rounded,
                    size: 15,
                    color: _DashboardColors.primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      clientName.isEmpty ? '—' : clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _DashboardColors.darkGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _detailRow(
              label: 'Check-in Time',
              value: _formatDateTime(checkInAt),
            ),
            if (distanceKm != null)
              _detailRow(
                label: 'Distance From Client',
                value: '${distanceKm.toStringAsFixed(2)} km',
                valueColor: hasWarning
                    ? _DashboardColors.warning
                    : _DashboardColors.darkGray,
              ),
            if (hasWarning)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    'Check-in is ${distanceLabel}km away from client location (threshold: 0.8km).',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _DashboardColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (clientLocationUrl.isNotEmpty ||
                checkInLocation.isNotEmpty ||
                checkInImageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (clientLocationUrl.isNotEmpty)
                      _linkButton(
                        icon: Icons.place_outlined,
                        label: 'Client Location',
                        onTap: () => _openUrl(clientLocationUrl),
                      ),
                    if (checkInLocation.isNotEmpty)
                      _linkButton(
                        icon: Icons.location_on_outlined,
                        label: 'Check-in Location',
                        onTap: () => _openUrl(checkInLocation),
                      ),
                    if (checkInImageUrl.isNotEmpty)
                      _linkButton(
                        icon: Icons.image_outlined,
                        label: 'Check-in Image',
                        onTap: () => _openImagePreview(checkInImageUrl),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String raw) async {
    // Keep it simple: delegate to platform browser via Link widget semantics.
    // For now, using dialog to show URL when deep-link package isn't configured.
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Link'),
        content: SelectableText(raw),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _linkButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color tint = _DashboardColors.primaryBlue,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: tint),
      label: Text(
        label,
        style: TextStyle(color: tint, fontWeight: FontWeight.w600),
      ),
      style: _outlinedButtonStyle(
        color: tint,
        borderColor: tint.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _detailRow({
    required String label,
    required String value,
    Color valueColor = _DashboardColors.darkGray,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                color: _DashboardColors.textGray,
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
      ),
    );
  }

  Widget _buildLatestRosterSection() {
    final DateTime? startDate = _asDate(_latestRoster?['startDate']);
    final DateTime? endDate = _asDate(_latestRoster?['endDate']);

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.calendar_view_week_rounded,
            title: 'Latest Week Roster',
            trailing: (startDate != null && endDate != null)
                ? Text(
                    '${_formatDayMonth(startDate)} → ${_formatDayMonth(endDate)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _DashboardColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          if (_loadingRoster)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rosterError.isNotEmpty)
            _errorBox(message: _rosterError, onRetry: _fetchLatestRoster)
          else if (_latestRoster == null)
            _emptyBlock(
              icon: Icons.calendar_month_outlined,
              title: 'No roster available',
              subtitle: 'Latest weekly roster has not been generated yet.',
            )
          else
            _buildLatestRosterTable(),
        ],
      ),
    );
  }

  List<DateTime> _latestRosterDateRange(List<Map<String, dynamic>> clients) {
    final DateTime? start = _asDate(_latestRoster?['startDate']);
    final DateTime? end = _asDate(_latestRoster?['endDate']);
    if (start != null && end != null && !end.isBefore(start)) {
      return _buildDateRange(start, end);
    }

    final Set<String> dateKeys = <String>{};
    for (final Map<String, dynamic> client in clients) {
      for (final Map<String, dynamic> dateEntry in _asMapList(
        client['dates'],
      )) {
        final String key = _normalizeDateKey(_asString(dateEntry['date']));
        if (key.isNotEmpty) {
          dateKeys.add(key);
        }
      }
    }

    final List<String> sortedKeys = dateKeys.toList()..sort();
    return sortedKeys
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toList();
  }

  String _clientNameFromRoster(Map<String, dynamic> client) {
    final String explicitName = _asString(client['name']).trim();
    if (explicitName.isNotEmpty) {
      return explicitName;
    }

    final dynamic clientId = client['clientId'];
    if (clientId is Map) {
      final String nestedName = _asString(_asMap(clientId)['name']).trim();
      if (nestedName.isNotEmpty) {
        return nestedName;
      }
    }

    return 'Unnamed Venue';
  }

  String _guardNameFromAssignment(Map<String, dynamic> assignment) {
    final String explicit = _asString(assignment['guardName']).trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }

    final dynamic guardId = assignment['guardId'];
    if (guardId is Map) {
      final String nested = _asString(_asMap(guardId)['name']).trim();
      if (nested.isNotEmpty) {
        return nested;
      }
    }

    return 'Guard';
  }

  String _primaryClientTime(Map<String, List<Map<String, dynamic>>> byDate) {
    for (final List<Map<String, dynamic>> assignments in byDate.values) {
      for (final Map<String, dynamic> assignment in assignments) {
        final String time = _asString(assignment['checkInTime']).trim();
        if (time.isNotEmpty) {
          return time;
        }
      }
    }
    return '--:--';
  }

  Widget _buildLatestRosterTable() {
    final List<Map<String, dynamic>> clients = _asMapList(
      _latestRoster?['clients'],
    );
    if (clients.isEmpty) {
      return _emptyBlock(
        icon: Icons.view_week_outlined,
        title: 'Roster has no clients',
        subtitle: 'No venue assignments found in latest roster.',
      );
    }

    final List<DateTime> dateRange = _latestRosterDateRange(clients);
    if (dateRange.isEmpty) {
      return _emptyBlock(
        icon: Icons.event_busy_outlined,
        title: 'Roster dates unavailable',
        subtitle: 'Could not determine date range for latest roster.',
      );
    }

    const double venueWidth = 172;
    const double timeWidth = 92;
    const double dateWidth = 140;

    Widget cell({
      required Widget child,
      required double width,
      Color bg = Colors.white,
      Alignment alignment = Alignment.centerLeft,
      EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ),
    }) {
      return Container(
        width: width,
        alignment: alignment,
        padding: padding,
        color: bg,
        child: child,
      );
    }

    Widget headerCell(String text, {required double width}) {
      return cell(
        width: width,
        bg: _DashboardColors.surfaceMuted,
        alignment: Alignment.center,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _DashboardColors.darkGray,
          ),
        ),
      );
    }

    final List<Widget> header = <Widget>[
      headerCell('Venues', width: venueWidth),
      headerCell('Time', width: timeWidth),
      ...dateRange.map((date) {
        return headerCell(
          '${_weekday(date)} ${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)}',
          width: dateWidth,
        );
      }),
    ];

    final List<Widget> rows = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: header,
      ),
    ];

    for (int i = 0; i < clients.length; i++) {
      final Map<String, dynamic> client = clients[i];
      final String clientName = _clientNameFromRoster(client);
      final Map<String, List<Map<String, dynamic>>> assignmentsByDate =
          <String, List<Map<String, dynamic>>>{};

      for (final Map<String, dynamic> dateEntry in _asMapList(
        client['dates'],
      )) {
        final String dateKey = _normalizeDateKey(_asString(dateEntry['date']));
        assignmentsByDate[dateKey] = _asMapList(dateEntry['assignments']);
      }

      final Color rowBg = i.isEven
          ? _DashboardColors.pureWhite
          : _DashboardColors.surfaceMuted;
      final String primaryTime = _primaryClientTime(assignmentsByDate);

      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cell(
              width: venueWidth,
              bg: rowBg,
              child: Text(
                clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _DashboardColors.darkGray,
                ),
              ),
            ),
            cell(
              width: timeWidth,
              bg: rowBg,
              alignment: Alignment.center,
              child: Text(
                primaryTime,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _DashboardColors.darkGray,
                ),
              ),
            ),
            ...dateRange.map((date) {
              final String key = _dateKey(date);
              final List<Map<String, dynamic>> assignments =
                  assignmentsByDate[key] ?? <Map<String, dynamic>>[];

              if (assignments.isEmpty) {
                return cell(
                  width: dateWidth,
                  bg: rowBg,
                  alignment: Alignment.center,
                  child: const Text(
                    '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _DashboardColors.textGray,
                    ),
                  ),
                );
              }

              return cell(
                width: dateWidth,
                bg: rowBg,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: assignments.map((assignment) {
                    final String guardName = _guardNameFromAssignment(
                      assignment,
                    );
                    final String time = _asString(
                      assignment['checkInTime'],
                    ).trim();
                    return Container(
                      constraints: const BoxConstraints(minWidth: 72),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _DashboardColors.offWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _DashboardColors.lightGray),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            guardName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _DashboardColors.darkGray,
                            ),
                          ),
                          Text(
                            time.isEmpty ? '--:--' : time,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: _DashboardColors.textGray,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
          ],
        ),
      );
    }

    return _HoverCard(
      hoverable: false,
      elevation: 1,
      hoverElevation: 1,
      borderRadius: BorderRadius.circular(14),
      borderColor: _DashboardColors.lightGray,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
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

  Widget _errorBox({required String message, required VoidCallback onRetry}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDD5D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Something went wrong',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFFB91C1C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF991B1B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: _outlinedButtonStyle(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
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
      borderColor: _DashboardColors.lightGray,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: _DashboardColors.mediumGray),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _DashboardColors.darkGray,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _DashboardColors.textGray,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DashboardColors.pageBackground,
      body: Container(
        decoration: _backgroundGradient(),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _buildOnDutySection(),
                      const SizedBox(height: 16),
                      _buildLatestRosterSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 0),
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
          color: _DashboardColors.pureWhite,
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
