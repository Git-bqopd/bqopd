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
/// It starts from the first Thursday of the provided [startMonth] and [startYear].
List<ConWeek> generateConWeeks(String startMonth, String startYear) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Find the month index (1-12)
  int monthIndex = months.indexOf(startMonth) + 1;
  if (monthIndex == 0) monthIndex = 1; // Fallback to January if not found

  // Parse the year
  int year = int.tryParse(startYear) ?? DateTime.now().year;

  // Get the first day of that month
  DateTime firstDayOfMonth = DateTime(year, monthIndex, 1);

  // Find the first Thursday.
  // DateTime.weekday: Monday = 1, Tuesday = 2, Wednesday = 3, Thursday = 4.
  int daysToThursday = (DateTime.thursday - firstDayOfMonth.weekday) % 7;
  if (daysToThursday < 0) daysToThursday += 7; // Ensure we always move forward

  DateTime currentThursday = firstDayOfMonth.add(Duration(days: daysToThursday));

  List<ConWeek> weeks = [];

  // Generate 52 weeks
  for (int i = 0; i < 52; i++) {
    // Sunday is 3 days after Thursday
    DateTime currentSunday = currentThursday.add(const Duration(days: 3));

    String startMonthStr = months[currentThursday.month - 1];
    String endMonthStr = months[currentSunday.month - 1];

    String display;
    if (currentThursday.month == currentSunday.month) {
      // e.g., "February 5 - 8"
      display = '$startMonthStr ${currentThursday.day} - ${currentSunday.day}';
    } else {
      // e.g., "February 26 - March 1"
      display = '$startMonthStr ${currentThursday.day} - $endMonthStr ${currentSunday.day}';
    }

    weeks.add(ConWeek(
      startDate: currentThursday,
      endDate: currentSunday,
      displayString: display,
    ));

    // Jump 7 days to the next Thursday
    currentThursday = currentThursday.add(const Duration(days: 7));
  }

  return weeks;
}