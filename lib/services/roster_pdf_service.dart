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

class RosterPdfService {
  RosterPdfService._();

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
        build: (_) {
          return <pw.Widget>[
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
            _buildPdfRosterTable(clients: clients, dateRange: dateRange),
          ];
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
  ) {
    const double minHeight = 24;
    const double chipHeight = 22;
    const double chipSpacing = 3;
    const double verticalPadding = 4;

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
      return minHeight;
    }

    final double chipsHeight =
        (maxAssignments * chipHeight) +
        ((maxAssignments - 1) * chipSpacing) +
        (verticalPadding * 2);
    return math.max(minHeight, chipsHeight);
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

  static pw.Widget _buildPdfRosterTable({
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

    final List<pw.TableRow> rows = <pw.TableRow>[
      pw.TableRow(
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

    for (int clientIdx = 0; clientIdx < clients.length; clientIdx++) {
      final RosterPdfClient client = clients[clientIdx];
      final String clientName = client.name.toUpperCase();
      final PdfColor venueColor = venueColors[clientIdx % venueColors.length];
      final String time = _primaryTimeForClient(client);
      final double rowHeight = _rowHeightForClient(client, dateRange);

      rows.add(
        pw.TableRow(
          children: <pw.Widget>[
            _pdfTextCell(
              text: clientName,
              backgroundColor: venueColor,
              textColor: _pdfColor(31, 41, 55),
              isBold: true,
              fontSize: 7.6,
              alignment: pw.Alignment.centerLeft,
              height: rowHeight,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
            ),
            _pdfTextCell(
              text: time,
              backgroundColor: timeColor,
              textColor: _pdfColor(31, 41, 55),
              fontSize: 7.6,
              isBold: true,
              alignment: pw.Alignment.center,
              textAlign: pw.TextAlign.center,
              height: rowHeight,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
            ),
            ...dateRange.map((date) {
              final String dateKey = _dateKey(date);
              final List<RosterPdfAssignment> assignments =
                  client.assignmentsByDate[dateKey] ?? <RosterPdfAssignment>[];

              if (assignments.isEmpty) {
                return _pdfTextCell(
                  text: 'N/A',
                  backgroundColor: naColor,
                  textColor: _pdfColor(55, 65, 81),
                  isBold: true,
                  fontSize: 7.4,
                  alignment: pw.Alignment.center,
                  textAlign: pw.TextAlign.center,
                  height: rowHeight,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                );
              }

              return _pdfCell(
                backgroundColor: PdfColors.white,
                height: rowHeight,
                alignment: pw.Alignment.topLeft,
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: <pw.Widget>[
                    for (int i = 0; i < assignments.length; i++)
                      pw.Padding(
                        padding: pw.EdgeInsets.only(
                          bottom: i == assignments.length - 1 ? 0 : 3,
                        ),
                        child: _pdfAssignmentChip(assignments[i]),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    return pw.Table(
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: rows,
    );
  }
}
