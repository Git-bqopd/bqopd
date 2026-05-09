/// Represents a Thursday-Sunday convention week block.
class ConWeek {
  final DateTime startDate;
  final DateTime endDate;
  final String displayString;

  ConWeek({
    required this.startDate,
    required this.endDate,
    required this.displayString,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ConWeek &&
              runtimeType == other.runtimeType &&
              startDate == other.startDate &&
              endDate == other.endDate;

  @override
  int get hashCode => startDate.hashCode ^ endDate.hashCode;
}

/// Generates a list of 52 [ConWeek] objects representing Thursday-Sunday date ranges.
List<ConWeek> generateConWeeks(String startMonth, String startYear) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  int monthIndex = months.indexOf(startMonth) + 1;
  if (monthIndex == 0) monthIndex = 1;

  int year = int.tryParse(startYear) ?? DateTime.now().year;

  DateTime firstDayOfMonth = DateTime(year, monthIndex, 1);

  int daysToThursday = (4 - firstDayOfMonth.weekday) % 7;
  if (daysToThursday < 0) daysToThursday += 7;

  DateTime currentThursday = firstDayOfMonth.add(Duration(days: daysToThursday));

  List<ConWeek> weeks = [];

  for (int i = 0; i < 52; i++) {
    DateTime currentSunday = currentThursday.add(const Duration(days: 3));

    String startMonthStr = months[currentThursday.month - 1];
    String endMonthStr = months[currentSunday.month - 1];

    String display;
    if (currentThursday.month == currentSunday.month) {
      display = '$startMonthStr ${currentThursday.day} - ${currentSunday.day}';
    } else {
      display = '$startMonthStr ${currentThursday.day} - $endMonthStr ${currentSunday.day}';
    }

    weeks.add(ConWeek(
      startDate: currentThursday,
      endDate: currentSunday,
      displayString: display,
    ));

    currentThursday = currentThursday.add(const Duration(days: 7));
  }

  return weeks;
}