// lib/models/shift_entry.dart

class ShiftEntry {
  final String date; // e.g. "06/04/2026"
  final String startTime; // e.g. "06:48 PM"
  final String endTime;
  final String totalHours;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final String shiftId;

  const ShiftEntry({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.totalHours,
    required this.shiftId,
    this.startLat = 23.0225,
    this.startLng = 72.5714,
    this.endLat = 23.0225,
    this.endLng = 72.5714,
  });
}

/// Grouped model used for the timesheet table
class ShiftGroup {
  final String date;
  final List<ShiftEntry> entries;
  const ShiftGroup({required this.date, required this.entries});
}

// Add below your existing ShiftEntry / ShiftGroup classes

class StaffShiftApiModel {
  final String? shiftId;
  final DateTime? shiftStart;
  final DateTime? shiftEnd;
  final String? shiftStatus;

  const StaffShiftApiModel({
    this.shiftId,
    this.shiftStart,
    this.shiftEnd,
    this.shiftStatus,
  });

  factory StaffShiftApiModel.fromJson(Map<String, dynamic> json) {
    return StaffShiftApiModel(
      shiftId: json['shiftId'] as String?,
      shiftStart: json['shiftStart'] != null
          ? DateTime.tryParse(json['shiftStart'] as String)
          : null,
      shiftEnd: json['shiftEnd'] != null
          ? DateTime.tryParse(json['shiftEnd'] as String)
          : null,
      shiftStatus: json['shiftStatus'] as String?,
    );
  }

  /// Convert to the ShiftEntry shape used by the UI
  ShiftEntry toShiftEntry() {
    final start = shiftStart ?? DateTime(0);
    final end   = shiftEnd   ?? DateTime(0);

    final diff    = end.difference(start);
    final hh      = diff.inHours.abs().toString().padLeft(2, '0');
    final mm      = (diff.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final totHrs  = '$hh:$mm';

    String _fmt(DateTime dt) {
      final h  = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m  = dt.minute.toString().padLeft(2, '0');
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      return '${h.toString().padLeft(2, '0')}:$m $ap';
    }

    String _fmtDate(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}/'
            '${dt.month.toString().padLeft(2, '0')}/'
            '${dt.year}';

    return ShiftEntry(
      date:       _fmtDate(start),
      startTime:  _fmt(start),
      endTime:    _fmt(end),
      totalHours: totHrs,
      shiftId:    shiftId ?? '',
      startLat:   23.0225,
      startLng:   72.5714,
      endLat:     23.0225,
      endLng:     72.5714,
    );
  }
}

List<ShiftGroup> groupShifts(List<ShiftEntry> entries) {
  final Map<String, List<ShiftEntry>> map = {};
  for (final e in entries) {
    map.putIfAbsent(e.date, () => []).add(e);
  }
  return map.entries
      .map((e) => ShiftGroup(date: e.key, entries: e.value))
      .toList();
}
