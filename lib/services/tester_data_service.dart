import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class TesterDataService {
  const TesterDataService._();

  static const String _boxName = 'tester_data_box';
  static const String _clientsKey = 'clients';
  static const String _guardsKey = 'guards';
  static const String _rostersKey = 'rosters';

  static Future<Box<dynamic>> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return Hive.openBox<dynamic>(_boxName);
    }
    return Hive.box<dynamic>(_boxName);
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  static DateTime? _asDate(dynamic value) {
    final String raw = _asString(value).trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static String _dateKey(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static List<Map<String, dynamic>> _deepCopyList(
    List<Map<String, dynamic>> value,
  ) {
    final dynamic decoded = jsonDecode(jsonEncode(value));
    return _asMapList(decoded);
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
    final dynamic decoded = jsonDecode(jsonEncode(value));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  static Future<void> ensureSeeded() async {
    final Box<dynamic> box = await _box();

    final List<Map<String, dynamic>> existingClients = _asMapList(
      box.get(_clientsKey),
    );
    final List<Map<String, dynamic>> existingGuards = _asMapList(
      box.get(_guardsKey),
    );
    final List<Map<String, dynamic>> existingRosters = _asMapList(
      box.get(_rostersKey),
    );

    if (existingClients.isNotEmpty &&
        existingGuards.isNotEmpty &&
        existingRosters.isNotEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime monday = now.subtract(Duration(days: now.weekday - 1));
    final DateTime sunday = monday.add(const Duration(days: 6));

    final List<Map<String, dynamic>> clients = <Map<String, dynamic>>[
      <String, dynamic>{
        '_id': 'client_001',
        'name': 'Harbor Lounge',
        'type': 'bar',
        'contactPerson': 'Ivy Reed',
        'contactPhone': '+1 555 0101',
        'email': 'ops@harborlounge.example',
        'website': 'https://harborlounge.example',
        'logo': 'https://picsum.photos/seed/client001/200/200',
        'address': '101 Harbor Ave, Miami, FL',
        'locationUrl': 'https://maps.google.com/?q=25.7617,-80.1918',
        'note': 'VIP entrance requires 2 guards on weekends.',
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
      },
      <String, dynamic>{
        '_id': 'client_002',
        'name': 'Summit Mall',
        'type': 'retail',
        'contactPerson': 'Noah Carter',
        'contactPhone': '+1 555 0102',
        'email': 'admin@summitmall.example',
        'website': 'https://summitmall.example',
        'logo': 'https://picsum.photos/seed/client002/200/200',
        'address': '22 Pine Road, Dallas, TX',
        'locationUrl': 'https://maps.google.com/?q=32.7767,-96.7970',
        'note': 'Morning shift starts at loading dock.',
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
      },
      <String, dynamic>{
        '_id': 'client_003',
        'name': 'Azure Offices',
        'type': 'office',
        'contactPerson': 'Maya Patel',
        'contactPhone': '+1 555 0103',
        'email': 'security@azureoffices.example',
        'website': 'https://azureoffices.example',
        'logo': 'https://picsum.photos/seed/client003/200/200',
        'address': '88 Lake View Dr, Seattle, WA',
        'locationUrl': 'https://maps.google.com/?q=47.6062,-122.3321',
        'note': 'Night shift badge audit each Friday.',
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
      },
    ];

    final List<Map<String, dynamic>> guards = <Map<String, dynamic>>[
      <String, dynamic>{
        '_id': 'guard_001',
        'name': 'Liam Brooks',
        'phone': '+1 555 1001',
        'email': 'liam.brooks@example.com',
        'type': 'bouncer',
        'password': '',
        'defaultPay': 110,
        'gender': 'M',
        'photo': 'https://picsum.photos/seed/guard001/200/200',
        'weightKg': '78',
        'heightCm': '182',
        'dob': '1993-08-11',
        'nationality': <String>['USA'],
        'language': <String>['English'],
        'notes': 'Strong customer handling skills.',
        'bio': '6 years of venue security experience.',
        'emiratesId': <String, dynamic>{
          'no': 'EMR001',
          'issueDate': '2024-01-10',
          'expiryDate': '2027-01-09',
          'imageUrl': <String>[],
          'verified': true,
        },
        'passport': <String, dynamic>{
          'no': 'P001122',
          'issueDate': '2022-03-20',
          'expiryDate': '2032-03-19',
          'imageUrl': <String>[],
          'verified': true,
        },
        'sira': <String, dynamic>{
          'no': 'SIRA-1001',
          'issueDate': '2025-05-01',
          'expiryDate': '2027-05-01',
          'imageUrl': <String>[],
          'verified': true,
        },
        'block': false,
        'verified': true,
        'complaints': <Map<String, dynamic>>[],
        'lastLogin': _nowIso(),
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
      },
      <String, dynamic>{
        '_id': 'guard_002',
        'name': 'Emma Stone',
        'phone': '+1 555 1002',
        'email': 'emma.stone@example.com',
        'type': 'security-guard',
        'password': '',
        'defaultPay': 95,
        'gender': 'F',
        'photo': 'https://picsum.photos/seed/guard002/200/200',
        'weightKg': '62',
        'heightCm': '170',
        'dob': '1996-04-28',
        'nationality': <String>['USA'],
        'language': <String>['English', 'Spanish'],
        'notes': 'Experienced in retail patrol.',
        'bio': 'Focused on access control and incident reports.',
        'emiratesId': <String, dynamic>{
          'no': 'EMR002',
          'issueDate': '2024-02-12',
          'expiryDate': '2027-02-11',
          'imageUrl': <String>[],
          'verified': true,
        },
        'passport': <String, dynamic>{
          'no': 'P009911',
          'issueDate': '2021-11-04',
          'expiryDate': '2031-11-03',
          'imageUrl': <String>[],
          'verified': true,
        },
        'sira': <String, dynamic>{
          'no': 'SIRA-1002',
          'issueDate': '2025-03-10',
          'expiryDate': '2027-03-09',
          'imageUrl': <String>[],
          'verified': false,
        },
        'block': false,
        'verified': true,
        'complaints': <Map<String, dynamic>>[
          <String, dynamic>{
            'description': 'Late by 10 minutes',
            'severity': 'low',
            'date': monday.toUtc().toIso8601String(),
            'resolved': true,
          },
        ],
        'lastLogin': _nowIso(),
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
      },
      <String, dynamic>{
        '_id': 'guard_003',
        'name': 'Noah Hayes',
        'phone': '+1 555 1003',
        'email': 'noah.hayes@example.com',
        'type': 'supervisor',
        'password': '',
        'defaultPay': 130,
        'gender': 'M',
        'photo': 'https://picsum.photos/seed/guard003/200/200',
        'weightKg': '85',
        'heightCm': '186',
        'dob': '1991-01-15',
        'nationality': <String>['USA'],
        'language': <String>['English'],
        'notes': 'Handles escalation and team handoff.',
        'bio': 'Leads evening operation across multiple sites.',
        'emiratesId': <String, dynamic>{
          'no': 'EMR003',
          'issueDate': '2023-12-01',
          'expiryDate': '2026-11-30',
          'imageUrl': <String>[],
          'verified': true,
        },
        'passport': <String, dynamic>{
          'no': 'P004411',
          'issueDate': '2020-07-14',
          'expiryDate': '2030-07-13',
          'imageUrl': <String>[],
          'verified': true,
        },
        'sira': <String, dynamic>{
          'no': 'SIRA-1003',
          'issueDate': '2024-09-01',
          'expiryDate': '2026-09-01',
          'imageUrl': <String>[],
          'verified': true,
        },
        'block': false,
        'verified': true,
        'complaints': <Map<String, dynamic>>[],
        'lastLogin': _nowIso(),
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
      },
    ];

    final List<Map<String, dynamic>> rosters = <Map<String, dynamic>>[
      <String, dynamic>{
        '_id': 'roster_001',
        'startDate': _dateKey(monday),
        'endDate': _dateKey(sunday),
        'clients': <Map<String, dynamic>>[
          <String, dynamic>{
            'clientId': 'client_001',
            'name': 'Harbor Lounge',
            'dates': <Map<String, dynamic>>[
              <String, dynamic>{
                'date': _dateKey(monday),
                'assignments': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'guardId': 'guard_001',
                    'guardName': 'Liam Brooks',
                    'checkInTime': '20:00',
                  },
                ],
              },
              <String, dynamic>{
                'date': _dateKey(monday.add(const Duration(days: 1))),
                'assignments': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'guardId': 'guard_003',
                    'guardName': 'Noah Hayes',
                    'checkInTime': '20:00',
                  },
                ],
              },
            ],
          },
          <String, dynamic>{
            'clientId': 'client_002',
            'name': 'Summit Mall',
            'dates': <Map<String, dynamic>>[
              <String, dynamic>{
                'date': _dateKey(monday),
                'assignments': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'guardId': 'guard_002',
                    'guardName': 'Emma Stone',
                    'checkInTime': '09:00',
                  },
                ],
              },
            ],
          },
          <String, dynamic>{
            'clientId': 'client_003',
            'name': 'Azure Offices',
            'dates': <Map<String, dynamic>>[
              <String, dynamic>{
                'date': _dateKey(monday.add(const Duration(days: 2))),
                'assignments': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'guardId': 'guard_003',
                    'guardName': 'Noah Hayes',
                    'checkInTime': '18:00',
                  },
                ],
              },
            ],
          },
        ],
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
      },
    ];

    await box.put(_clientsKey, clients);
    await box.put(_guardsKey, guards);
    await box.put(_rostersKey, rosters);
  }

  static Future<List<Map<String, dynamic>>> getClients() async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    return _deepCopyList(_asMapList(box.get(_clientsKey)));
  }

  static Future<List<Map<String, dynamic>>> getGuards() async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    return _deepCopyList(_asMapList(box.get(_guardsKey)));
  }

  static Future<List<Map<String, dynamic>>> getRosters() async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    return _deepCopyList(_asMapList(box.get(_rostersKey)));
  }

  static Future<Map<String, dynamic>?> getRosterById(String rosterId) async {
    final List<Map<String, dynamic>> rosters = await getRosters();
    for (final Map<String, dynamic> roster in rosters) {
      if (_asString(roster['_id']).trim() == rosterId.trim()) {
        return _deepCopyMap(roster);
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>> getDateForRosterData() async {
    return <String, dynamic>{
      'clients': await getClients(),
      'guards': await getGuards(),
    };
  }

  static Future<Map<String, dynamic>?> getLatestRoster() async {
    final List<Map<String, dynamic>> rosters = await getRosters();
    if (rosters.isEmpty) {
      return null;
    }

    rosters.sort((a, b) {
      final DateTime ad = _asDate(a['createdAt']) ?? DateTime(1970);
      final DateTime bd = _asDate(b['createdAt']) ?? DateTime(1970);
      return bd.compareTo(ad);
    });

    return _deepCopyMap(rosters.first);
  }

  static Future<List<Map<String, dynamic>>> getOnDutyGuards() async {
    final List<Map<String, dynamic>> guards = await getGuards();
    final List<Map<String, dynamic>> clients = await getClients();
    final Map<String, Map<String, dynamic>> guardById =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> item in guards)
            _asString(item['_id']): item,
        };
    final Map<String, Map<String, dynamic>> clientById =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> item in clients)
            _asString(item['_id']): item,
        };

    final Map<String, dynamic>? latestRoster = await getLatestRoster();
    if (latestRoster == null) {
      return <Map<String, dynamic>>[];
    }

    final String todayKey = _dateKey(DateTime.now());
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> client in _asMapList(
      latestRoster['clients'],
    )) {
      final String clientId = _asString(client['clientId']).trim();
      final Map<String, dynamic> clientData = clientById[clientId] ?? client;
      final String clientName = _asString(clientData['name']).trim();
      final String clientLocationUrl = _asString(
        clientData['locationUrl'],
      ).trim();

      for (final Map<String, dynamic> dateItem in _asMapList(client['dates'])) {
        final String date = _asString(dateItem['date']).trim();
        if (date != todayKey) {
          continue;
        }

        for (final Map<String, dynamic> assignment in _asMapList(
          dateItem['assignments'],
        )) {
          final String guardId = _asString(assignment['guardId']).trim();
          final Map<String, dynamic> guard =
              guardById[guardId] ?? <String, dynamic>{};

          final String checkInTime =
              _asString(assignment['checkInTime']).trim().isEmpty
              ? '09:00'
              : _asString(assignment['checkInTime']).trim();

          result.add(<String, dynamic>{
            '_id': 'onduty_${guardId}_$date',
            'name': _asString(guard['name']),
            'phone': _asString(guard['phone']),
            'type': _asString(guard['type']),
            'photo': _asString(guard['photo']),
            'clientName': clientName,
            'clientLocationUrl': clientLocationUrl,
            'shift': <String, dynamic>{
              'checkInAt': '${date}T$checkInTime:00.000Z',
              'checkInLocation': clientLocationUrl,
              'checkInImageUrl': _asString(guard['photo']),
            },
          });
        }
      }
    }

    return _deepCopyList(result);
  }

  static Future<Map<String, dynamic>> upsertClient({
    required Map<String, dynamic> payload,
    String? clientId,
  }) async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    final List<Map<String, dynamic>> clients = _asMapList(box.get(_clientsKey));
    final String now = _nowIso();

    if (_asString(clientId).trim().isNotEmpty) {
      final String id = _asString(clientId).trim();
      final int index = clients.indexWhere(
        (item) => _asString(item['_id']) == id,
      );
      if (index >= 0) {
        final Map<String, dynamic> updated = <String, dynamic>{
          ...clients[index],
          ...payload,
          '_id': id,
          'updatedAt': now,
        };
        clients[index] = updated;
        await box.put(_clientsKey, clients);
        return _deepCopyMap(updated);
      }
    }

    final String newId =
        'client_${DateTime.now().microsecondsSinceEpoch.toString()}';
    final Map<String, dynamic> created = <String, dynamic>{
      ...payload,
      '_id': newId,
      'createdAt': now,
      'updatedAt': now,
    };

    clients.add(created);
    await box.put(_clientsKey, clients);
    return _deepCopyMap(created);
  }

  static Future<void> deleteClient(String clientId) async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();

    final List<Map<String, dynamic>> clients = _asMapList(box.get(_clientsKey));
    clients.removeWhere((item) => _asString(item['_id']) == clientId);
    await box.put(_clientsKey, clients);

    final List<Map<String, dynamic>> rosters = _asMapList(box.get(_rostersKey));
    for (final Map<String, dynamic> roster in rosters) {
      final List<Map<String, dynamic>> rosterClients = _asMapList(
        roster['clients'],
      );
      rosterClients.removeWhere(
        (item) => _asString(item['clientId']) == clientId,
      );
      roster['clients'] = rosterClients;
      roster['updatedAt'] = _nowIso();
    }
    await box.put(_rostersKey, rosters);
  }

  static Future<Map<String, dynamic>> upsertGuard({
    required Map<String, dynamic> payload,
    String? guardId,
  }) async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    final List<Map<String, dynamic>> guards = _asMapList(box.get(_guardsKey));
    final String now = _nowIso();

    if (_asString(guardId).trim().isNotEmpty) {
      final String id = _asString(guardId).trim();
      final int index = guards.indexWhere(
        (item) => _asString(item['_id']) == id,
      );
      if (index >= 0) {
        final Map<String, dynamic> updated = <String, dynamic>{
          ...guards[index],
          ...payload,
          '_id': id,
          'updatedAt': now,
        };
        guards[index] = updated;
        await box.put(_guardsKey, guards);
        return _deepCopyMap(updated);
      }
    }

    final String newId = 'guard_${DateTime.now().microsecondsSinceEpoch}';
    final Map<String, dynamic> created = <String, dynamic>{
      ...payload,
      '_id': newId,
      'block': false,
      'verified': false,
      'complaints': <Map<String, dynamic>>[],
      'createdAt': now,
      'updatedAt': now,
    };

    guards.add(created);
    await box.put(_guardsKey, guards);
    return _deepCopyMap(created);
  }

  static Future<void> deleteGuard(String guardId) async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();

    final List<Map<String, dynamic>> guards = _asMapList(box.get(_guardsKey));
    guards.removeWhere((item) => _asString(item['_id']) == guardId);
    await box.put(_guardsKey, guards);

    final List<Map<String, dynamic>> rosters = _asMapList(box.get(_rostersKey));
    for (final Map<String, dynamic> roster in rosters) {
      for (final Map<String, dynamic> rosterClient in _asMapList(
        roster['clients'],
      )) {
        for (final Map<String, dynamic> dateItem in _asMapList(
          rosterClient['dates'],
        )) {
          final List<Map<String, dynamic>> assignments = _asMapList(
            dateItem['assignments'],
          );
          assignments.removeWhere((a) => _asString(a['guardId']) == guardId);
          dateItem['assignments'] = assignments;
        }
      }
      roster['updatedAt'] = _nowIso();
    }
    await box.put(_rostersKey, rosters);
  }

  static Future<Map<String, dynamic>?> _updateGuard(
    String guardId,
    Map<String, dynamic> Function(Map<String, dynamic> guard) updater,
  ) async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    final List<Map<String, dynamic>> guards = _asMapList(box.get(_guardsKey));
    final int index = guards.indexWhere(
      (item) => _asString(item['_id']) == guardId,
    );
    if (index < 0) {
      return null;
    }

    final Map<String, dynamic> updated = updater(guards[index]);
    updated['updatedAt'] = _nowIso();
    guards[index] = updated;
    await box.put(_guardsKey, guards);
    return _deepCopyMap(updated);
  }

  static Future<Map<String, dynamic>?> toggleGuardBlock(String guardId) async {
    return _updateGuard(guardId, (guard) {
      final bool current = guard['block'] == true;
      return <String, dynamic>{...guard, 'block': !current};
    });
  }

  static Future<Map<String, dynamic>?> toggleGuardVerified(
    String guardId,
  ) async {
    return _updateGuard(guardId, (guard) {
      final bool current = guard['verified'] == true;
      return <String, dynamic>{...guard, 'verified': !current};
    });
  }

  static Future<Map<String, dynamic>?> toggleGuardDocumentVerification(
    String guardId,
    String field,
  ) async {
    return _updateGuard(guardId, (guard) {
      final Map<String, dynamic> document = guard[field] is Map
          ? Map<String, dynamic>.from(guard[field] as Map)
          : <String, dynamic>{};
      final bool current = document['verified'] == true;
      document['verified'] = !current;
      return <String, dynamic>{...guard, field: document};
    });
  }

  static Future<Map<String, dynamic>?> addGuardComplaint(
    String guardId, {
    required String description,
    required String severity,
    required DateTime date,
  }) async {
    return _updateGuard(guardId, (guard) {
      final List<Map<String, dynamic>> complaints = _asMapList(
        guard['complaints'],
      );
      complaints.add(<String, dynamic>{
        'description': description,
        'severity': severity,
        'date': date.toUtc().toIso8601String(),
        'resolved': false,
      });
      return <String, dynamic>{...guard, 'complaints': complaints};
    });
  }

  static Future<Map<String, dynamic>> upsertRoster({
    required Map<String, dynamic> payload,
    String? rosterId,
  }) async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    final List<Map<String, dynamic>> rosters = _asMapList(box.get(_rostersKey));
    final List<Map<String, dynamic>> clients = _asMapList(box.get(_clientsKey));
    final List<Map<String, dynamic>> guards = _asMapList(box.get(_guardsKey));

    final Map<String, String> clientNameById = <String, String>{
      for (final Map<String, dynamic> c in clients)
        _asString(c['_id']): _asString(c['name']),
    };
    final Map<String, String> guardNameById = <String, String>{
      for (final Map<String, dynamic> g in guards)
        _asString(g['_id']): _asString(g['name']),
    };

    final List<Map<String, dynamic>> payloadClients = _asMapList(
      payload['clients'],
    );
    final List<Map<String, dynamic>> rosterClients = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> payloadClient in payloadClients) {
      final String clientId = _asString(payloadClient['clientId']).trim();
      if (clientId.isEmpty) {
        continue;
      }

      final List<Map<String, dynamic>> dates = <Map<String, dynamic>>[];
      for (final Map<String, dynamic> dateItem in _asMapList(
        payloadClient['dates'],
      )) {
        final String date = _asString(dateItem['date']).trim();
        if (date.isEmpty) {
          continue;
        }

        final List<Map<String, dynamic>> assignments = <Map<String, dynamic>>[];
        for (final Map<String, dynamic> assignment in _asMapList(
          dateItem['assignments'],
        )) {
          final String guardId = _asString(assignment['guardId']).trim();
          if (guardId.isEmpty) {
            continue;
          }
          assignments.add(<String, dynamic>{
            'guardId': guardId,
            'guardName': guardNameById[guardId] ?? '',
            'checkInTime': _asString(assignment['checkInTime']).trim(),
          });
        }

        dates.add(<String, dynamic>{'date': date, 'assignments': assignments});
      }

      rosterClients.add(<String, dynamic>{
        'clientId': clientId,
        'name': clientNameById[clientId] ?? '',
        'dates': dates,
      });
    }

    final String now = _nowIso();

    if (_asString(rosterId).trim().isNotEmpty) {
      final String id = _asString(rosterId).trim();
      final int index = rosters.indexWhere(
        (item) => _asString(item['_id']) == id,
      );
      if (index >= 0) {
        final Map<String, dynamic> updated = <String, dynamic>{
          ...rosters[index],
          'startDate': _asString(payload['startDate']).trim(),
          'endDate': _asString(payload['endDate']).trim(),
          'clients': rosterClients,
          'updatedAt': now,
        };
        rosters[index] = updated;
        await box.put(_rostersKey, rosters);
        return _deepCopyMap(updated);
      }
    }

    final Map<String, dynamic> created = <String, dynamic>{
      '_id': 'roster_${DateTime.now().microsecondsSinceEpoch}',
      'startDate': _asString(payload['startDate']).trim(),
      'endDate': _asString(payload['endDate']).trim(),
      'clients': rosterClients,
      'createdAt': now,
      'updatedAt': now,
    };
    rosters.add(created);
    await box.put(_rostersKey, rosters);
    return _deepCopyMap(created);
  }

  static Future<Map<String, dynamic>> getAttendanceReport({
    required String startDate,
    required String endDate,
    String? guardId,
  }) async {
    await ensureSeeded();

    final DateTime start = _asDate(startDate) ?? DateTime.now();
    final DateTime end = _asDate(endDate) ?? DateTime.now();

    final List<Map<String, dynamic>> guards = await getGuards();
    final List<Map<String, dynamic>> clients = await getClients();
    final List<Map<String, dynamic>> rosters = await getRosters();

    if (guards.isEmpty) {
      return <String, dynamic>{
        'guard': <String, dynamic>{},
        'clients': <Map<String, dynamic>>[],
        'insights': <String, dynamic>{'totalHours': 0, 'totalShifts': 0},
      };
    }

    final Map<String, dynamic> guard = guardId == null || guardId.trim().isEmpty
        ? guards.first
        : guards.firstWhere(
            (g) => _asString(g['_id']).trim() == guardId.trim(),
            orElse: () => guards.first,
          );
    final String resolvedGuardId = _asString(guard['_id']).trim();

    final Map<String, Map<String, dynamic>> clientById =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> c in clients) _asString(c['_id']): c,
        };

    final Map<String, List<Map<String, dynamic>>> shiftsByClientId =
        <String, List<Map<String, dynamic>>>{};

    for (final Map<String, dynamic> roster in rosters) {
      final List<Map<String, dynamic>> rosterClients = _asMapList(
        roster['clients'],
      );
      for (final Map<String, dynamic> rosterClient in rosterClients) {
        final String clientId = _asString(rosterClient['clientId']).trim();
        if (clientId.isEmpty) {
          continue;
        }

        for (final Map<String, dynamic> dateItem in _asMapList(
          rosterClient['dates'],
        )) {
          final String dateRaw = _asString(dateItem['date']).trim();
          final DateTime? date = _asDate(dateRaw);
          if (date == null) {
            continue;
          }

          final DateTime normalizedDate = DateTime(
            date.year,
            date.month,
            date.day,
          );
          if (normalizedDate.isBefore(
                DateTime(start.year, start.month, start.day),
              ) ||
              normalizedDate.isAfter(DateTime(end.year, end.month, end.day))) {
            continue;
          }

          for (final Map<String, dynamic> assignment in _asMapList(
            dateItem['assignments'],
          )) {
            final String assignmentGuardId = _asString(
              assignment['guardId'],
            ).trim();
            if (assignmentGuardId != resolvedGuardId) {
              continue;
            }

            final String checkInTime =
                _asString(assignment['checkInTime']).trim().isEmpty
                ? '09:00'
                : _asString(assignment['checkInTime']).trim();

            final DateTime checkInAt =
                DateTime.tryParse(
                  '${_dateKey(normalizedDate)}T$checkInTime:00',
                ) ??
                DateTime(
                  normalizedDate.year,
                  normalizedDate.month,
                  normalizedDate.day,
                  9,
                );
            final DateTime checkOutAt = checkInAt.add(const Duration(hours: 8));
            const double hours = 8;
            final double payPerHour = (guard['defaultPay'] is num)
                ? (guard['defaultPay'] as num).toDouble()
                : 0;
            final double pay = payPerHour * hours;

            shiftsByClientId.putIfAbsent(
              clientId,
              () => <Map<String, dynamic>>[],
            );
            shiftsByClientId[clientId]!.add(<String, dynamic>{
              'shiftId': 'shift_${checkInAt.millisecondsSinceEpoch}_$clientId',
              'start': checkInAt.toUtc().toIso8601String(),
              'checkInAt': checkInAt.toUtc().toIso8601String(),
              'checkOutAt': checkOutAt.toUtc().toIso8601String(),
              'hours': hours,
              'roundOffHours': hours,
              'payPerHour': payPerHour,
              'pay': pay,
              'checkInLocation': _asString(
                clientById[clientId]?['locationUrl'],
              ),
              'checkOutLocation': _asString(
                clientById[clientId]?['locationUrl'],
              ),
              'clientLocationUrl': _asString(
                clientById[clientId]?['locationUrl'],
              ),
              'note': '',
            });
          }
        }
      }
    }

    final List<Map<String, dynamic>> reportClients = <Map<String, dynamic>>[];
    for (final MapEntry<String, List<Map<String, dynamic>>> entry
        in shiftsByClientId.entries) {
      final String clientId = entry.key;
      final Map<String, dynamic> client =
          clientById[clientId] ?? <String, dynamic>{};
      final List<Map<String, dynamic>> shifts = entry.value;
      final double totalHours = shifts.fold<double>(
        0,
        (sum, shift) => sum + (shift['roundOffHours'] as double? ?? 0),
      );
      final double totalPay = shifts.fold<double>(
        0,
        (sum, shift) => sum + (shift['pay'] as double? ?? 0),
      );
      reportClients.add(<String, dynamic>{
        'clientId': clientId,
        'clientName': _asString(client['name']),
        'address': _asString(client['address']),
        'locationUrl': _asString(client['locationUrl']),
        'totalShifts': shifts.length,
        'totalHours': totalHours,
        'totalPay': totalPay,
        'shifts': shifts,
      });
    }

    final double totalHours = reportClients.fold<double>(
      0,
      (sum, c) => sum + ((c['totalHours'] as double?) ?? 0),
    );
    final int totalShifts = reportClients.fold<int>(
      0,
      (sum, c) => sum + ((c['totalShifts'] as int?) ?? 0),
    );
    final double totalPay = reportClients.fold<double>(
      0,
      (sum, c) => sum + ((c['totalPay'] as double?) ?? 0),
    );

    return <String, dynamic>{
      'guard': <String, dynamic>{
        'guardId': _asString(guard['_id']),
        'name': _asString(guard['name']),
        'phone': _asString(guard['phone']),
        'photo': _asString(guard['photo']),
        'emiratesIdVerified': guard['emiratesId'] is Map
            ? (guard['emiratesId']['verified'] == true)
            : false,
        'passportVerified': guard['passport'] is Map
            ? (guard['passport']['verified'] == true)
            : false,
        'siraVerified': guard['sira'] is Map
            ? (guard['sira']['verified'] == true)
            : false,
      },
      'clients': reportClients,
      'insights': <String, dynamic>{
        'totalHours': totalHours,
        'totalShifts': totalShifts,
        'totalPay': totalPay,
      },
    };
  }

  static Future<Map<String, dynamic>> getAttendanceReportForGuard({
    required String guardId,
    required String startDate,
    required String endDate,
  }) {
    return getAttendanceReport(
      startDate: startDate,
      endDate: endDate,
      guardId: guardId,
    );
  }

  static Future<void> deleteRoster(String rosterId) async {
    await ensureSeeded();
    final Box<dynamic> box = await _box();
    final List<Map<String, dynamic>> rosters = _asMapList(box.get(_rostersKey));
    rosters.removeWhere((item) => _asString(item['_id']) == rosterId);
    await box.put(_rostersKey, rosters);
  }
}
