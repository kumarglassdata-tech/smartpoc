import 'package:flutter/material.dart';

class ScheduleTaskItem {
  String id;
  String title;
  bool isCompleted;

  ScheduleTaskItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'is_completed': isCompleted,
      };

  factory ScheduleTaskItem.fromJson(Map<String, dynamic> json) =>
      ScheduleTaskItem(
        id: json['id']?.toString() ?? UniqueKey().toString(),
        title: json['title']?.toString() ?? '',
        isCompleted: json['is_completed'] == true,
      );

  ScheduleTaskItem copyWith({String? title, bool? isCompleted}) =>
      ScheduleTaskItem(
        id: id,
        title: title ?? this.title,
        isCompleted: isCompleted ?? this.isCompleted,
      );
}

class ScheduleActivitySlot {
  String id;
  String day; // 'Monday', 'Tuesday', etc.
  String time; // '05:00', '14:00'
  String activity; // 'Waking Up', 'Working', etc.
  int taskCount;
  List<ScheduleTaskItem> tasks;
  String? notes;

  ScheduleActivitySlot({
    required this.id,
    required this.day,
    required this.time,
    required this.activity,
    required this.taskCount,
    required this.tasks,
    this.notes,
  });

  int get completedCount => tasks.where((t) => t.isCompleted).length;
  bool get isAllCompleted => tasks.isNotEmpty && completedCount == tasks.length;

  Color get accentColor {
    final act = activity.toLowerCase();
    if (act.contains('wak') || act.contains('morn') || act.contains('alarm')) {
      return const Color(0xFFFF7043); // Warm orange / sunrise
    } else if (act.contains('bath') || act.contains('shower') || act.contains('wash') || act.contains('dress')) {
      return const Color(0xFF00BCD4); // Cyan / Water
    } else if (act.contains('eat') || act.contains('break') || act.contains('lunch') || act.contains('dinner') || act.contains('meal') || act.contains('cook')) {
      return const Color(0xFFFFA726); // Amber / Food
    } else if (act.contains('transit') || act.contains('travel') || act.contains('drive') || act.contains('commute') || act.contains('bus') || act.contains('walk')) {
      return const Color(0xFF42A5F5); // Blue / Transit
    } else if (act.contains('work') || act.contains('meet') || act.contains('code') || act.contains('study') || act.contains('email') || act.contains('office')) {
      return const Color(0xFFAB47BC); // Purple / Focus
    } else if (act.contains('relax') || act.contains('leisure') || act.contains('read') || act.contains('rest') || act.contains('nap')) {
      return const Color(0xFFEC407A); // Pink / Relaxation
    } else if (act.contains('watch') || act.contains('tv') || act.contains('movie') || act.contains('game')) {
      return const Color(0xFF26A69A); // Mint Teal / Entertainment
    } else if (act.contains('sleep') || act.contains('bed') || act.contains('night')) {
      return const Color(0xFF5C6BC0); // Deep Indigo / Sleep
    } else if (act.contains('gym') || act.contains('exercise') || act.contains('workout') || act.contains('run') || act.contains('sport')) {
      return const Color(0xFF66BB6A); // Fresh Green / Fitness
    }
    return const Color(0xFFE8963C); // Default App Accent
  }

  String get emoji {
    final act = activity.toLowerCase();
    if (act.contains('wak') || act.contains('morn') || act.contains('alarm')) {
      return '🌅';
    } else if (act.contains('bath') || act.contains('shower') || act.contains('wash')) {
      return '🚿';
    } else if (act.contains('eat') || act.contains('break') || act.contains('lunch') || act.contains('dinner') || act.contains('meal')) {
      return '🍽️';
    } else if (act.contains('transit') || act.contains('travel') || act.contains('commute') || act.contains('bus')) {
      return '🚌';
    } else if (act.contains('work') || act.contains('meet') || act.contains('code') || act.contains('study')) {
      return '💼';
    } else if (act.contains('relax') || act.contains('leisure') || act.contains('rest')) {
      return '🛋️';
    } else if (act.contains('watch') || act.contains('tv') || act.contains('movie')) {
      return '📺';
    } else if (act.contains('sleep') || act.contains('bed') || act.contains('night')) {
      return '🌙';
    } else if (act.contains('gym') || act.contains('exercise') || act.contains('workout')) {
      return '💪';
    }
    return '📌';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'time': time,
        'activity': activity,
        'task_count': taskCount,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        if (notes != null) 'notes': notes,
      };

  factory ScheduleActivitySlot.fromJson(Map<String, dynamic> json) =>
      ScheduleActivitySlot(
        id: json['id']?.toString() ?? UniqueKey().toString(),
        day: json['day']?.toString() ?? 'Monday',
        time: json['time']?.toString() ?? '08:00',
        activity: json['activity']?.toString() ?? 'Activity',
        taskCount: (json['task_count'] as num?)?.toInt() ?? 1,
        tasks: (json['tasks'] as List?)
                ?.whereType<Map>()
                .map((t) => ScheduleTaskItem.fromJson(t.cast<String, dynamic>()))
                .toList() ??
            [],
        notes: json['notes']?.toString(),
      );

  ScheduleActivitySlot copyWith({
    String? day,
    String? time,
    String? activity,
    int? taskCount,
    List<ScheduleTaskItem>? tasks,
    String? notes,
  }) =>
      ScheduleActivitySlot(
        id: id,
        day: day ?? this.day,
        time: time ?? this.time,
        activity: activity ?? this.activity,
        taskCount: taskCount ?? this.taskCount,
        tasks: tasks ?? this.tasks,
        notes: notes ?? this.notes,
      );
}

class WeeklySchedule {
  final Map<String, List<ScheduleActivitySlot>> slotsByDay;
  final String sourceFileName;
  final DateTime updatedAt;

  WeeklySchedule({
    required this.slotsByDay,
    this.sourceFileName = 'Default Routine',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Empty constructor when no schedule has been uploaded or configured yet
  factory WeeklySchedule.empty({String name = 'Live Schedule (Awaiting Upload)'}) {
    return WeeklySchedule(
      slotsByDay: const {},
      sourceFileName: name,
      updatedAt: DateTime.now(),
    );
  }

  static const List<String> standardDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> shortDays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  List<ScheduleActivitySlot> slotsForDay(String dayName) {
    if (dayName.trim().isEmpty) return slotsByDay['Monday'] ?? [];
    final lower = dayName.toLowerCase().trim();
    for (final d in standardDays) {
      final dLower = d.toLowerCase();
      if (dLower == lower || dLower.startsWith(lower) || lower.startsWith(dLower)) {
        return slotsByDay[d] ?? [];
      }
    }
    return slotsByDay[dayName] ?? [];
  }

  ScheduleActivitySlot? getSlotForDateTime(DateTime dt) {
    final weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayName = weekdayNames[(dt.weekday - 1) % 7];
    final daySlots = slotsForDay(dayName);
    if (daySlots.isEmpty) return null;
    final hour = dt.hour;
    for (final s in daySlots) {
      final slotHour = int.tryParse(s.time.split(':').first) ?? 0;
      if (hour >= slotHour && hour < slotHour + 3) return s;
    }
    return daySlots.first;
  }

  int get totalActivities {
    return slotsByDay.values.fold(0, (acc, list) => acc + list.length);
  }

  int get totalCompletedTasks {
    return slotsByDay.values.fold(
      0,
      (acc, list) => acc + list.fold(0, (sum, slot) => sum + slot.completedCount),
    );
  }

  int get totalTasks {
    return slotsByDay.values.fold(
      0,
      (acc, list) => acc + list.fold(0, (sum, slot) => sum + slot.tasks.length),
    );
  }

  Map<String, dynamic> toJson() => {
        'source_file_name': sourceFileName,
        'updated_at': updatedAt.toIso8601String(),
        'slots_by_day': slotsByDay.map(
          (k, v) => MapEntry(k, v.map((s) => s.toJson()).toList()),
        ),
      };

  factory WeeklySchedule.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots_by_day'] as Map? ?? {};
    final parsedSlots = <String, List<ScheduleActivitySlot>>{};

    for (final entry in rawSlots.entries) {
      final key = entry.key.toString();
      final list = (entry.value as List?) ?? [];
      parsedSlots[key] = list
          .whereType<Map>()
          .map((s) => ScheduleActivitySlot.fromJson(s.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
    }

    return WeeklySchedule(
      slotsByDay: parsedSlots,
      sourceFileName: json['source_file_name']?.toString() ?? 'Routine',
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
