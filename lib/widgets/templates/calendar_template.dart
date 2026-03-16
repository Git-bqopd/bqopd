import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// --- MODELS ---

class CalEvent {
  final String name;
  final String handle;
  final String location;
  final bool isHighlighted;
  final bool bqopdAttending;

  const CalEvent({
    required this.name,
    required this.handle,
    required this.location,
    this.isHighlighted = false,
    this.bqopdAttending = false,
  });
}

class CalWeek {
  final List<String> dates; // Thu, Fri, Sat, Sun
  final List<bool> highlightedDates;
  final CalEvent? event;

  const CalWeek({
    required this.dates,
    this.highlightedDates = const [false, false, false, false],
    this.event,
  });
}

class CalMonth {
  final String name;
  final List<CalWeek> weeks;

  const CalMonth({required this.name, required this.weeks});
}

class CalEventData {
  final String id;
  final String name;
  final String handle;
  final String location;
  final String month;
  final String startDay;
  final bool isHighlighted;
  final bool bqopdAttending;

  CalEventData({
    required this.id,
    required this.name,
    required this.handle,
    required this.location,
    required this.month,
    required this.startDay,
    required this.isHighlighted,
    required this.bqopdAttending,
  });

  factory CalEventData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CalEventData(
      id: doc.id,
      name: data['name'] ?? '',
      handle: data['handle'] ?? '',
      location: data['location'] ?? '',
      month: data['month'] ?? '',
      startDay: data['startDay'] ?? '',
      isHighlighted: data['isHighlighted'] ?? false,
      bqopdAttending: data['bqopdAttending'] ?? false,
    );
  }
}

// --- CALENDAR LOGIC UTILS ---

class CalendarDateUtils {
  static List<CalMonth> generateFolioDates(int startMonth, int startYear) {
    List<CalMonth> months = [];
    DateTime current = DateTime(startYear, startMonth, 1);

    for (int i = 0; i < 12; i++) {
      int month = current.month;
      int year = current.year;
      String monthName = DateFormat('MMMM').format(current);

      List<CalWeek> weeks = [];
      DateTime firstDay = DateTime(year, month, 1);
      DateTime lastDay = DateTime(year, month + 1, 0);

      for (int d = 1; d <= lastDay.day; d++) {
        DateTime day = DateTime(year, month, d);
        if (day.weekday == DateTime.thursday) {
          List<String> dates = [];
          for (int offset = 0; offset < 4; offset++) {
            DateTime actual = day.add(Duration(days: offset));
            dates.add("${actual.day}");
          }
          weeks.add(CalWeek(dates: dates));
        }
      }

      months.add(CalMonth(name: monthName, weeks: weeks));
      current = DateTime(year, month + 1, 1);
    }
    return months;
  }
}

class CalendarDataBuilder {
  static List<CalMonth> buildPage(List<CalEventData> events, List<CalMonth> folioBase, bool isLeft) {
    final range = isLeft ? folioBase.sublist(0, 6) : folioBase.sublist(6, 12);
    return _merge(range, events);
  }

  static List<CalMonth> _merge(List<CalMonth> base, List<CalEventData> events) {
    return base.map((m) {
      final newWeeks = m.weeks.map((w) {
        final evt = events.where((e) => e.month == m.name && e.startDay == w.dates[0]).firstOrNull;
        if (evt != null) {
          return CalWeek(
            dates: w.dates,
            highlightedDates: evt.isHighlighted ? [true, true, true, true] : w.highlightedDates,
            event: CalEvent(
              name: evt.name,
              handle: evt.handle,
              location: evt.location,
              isHighlighted: evt.isHighlighted,
              bqopdAttending: evt.bqopdAttending,
            ),
          );
        }
        return w;
      }).toList();
      return CalMonth(name: m.name, weeks: newWeeks);
    }).toList();
  }
}

// --- RENDERERS ---

class CalendarPageRenderer extends StatelessWidget {
  final bool isLeft;
  final String folioId;

  const CalendarPageRenderer({super.key, required this.isLeft, required this.folioId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('fanzines').doc(folioId).snapshots(),
        builder: (context, folioSnap) {
          if (!folioSnap.hasData) return const Center(child: CircularProgressIndicator());

          final folioData = folioSnap.data!.data() as Map<String, dynamic>? ?? {};
          final startMonth = folioData['startMonth'] ?? 2;
          final startYear = folioData['startYear'] ?? 2026;

          final fullYearBase = CalendarDateUtils.generateFolioDates(startMonth, startYear);

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('conventions')
                .where('folioId', isEqualTo: folioId)
                .snapshots(),
            builder: (context, snapshot) {
              List<CalEventData> events = [];
              if (snapshot.hasData) {
                events = snapshot.data!.docs.map((d) => CalEventData.fromFirestore(d)).toList();
              }

              final months = CalendarDataBuilder.buildPage(events, fullYearBase, isLeft);

              return FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 2000,
                  height: 3200,
                  child: _CalendarPage(months: months),
                ),
              );
            },
          );
        }
    );
  }
}

class CalendarSpreadTemplate extends StatelessWidget {
  final List<CalMonth> leftPageMonths;
  final List<CalMonth> rightPageMonths;

  static const double targetWidth = 4000.0;
  static const double targetHeight = 3200.0;

  const CalendarSpreadTemplate({
    super.key,
    required this.leftPageMonths,
    required this.rightPageMonths,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: targetWidth,
      height: targetHeight,
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _CalendarPage(months: leftPageMonths)),
          Expanded(child: _CalendarPage(months: rightPageMonths)),
        ],
      ),
    );
  }
}

class _CalendarPage extends StatelessWidget {
  final List<CalMonth> months;
  const _CalendarPage({required this.months});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(40.0),
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 12.0)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: months.asMap().entries.map((entry) {
          final isLastMonth = entry.key == months.length - 1;
          return Expanded(
            flex: entry.value.weeks.length,
            child: _MonthColumn(month: entry.value, isLastMonth: isLastMonth),
          );
        }).toList(),
      ),
    );
  }
}

class _MonthColumn extends StatelessWidget {
  final CalMonth month;
  final bool isLastMonth;
  const _MonthColumn({required this.month, required this.isLastMonth});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: isLastMonth ? null : const Border(right: BorderSide(color: Colors.black, width: 8.0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 80,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black, width: 8.0))),
            child: Center(child: Text(month.name, style: const TextStyle(fontFamily: 'Impact', fontSize: 54, fontWeight: FontWeight.bold, letterSpacing: 2.0))),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: month.weeks.asMap().entries.map((entry) {
                final isLastWeek = entry.key == month.weeks.length - 1;
                return Expanded(
                    flex: 1,
                    child: _WeekColumn(week: entry.value, isLastWeekInMonth: isLastWeek)
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekColumn extends StatelessWidget {
  final CalWeek week;
  final bool isLastWeekInMonth;
  const _WeekColumn({required this.week, required this.isLastWeekInMonth});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: isLastWeekInMonth ? null : const Border(right: BorderSide(color: Colors.black, width: 3.0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < 4; i++)
            Container(
              height: 75,
              decoration: BoxDecoration(color: week.highlightedDates[i] ? Colors.black : Colors.white, border: const Border(bottom: BorderSide(color: Colors.black, width: 3.0))),
              child: Center(child: Text(week.dates[i], style: TextStyle(fontFamily: 'Arial', fontSize: 42, fontWeight: FontWeight.w900, color: week.highlightedDates[i] ? Colors.white : Colors.black))),
            ),
          Expanded(child: Container(color: (week.event?.isHighlighted ?? false) ? Colors.black : Colors.white, child: _buildEventContent(week.event))),
        ],
      ),
    );
  }

  Widget _buildEventContent(CalEvent? event) {
    if (event == null) return const SizedBox();
    final textColor = event.isHighlighted ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: RotatedBox(quarterTurns: 1, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Text(event.name, style: TextStyle(fontFamily: 'Arial', fontSize: 48, fontWeight: FontWeight.w900, color: textColor)), const Spacer(), Text(event.handle, style: TextStyle(fontFamily: 'Arial', fontSize: 40, fontWeight: FontWeight.bold, color: textColor)), const Spacer(), Text(event.location, style: TextStyle(fontFamily: 'Arial', fontSize: 40, fontWeight: FontWeight.bold, color: textColor))])))),
        if (event.bqopdAttending)
          Container(
            height: 500,
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: RotatedBox(quarterTurns: 3, child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [ColorFiltered(colorFilter: const ColorFilter.matrix([-1,0,0,0,255,0,-1,0,0,255,0,0,-1,0,255,0,0,0,1,0]), child: Image.asset('assets/logo400.gif', height: 70, fit: BoxFit.contain)), const SizedBox(width: 24), const Text("bqopd will be there", style: TextStyle(fontFamily: 'Arial', fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white))])),
          ),
      ],
    );
  }
}

// --- BASE CALENDAR DEFINITIONS FOR PREVIEWS ---

class CalendarDummyData {
  static List<CalMonth> getLeftPageBase() {
    return [
      const CalMonth(name: "February", weeks: [
        CalWeek(dates: ["30", "31", "1", "2"]),
        CalWeek(dates: ["6", "7", "8", "9"]),
        CalWeek(dates: ["13", "14", "15", "16"]),
        CalWeek(dates: ["20", "21", "22", "23"]),
        CalWeek(dates: ["27", "28", "29", "30"]),
      ]),
      const CalMonth(name: "March", weeks: [
        CalWeek(dates: ["6", "7", "8", "9"]),
        CalWeek(dates: ["13", "14", "15", "16"]),
        CalWeek(dates: ["20", "21", "22", "23"]),
        CalWeek(dates: ["27", "28", "29", "30"]),
      ]),
      const CalMonth(name: "April", weeks: [
        CalWeek(dates: ["3", "4", "5", "6"]),
        CalWeek(dates: ["10", "11", "12", "13"]),
        CalWeek(dates: ["17", "18", "19", "20"]),
        CalWeek(dates: ["24", "25", "26", "27"]),
      ]),
      const CalMonth(name: "May", weeks: [
        CalWeek(dates: ["1", "2", "3", "4"]),
        CalWeek(dates: ["8", "9", "10", "11"]),
        CalWeek(dates: ["15", "16", "17", "18"]),
        CalWeek(dates: ["22", "23", "24", "25"]),
        CalWeek(dates: ["29", "30", "31", "1"]),
      ]),
      const CalMonth(name: "June", weeks: [
        CalWeek(dates: ["5", "6", "7", "8"]),
        CalWeek(dates: ["12", "13", "14", "15"]),
        CalWeek(dates: ["19", "20", "21", "22"]),
        CalWeek(dates: ["26", "27", "28", "29"]),
      ]),
      const CalMonth(name: "July", weeks: [
        CalWeek(dates: ["3", "4", "5", "6"]),
        CalWeek(dates: ["10", "11", "12", "13"]),
        CalWeek(dates: ["17", "18", "19", "20"]),
        CalWeek(dates: ["24", "25", "26", "27"]),
      ]),
    ];
  }

  static List<CalMonth> getRightPageBase() {
    return [
      const CalMonth(name: "August", weeks: [
        CalWeek(dates: ["31", "1", "2", "3"]),
        CalWeek(dates: ["7", "8", "9", "10"]),
        CalWeek(dates: ["14", "15", "16", "17"]),
        CalWeek(dates: ["21", "22", "23", "24"]),
        CalWeek(dates: ["28", "29", "30", "31"]),
      ]),
      const CalMonth(name: "September", weeks: [
        CalWeek(dates: ["4", "5", "6", "7"]),
        CalWeek(dates: ["11", "12", "13", "14"]),
        CalWeek(dates: ["18", "19", "20", "21"]),
        CalWeek(dates: ["25", "26", "27", "28"]),
      ]),
      const CalMonth(name: "October", weeks: [
        CalWeek(dates: ["2", "3", "4", "5"]),
        CalWeek(dates: ["9", "10", "11", "12"]),
        CalWeek(dates: ["16", "17", "18", "19"]),
        CalWeek(dates: ["23", "24", "25", "26"]),
        CalWeek(dates: ["30", "31", "1", "2"]),
      ]),
      const CalMonth(name: "November", weeks: [
        CalWeek(dates: ["6", "7", "8", "9"]),
        CalWeek(dates: ["13", "14", "15", "16"]),
        CalWeek(dates: ["20", "21", "22", "23"]),
        CalWeek(dates: ["27", "28", "29", "30"]),
      ]),
      const CalMonth(name: "December", weeks: [
        CalWeek(dates: ["4", "5", "6", "7"]),
        CalWeek(dates: ["11", "12", "13", "14"]),
        CalWeek(dates: ["18", "19", "20", "21"]),
        CalWeek(dates: ["25", "26", "27", "28"]),
      ]),
      const CalMonth(name: "January", weeks: [
        CalWeek(dates: ["1", "2", "3", "4"]),
        CalWeek(dates: ["8", "9", "10", "11"]),
        CalWeek(dates: ["15", "16", "17", "18"]),
        CalWeek(dates: ["22", "23", "24", "25"]),
      ]),
    ];
  }
}