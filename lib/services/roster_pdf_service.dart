import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class RosterPdfAssignment {
  const RosterPdfAssignment({
    required this.guardName,
    required this.checkInTime,
  });

  final String guardName;
  final String checkInTime;
}

class RosterPdfClient {
  const RosterPdfClient({required this.name, required this.assignmentsByDate});

  final String name;
  final Map<String, List<RosterPdfAssignment>> assignmentsByDate;
}

class _RosterPdfRow {
  const _RosterPdfRow({
    required this.clientName,
    required this.time,
    required this.venueColor,
    required this.rowHeight,
    required this.showIdentity,
    required this.isFirstSegment,
    required this.segmentAssignmentsByDate,
  });

  final String clientName;
  final String time;
  final PdfColor venueColor;
  final double rowHeight;
  final bool showIdentity;
  final bool isFirstSegment;
  final Map<String, List<RosterPdfAssignment>> segmentAssignmentsByDate;

  _RosterPdfRow copyWith({bool? showIdentity}) {
    return _RosterPdfRow(
      clientName: clientName,
      time: time,
      venueColor: venueColor,
      rowHeight: rowHeight,
      showIdentity: showIdentity ?? this.showIdentity,
      isFirstSegment: isFirstSegment,
      segmentAssignmentsByDate: segmentAssignmentsByDate,
    );
  }
}

class RosterPdfService {
  RosterPdfService._();

  static const int _assignmentsPerSegment = 8;
  static const double _tableHeaderHeight = 24;
  static const double _firstPageTableHeightBudget = 430;
  static const double _otherPageTableHeightBudget = 520;

  static Future<void> shareRosterPdf({
    required DateTime startDate,
    required DateTime endDate,
    required List<DateTime> dateRange,
    required List<RosterPdfClient> clients,
    String logoAssetPath = 'assets/LogoNoBg.png',
    double logoWidth = 60,
    String? filename,
  }) async {
    final ByteData logoData = await rootBundle.load(logoAssetPath);
    final Uint8List logoBytes = logoData.buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes);

    final pw.Document doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
        // The default max pages in MultiPage is low for large rosters.
        // Increase it to avoid TooManyPagesException without changing layout.
        maxPages: 500,
        build: (_) {
          final List<_RosterPdfRow> tableRows = _buildRowsForTable(
            clients: clients,
            dateRange: dateRange,
          );
          final List<List<_RosterPdfRow>> pages = _paginateRows(tableRows);

          final List<pw.Widget> content = <pw.Widget>[
            pw.Center(
              child: pw.Image(
                logoImage,
                width: logoWidth,
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'Guard Roster',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Period: ${_dateKey(startDate)} to ${_dateKey(endDate)}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            pw.SizedBox(height: 7),
            _buildPdfRosterTable(
              dataRows: pages.isNotEmpty ? pages.first : <_RosterPdfRow>[],
              dateRange: dateRange,
            ),
          ];

          if (pages.length > 1) {
            for (int pageIndex = 1; pageIndex < pages.length; pageIndex++) {
              content.add(pw.NewPage());
              content.add(
                _buildPdfRosterTable(
                  dataRows: pages[pageIndex],
                  dateRange: dateRange,
                ),
              );
            }
          }

          return content;
        },
      ),
    );

    final Uint8List bytes = await doc.save();
    final String outFileName =
        filename ?? 'roster_${_dateKey(startDate)}_to_${_dateKey(endDate)}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: outFileName);
  }

  static String _monthName(int month) {
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

  static String _dateKey(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _pdfDateHeader(DateTime date) {
    const List<String> names = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final String dayName = names[date.weekday - 1].toUpperCase();
    return '$dayName ${date.day.toString().padLeft(2, '0')} ${_monthName(date.month).toUpperCase()}';
  }

  static String _primaryTimeForClient(RosterPdfClient client) {
    for (final List<RosterPdfAssignment> dateRoster
        in client.assignmentsByDate.values) {
      for (final RosterPdfAssignment assignment in dateRoster) {
        final String checkIn = assignment.checkInTime.trim();
        if (checkIn.isNotEmpty) {
          return checkIn.toUpperCase();
        }
      }
    }
    return '--:--';
  }

  static String _assignmentTime(RosterPdfAssignment assignment) {
    final String value = assignment.checkInTime.trim();
    return value.isEmpty ? '--:--' : value;
  }

  static double _rowHeightForClient(
    RosterPdfClient client,
    List<DateTime> dateRange,
    int segmentIndex,
  ) {
    const double minHeight = 24;
    const double chipHeight = 22;
    const double chipSpacing = 3;
    const double verticalPadding = 4;

    int maxSegmentAssignments = 0;
    for (final DateTime date in dateRange) {
      final int count =
          (client.assignmentsByDate[_dateKey(date)] ?? <RosterPdfAssignment>[])
              .length;
      final int start = segmentIndex * _assignmentsPerSegment;
      final int end = math.min(start + _assignmentsPerSegment, count);
      final int segmentCount = end > start ? end - start : 0;
      if (segmentCount > maxSegmentAssignments) {
        maxSegmentAssignments = segmentCount;
      }
    }

    if (maxSegmentAssignments <= 0) {
      return minHeight;
    }

    final double chipsHeight =
        (maxSegmentAssignments * chipHeight) +
        ((maxSegmentAssignments - 1) * chipSpacing) +
        (verticalPadding * 2);
    return math.max(minHeight, chipsHeight);
  }

  static int _segmentCountForClient(
    RosterPdfClient client,
    List<DateTime> dateRange,
  ) {
    int maxAssignments = 0;
    for (final DateTime date in dateRange) {
      final int count =
          (client.assignmentsByDate[_dateKey(date)] ?? <RosterPdfAssignment>[])
              .length;
      if (count > maxAssignments) {
        maxAssignments = count;
      }
    }
    if (maxAssignments <= 0) {
      return 1;
    }
    return (maxAssignments / _assignmentsPerSegment).ceil();
  }

  static List<RosterPdfAssignment> _segmentAssignmentsForCell(
    List<RosterPdfAssignment> assignments,
    int segmentIndex,
  ) {
    final int start = segmentIndex * _assignmentsPerSegment;
    if (start >= assignments.length) {
      return <RosterPdfAssignment>[];
    }
    final int end = math.min(
      start + _assignmentsPerSegment,
      assignments.length,
    );
    return assignments.sublist(start, end);
  }

  static PdfColor _pdfColor(int r, int g, int b) {
    return PdfColor.fromInt((0xFF << 24) | (r << 16) | (g << 8) | b);
  }

  static pw.Widget _pdfCell({
    required pw.Widget child,
    PdfColor? backgroundColor,
    double? height,
    pw.Alignment alignment = pw.Alignment.topLeft,
    pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(4),
  }) {
    return pw.Container(
      height: height,
      alignment: alignment,
      padding: padding,
      decoration: pw.BoxDecoration(
        color: backgroundColor,
        border: pw.Border.all(color: _pdfColor(203, 213, 225), width: 0.6),
      ),
      child: child,
    );
  }

  static pw.Widget _pdfTextCell({
    required String text,
    PdfColor? backgroundColor,
    PdfColor? textColor,
    bool isBold = false,
    double fontSize = 8,
    double? height,
    pw.Alignment alignment = pw.Alignment.topLeft,
    pw.TextAlign textAlign = pw.TextAlign.left,
    pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(4),
  }) {
    return _pdfCell(
      backgroundColor: backgroundColor,
      height: height,
      alignment: alignment,
      padding: padding,
      child: pw.Text(
        text,
        textAlign: textAlign,
        style: pw.TextStyle(
          fontSize: fontSize,
          color: textColor ?? PdfColors.black,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _pdfAssignmentChip(RosterPdfAssignment assignment) {
    return pw.Container(
      height: 22,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
          colors: <PdfColor>[
            _pdfColor(243, 244, 246),
            _pdfColor(229, 231, 235),
          ],
        ),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _pdfColor(209, 213, 219), width: 0.4),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Container(
            height: 9,
            alignment: pw.Alignment.center,
            child: pw.Text(
              assignment.guardName.toUpperCase(),
              maxLines: 1,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 6.0,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Container(
            height: 8,
            alignment: pw.Alignment.center,
            child: pw.Text(
              _assignmentTime(assignment),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 5.9,
                fontWeight: pw.FontWeight.bold,
                color: _pdfColor(71, 85, 105),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<_RosterPdfRow> _buildRowsForTable({
    required List<RosterPdfClient> clients,
    required List<DateTime> dateRange,
  }) {
    final List<PdfColor> venueColors = <PdfColor>[
      _pdfColor(219, 234, 254),
      _pdfColor(220, 252, 231),
      _pdfColor(255, 237, 213),
      _pdfColor(207, 250, 254),
      _pdfColor(243, 232, 255),
      _pdfColor(252, 231, 243),
      _pdfColor(224, 231, 255),
      _pdfColor(209, 250, 229),
    ];

    final List<_RosterPdfRow> rows = <_RosterPdfRow>[];

    for (int clientIdx = 0; clientIdx < clients.length; clientIdx++) {
      final RosterPdfClient client = clients[clientIdx];
      final String clientName = client.name.toUpperCase();
      final PdfColor venueColor = venueColors[clientIdx % venueColors.length];
      final String time = _primaryTimeForClient(client);
      final int segmentCount = _segmentCountForClient(client, dateRange);

      for (int segmentIndex = 0; segmentIndex < segmentCount; segmentIndex++) {
        final bool isFirstSegment = segmentIndex == 0;
        final double rowHeight = _rowHeightForClient(
          client,
          dateRange,
          segmentIndex,
        );

        final Map<String, List<RosterPdfAssignment>> segmentByDate =
            <String, List<RosterPdfAssignment>>{};

        for (final DateTime date in dateRange) {
          final String dateKey = _dateKey(date);
          final List<RosterPdfAssignment> assignments =
              client.assignmentsByDate[dateKey] ?? <RosterPdfAssignment>[];
          segmentByDate[dateKey] = _segmentAssignmentsForCell(
            assignments,
            segmentIndex,
          );
        }

        rows.add(
          _RosterPdfRow(
            clientName: clientName,
            time: time,
            venueColor: venueColor,
            rowHeight: rowHeight,
            showIdentity: isFirstSegment,
            isFirstSegment: isFirstSegment,
            segmentAssignmentsByDate: segmentByDate,
          ),
        );
      }
    }

    return rows;
  }

  static List<List<_RosterPdfRow>> _paginateRows(List<_RosterPdfRow> rows) {
    if (rows.isEmpty) {
      return <List<_RosterPdfRow>>[];
    }

    final List<List<_RosterPdfRow>> pages = <List<_RosterPdfRow>>[];
    int cursor = 0;
    bool firstPage = true;

    while (cursor < rows.length) {
      final double pageBudget = firstPage
          ? _firstPageTableHeightBudget
          : _otherPageTableHeightBudget;
      double usedHeight = _tableHeaderHeight;
      final List<_RosterPdfRow> pageRows = <_RosterPdfRow>[];

      while (cursor < rows.length) {
        final _RosterPdfRow row = rows[cursor];
        final bool willOverflow =
            pageRows.isNotEmpty && (usedHeight + row.rowHeight > pageBudget);
        if (willOverflow) {
          break;
        }
        pageRows.add(row);
        usedHeight += row.rowHeight;
        cursor += 1;
      }

      if (pageRows.isEmpty) {
        pageRows.add(rows[cursor]);
        cursor += 1;
      }

      final _RosterPdfRow firstRow = pageRows.first;
      if (!firstRow.showIdentity) {
        pageRows[0] = firstRow.copyWith(showIdentity: true);
      }

      pages.add(pageRows);
      firstPage = false;
    }

    return pages;
  }

  static pw.Widget _buildPdfRosterTable({
    required List<_RosterPdfRow> dataRows,
    required List<DateTime> dateRange,
  }) {
    final PdfColor headerColor = _pdfColor(209, 213, 219);
    final PdfColor headerTextColor = _pdfColor(31, 41, 55);
    final PdfColor timeColor = _pdfColor(243, 244, 246);
    final PdfColor naColor = _pdfColor(254, 243, 199);

    final Map<int, pw.TableColumnWidth> columnWidths =
        <int, pw.TableColumnWidth>{
          0: pw.FixedColumnWidth(30 * PdfPageFormat.mm),
          1: pw.FixedColumnWidth(20 * PdfPageFormat.mm),
        };
    for (int i = 0; i < dateRange.length; i++) {
      columnWidths[i + 2] = const pw.FlexColumnWidth();
    }

    final List<pw.TableRow> headerRows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        children: <pw.Widget>[
          _pdfTextCell(
            text: 'VENUES',
            backgroundColor: headerColor,
            textColor: headerTextColor,
            isBold: true,
            fontSize: 9,
            alignment: pw.Alignment.centerLeft,
            height: 24,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          _pdfTextCell(
            text: 'TIME',
            backgroundColor: headerColor,
            textColor: headerTextColor,
            isBold: true,
            fontSize: 9,
            alignment: pw.Alignment.center,
            textAlign: pw.TextAlign.center,
            height: 24,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          ...dateRange.map((date) {
            return _pdfTextCell(
              text: _pdfDateHeader(date),
              backgroundColor: headerColor,
              textColor: headerTextColor,
              isBold: true,
              fontSize: 7.6,
              alignment: pw.Alignment.center,
              textAlign: pw.TextAlign.center,
              height: 24,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
            );
          }),
        ],
      ),
    ];

    final List<pw.TableRow> bodyRows = <pw.TableRow>[];

    for (final _RosterPdfRow row in dataRows) {
      bodyRows.add(
        pw.TableRow(
          children: <pw.Widget>[
            _pdfTextCell(
              text: row.clientName,
              backgroundColor: row.venueColor,
              textColor: _pdfColor(31, 41, 55),
              isBold: true,
              fontSize: 7.6,
              alignment: pw.Alignment.centerLeft,
              height: row.rowHeight,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
            ),
            _pdfTextCell(
              text: row.time,
              backgroundColor: timeColor,
              textColor: _pdfColor(31, 41, 55),
              fontSize: 7.6,
              isBold: true,
              alignment: pw.Alignment.center,
              textAlign: pw.TextAlign.center,
              height: row.rowHeight,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
            ),
            ...dateRange.map((date) {
              final String dateKey = _dateKey(date);
              final List<RosterPdfAssignment> segmentAssignments =
                  row.segmentAssignmentsByDate[dateKey] ??
                  <RosterPdfAssignment>[];

              if (segmentAssignments.isEmpty) {
                return _pdfTextCell(
                  text: 'N/A',
                  backgroundColor: naColor,
                  textColor: _pdfColor(55, 65, 81),
                  isBold: true,
                  fontSize: 7.4,
                  alignment: pw.Alignment.center,
                  textAlign: pw.TextAlign.center,
                  height: row.rowHeight,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                );
              }

              return _pdfCell(
                backgroundColor: PdfColors.white,
                height: row.rowHeight,
                alignment: pw.Alignment.topLeft,
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: <pw.Widget>[
                    for (int i = 0; i < segmentAssignments.length; i++)
                      pw.Padding(
                        padding: pw.EdgeInsets.only(
                          bottom: i == segmentAssignments.length - 1 ? 0 : 3,
                        ),
                        child: _pdfAssignmentChip(segmentAssignments[i]),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    final List<pw.TableRow> allRows = <pw.TableRow>[...headerRows, ...bodyRows];

    return pw.Table(
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: allRows,
    );
  }
}
