import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models/weekly_schedule_model.dart';

class ScheduleParserService {
  static const String _defaultStorageKeyPrefix = 'weekly_schedule_';

  static String _storageKey(int userId) =>
      '$_defaultStorageKeyPrefix${userId != 0 ? userId : "guest"}_v1';

  /// Parses an uploaded Excel (.xlsx, .xls) or CSV file into a [WeeklySchedule].
  static WeeklySchedule parseFile(Uint8List bytes, String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.csv')) {
      return parseCsv(bytes, fileName: fileName);
    } else if (lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls')) {
      return parseExcel(bytes, fileName: fileName);
    } else {
      // Try XLSX XML first, then CSV, then Excel package
      try {
        final xmlRows = _parseXlsxXml(bytes);
        if (xmlRows.isNotEmpty) {
          return _parseTableRows(xmlRows, fileName);
        }
      } catch (_) {}

      try {
        return parseCsv(bytes, fileName: fileName);
      } catch (_) {
        return parseExcel(bytes, fileName: fileName);
      }
    }
  }

  /// Parses CSV format bytes.
  static WeeklySchedule parseCsv(Uint8List bytes, {String fileName = 'Schedule.csv'}) {
    final rawText = utf8.decode(bytes, allowMalformed: true);
    final rows = _parseCsvText(rawText);
    return _parseTableRows(rows, fileName);
  }

  static List<List<String>> _parseCsvText(String text) {
    final lines = const LineSplitter().convert(text);
    final rows = <List<String>>[];
    final cellRegex = RegExp(r'(?:^|,)(?:"([^"]*(?:""[^"]*)*)"|([^,]*))');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final row = <String>[];
      for (final match in cellRegex.allMatches(line)) {
        final quoted = match.group(1);
        final unquoted = match.group(2);
        if (quoted != null) {
          row.add(quoted.replaceAll('""', '"').trim());
        } else if (unquoted != null) {
          row.add(unquoted.trim());
        }
      }
      if (row.isNotEmpty) {
        rows.add(row);
      }
    }
    return rows;
  }

  /// Parses Excel (.xlsx/.xls) format bytes using XML decoding first, then package:excel.
  static WeeklySchedule parseExcel(Uint8List bytes, {String fileName = 'Schedule.xlsx'}) {
    // 1. Try robust direct XLSX XML extraction (bypasses parser bugs in excel package)
    try {
      final xmlRows = _parseXlsxXml(bytes);
      if (xmlRows.isNotEmpty) {
        return _parseTableRows(xmlRows, fileName);
      }
    } catch (_) {}

    // 2. Fallback to package:excel parser
    try {
      final excel = Excel.decodeBytes(bytes);
      final rows = <List<dynamic>>[];

      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet != null && sheet.rows.isNotEmpty) {
          for (final row in sheet.rows) {
            final rowValues = <String>[];
            for (final cell in row) {
              rowValues.add(_extractCellValue(cell));
            }
            if (rowValues.any((v) => v.trim().isNotEmpty)) {
              rows.add(rowValues);
            }
          }
          if (rows.isNotEmpty) break;
        }
      }

      if (rows.isNotEmpty) {
        return _parseTableRows(rows, fileName);
      }
    } catch (_) {}

    // 3. Fallback to CSV plain text parsing
    try {
      return parseCsv(bytes, fileName: fileName);
    } catch (e) {
      throw 'Failed to parse spreadsheet: $e';
    }
  }

  static List<List<String>> _parseXlsxXml(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Read shared strings table
    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final ssXml = utf8.decode(ssFile.content as List<int>, allowMalformed: true);
      final doc = XmlDocument.parse(ssXml);
      for (final si in doc.findAllElements('si')) {
        final t = si.findAllElements('t').map((e) => e.innerText).join();
        sharedStrings.add(t);
      }
    }

    // Find worksheet
    ArchiveFile? sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
    if (sheetFile == null) {
      for (final f in archive.files) {
        if (f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml')) {
          sheetFile = f;
          break;
        }
      }
    }
    if (sheetFile == null) return [];

    final sheetXml = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
    final sheetDoc = XmlDocument.parse(sheetXml);

    final rows = <List<String>>[];
    for (final rowElem in sheetDoc.findAllElements('row')) {
      final rowMap = <int, String>{};
      for (final cElem in rowElem.findAllElements('c')) {
        final rAttr = cElem.getAttribute('r') ?? '';
        final tAttr = cElem.getAttribute('t') ?? '';
        final vElem = cElem.findElements('v').firstOrNull;
        String val = '';
        if (vElem != null) {
          final rawVal = vElem.innerText.trim();
          if (tAttr == 's') {
            final idx = int.tryParse(rawVal);
            if (idx != null && idx < sharedStrings.length) {
              val = sharedStrings[idx];
            } else {
              val = rawVal;
            }
          } else {
            val = rawVal;
          }
        } else {
          final isElem = cElem.findElements('is').firstOrNull;
          if (isElem != null) {
            val = isElem.findAllElements('t').map((e) => e.innerText).join();
          }
        }

        final colIdx = _colRefToIndex(rAttr);
        rowMap[colIdx] = val;
      }

      if (rowMap.values.any((v) => v.trim().isNotEmpty)) {
        final maxCol = rowMap.keys.reduce((a, b) => a > b ? a : b);
        final rowList = List<String>.generate(maxCol + 1, (i) => (rowMap[i] ?? '').trim());
        rows.add(rowList);
      }
    }
    return rows;
  }

  static int _colRefToIndex(String cellRef) {
    final letters = cellRef.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    int col = 0;
    for (int i = 0; i < letters.length; i++) {
      col = col * 26 + (letters.codeUnitAt(i) - 64);
    }
    return col > 0 ? col - 1 : 0;
  }

  static String _extractCellValue(dynamic cell) {
    if (cell == null) return '';
    try {
      final val = cell.value;
      if (val == null) return '';
      if (val is TextCellValue) {
        return val.value.text ?? val.value.toString();
      } else if (val is IntCellValue) {
        return val.value.toString();
      } else if (val is DoubleCellValue) {
        return val.value.toString();
      } else if (val is TimeCellValue) {
        final h = val.hour.toString().padLeft(2, '0');
        final m = val.minute.toString().padLeft(2, '0');
        return '$h:$m';
      } else if (val is DateTimeCellValue) {
        final h = val.hour.toString().padLeft(2, '0');
        final m = val.minute.toString().padLeft(2, '0');
        return '$h:$m';
      } else if (val is DateCellValue) {
        return '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
      } else if (val is BoolCellValue) {
        return val.value ? 'true' : 'false';
      } else if (val is FormulaCellValue) {
        return val.formula;
      }
      final str = val.toString().trim();
      final innerMatch = RegExp(r'^[A-Za-z]+CellValue\((?:value:\s*)?([^\)]+)\)$').firstMatch(str);
      if (innerMatch != null) {
        return innerMatch.group(1) ?? str;
      }
      return str;
    } catch (_) {
      return cell?.toString() ?? '';
    }
  }

  /// Core tabular parser that looks for headers: Day, Time, Activity, Tasks/Count
  static WeeklySchedule _parseTableRows(List<List<dynamic>> rows, String fileName) {
    if (rows.isEmpty) {
      return WeeklySchedule.empty(name: fileName);
    }

    // Locate header row indices
    int dayCol = -1;
    int timeCol = -1;
    int activityCol = -1;
    int countCol = -1;
    int subtasksCol = -1;
    int headerRowIndex = 0;

    for (int i = 0; i < rows.length && i < 10; i++) {
      final row = rows[i].map((e) => e.toString().trim().toLowerCase()).toList();
      for (int c = 0; c < row.length; c++) {
        final val = row[c];
        if (val == 'day' || val == 'weekday' || val == 'day of week') {
          dayCol = c;
        } else if (val == 'time' || val == 'hour' || val == 'start time' || val == 'slot') {
          timeCol = c;
        } else if (val == 'activity' || val == 'event' || val == 'action' || val == 'title') {
          activityCol = c;
        } else if (val.contains('task') || val.contains('count')) {
          countCol = c;
        } else if (val.contains('subtask') || val.contains('detail') || val.contains('note')) {
          subtasksCol = c;
        }
      }

      if (dayCol != -1 && (timeCol != -1 || activityCol != -1)) {
        headerRowIndex = i;
        break;
      }
    }

    // Default column fallback if headers were ambiguous
    if (dayCol == -1) dayCol = 0;
    if (timeCol == -1) timeCol = 1;
    if (activityCol == -1) activityCol = 2;
    if (countCol == -1 && rows.first.length > 3) countCol = 3;

    final slotsByDay = <String, List<ScheduleActivitySlot>>{
      'Monday': [],
      'Tuesday': [],
      'Wednesday': [],
      'Thursday': [],
      'Friday': [],
      'Saturday': [],
      'Sunday': [],
    };

    String currentDay = 'Monday';

    for (int r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      // Extract raw values
      final rawDay = dayCol < row.length ? row[dayCol].toString().trim() : '';
      final rawTime = timeCol < row.length ? row[timeCol].toString().trim() : '';
      final rawActivity = activityCol < row.length ? row[activityCol].toString().trim() : '';
      final rawCount = countCol != -1 && countCol < row.length ? row[countCol].toString().trim() : '';
      final rawSubtasks = subtasksCol != -1 && subtasksCol < row.length ? row[subtasksCol].toString().trim() : '';

      // Carry forward day if row has blank day
      if (rawDay.isNotEmpty) {
        currentDay = _normalizeDay(rawDay);
      }

      if (rawActivity.trim().isEmpty) continue;

      final formattedTime = _formatTime(rawTime);
      final taskCount = int.tryParse(rawCount) ?? 1;

      // Generate or parse subtasks
      final tasks = _buildSubtasks(rawActivity, taskCount, rawSubtasks);

      final slot = ScheduleActivitySlot(
        id: '${currentDay}_${formattedTime}_${rawActivity.hashCode}',
        day: currentDay,
        time: formattedTime,
        activity: rawActivity.isNotEmpty ? rawActivity : 'Scheduled Routine',
        taskCount: taskCount,
        tasks: tasks,
      );

      slotsByDay.putIfAbsent(currentDay, () => []).add(slot);
    }

    // Sort slots by time for each day
    for (final key in slotsByDay.keys) {
      slotsByDay[key]?.sort((a, b) => a.time.compareTo(b.time));
    }

    return WeeklySchedule(
      slotsByDay: slotsByDay,
      sourceFileName: fileName,
      updatedAt: DateTime.now(),
    );
  }

  static String _normalizeDay(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.startsWith('mon')) return 'Monday';
    if (lower.startsWith('tue')) return 'Tuesday';
    if (lower.startsWith('wed')) return 'Wednesday';
    if (lower.startsWith('thu')) return 'Thursday';
    if (lower.startsWith('fri')) return 'Friday';
    if (lower.startsWith('sat')) return 'Saturday';
    if (lower.startsWith('sun')) return 'Sunday';
    return 'Monday';
  }

  static String _formatTime(String raw) {
    if (raw.isEmpty) return '08:00';
    final clean = raw.trim();

    // Check if integer (e.g. 5 -> 05:00)
    final numVal = int.tryParse(clean);
    if (numVal != null && numVal >= 0 && numVal <= 24) {
      return '${numVal.toString().padLeft(2, '0')}:00';
    }

    // Check if decimal fraction (e.g. 0.3125 -> 07:30)
    final doubleVal = double.tryParse(clean);
    if (doubleVal != null && doubleVal >= 0.0 && doubleVal <= 1.0) {
      final totalMinutes = (doubleVal * 24 * 60).round();
      final hours = (totalMinutes ~/ 60) % 24;
      final minutes = totalMinutes % 60;
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    }

    // Match HH:MM
    final match = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(clean);
    if (match != null) {
      final g1 = match.group(1);
      final g2 = match.group(2);
      if (g1 != null && g2 != null) {
        final hh = g1.padLeft(2, '0');
        return '$hh:$g2';
      }
    }

    return clean;
  }

  static List<ScheduleTaskItem> _buildSubtasks(
    String activity,
    int count,
    String rawSubtasks,
  ) {
    if (rawSubtasks.isNotEmpty) {
      final parts = rawSubtasks.split(RegExp(r'[,;|\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        return parts
            .map((p) => ScheduleTaskItem(id: UniqueKey().toString(), title: p))
            .toList();
      }
    }

    final act = activity.toLowerCase();
    final defaults = <String>[];

    if (act.contains('wak') || act.contains('alarm')) {
      defaults.addAll(['Dismiss alarm', 'Check phone', 'Drink water']);
    } else if (act.contains('bath') || act.contains('shower')) {
      defaults.addAll(['Shower', 'Get dressed', 'Skin care']);
    } else if (act.contains('eat') || act.contains('break') || act.contains('lunch') || act.contains('dinner')) {
      defaults.addAll(['Breakfast', 'Pack lunch', 'Clean dishes']);
    } else if (act.contains('transit') || act.contains('commute')) {
      defaults.addAll(['Commute to office', 'Transit check']);
    } else if (act.contains('work')) {
      defaults.addAll(['Check emails', 'Morning standup', 'Deep work block', 'Team sync']);
    } else if (act.contains('relax')) {
      defaults.addAll(['Read book', 'Evening walk', 'Stretch']);
    } else if (act.contains('watch')) {
      defaults.addAll(['Watch episode', 'Relaxation time']);
    } else if (act.contains('gym') || act.contains('workout')) {
      defaults.addAll(['Warmup', 'Main set', 'Cool down']);
    } else {
      defaults.addAll(['Step 1', 'Step 2', 'Step 3']);
    }

    final effectiveCount = count > 0 ? count : 1;
    final list = <ScheduleTaskItem>[];
    for (int i = 0; i < effectiveCount; i++) {
      final title = i < defaults.length ? defaults[i] : 'Task ${i + 1}';
      list.add(ScheduleTaskItem(id: '${activity}_$i', title: title));
    }
    return list;
  }

  /// Save schedule locally
  static Future<void> saveSchedule(int userId, WeeklySchedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(schedule.toJson());
    await prefs.setString(_storageKey(userId), jsonStr);
  }

  /// Load schedule for user. Returns empty schedule awaiting live upload if no schedule is saved.
  static Future<WeeklySchedule> loadSchedule(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(userId));
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return WeeklySchedule.fromJson(decoded);
      } catch (e) {
        debugPrint('Failed to decode saved schedule: $e');
      }
    }
    return WeeklySchedule.empty();
  }

  /// Default pre-built schedule matching the user's sample Excel sheet
  static WeeklySchedule getSampleSchedule() {
    final slotsByDay = <String, List<ScheduleActivitySlot>>{
      'Monday': [
        _slot('Monday', '05:00', 'Waking Up', 2, ['Dismiss alarm', 'Check phone']),
        _slot('Monday', '06:00', 'Bathing', 2, ['Shower', 'Get dressed']),
        _slot('Monday', '07:00', 'Eating', 2, ['Breakfast', 'Pack lunch']),
        _slot('Monday', '08:00', 'Transit', 1, ['Commute to office']),
        _slot('Monday', '09:00', 'Working', 2, ['Check emails', 'Morning standup']),
        _slot('Monday', '10:00', 'Working', 1, ['Deep work block']),
        _slot('Monday', '11:00', 'Working', 1, ['Project reviews']),
        _slot('Monday', '12:00', 'Eating', 2, ['Lunch with team', 'Walk']),
        _slot('Monday', '13:00', 'Working', 1, ['Sprint tasks']),
        _slot('Monday', '14:00', 'Working', 1, ['Code analysis']),
        _slot('Monday', '15:00', 'Working', 1, ['Client sync']),
        _slot('Monday', '16:00', 'Working', 2, ['Wrap up', 'Log reports']),
        _slot('Monday', '17:00', 'Transit', 1, ['Commute home']),
        _slot('Monday', '18:00', 'Relaxing', 2, ['Evening tea', 'Unwind']),
        _slot('Monday', '19:00', 'Eating', 2, ['Dinner', 'Family time']),
        _slot('Monday', '20:00', 'Watching', 1, ['Documentary / News']),
        _slot('Monday', '21:00', 'Watching', 1, ['Favorite series']),
        _slot('Monday', '22:00', 'Relaxing', 2, ['Read book', 'Prepare sleep']),
      ],
      'Tuesday': [
        _slot('Tuesday', '05:00', 'Transit', 1, ['Early morning run']),
        _slot('Tuesday', '06:00', 'Eating', 2, ['Healthy breakfast', 'Hydrate']),
        _slot('Tuesday', '07:00', 'Eating', 2, ['Protein shake', 'Prep']),
        _slot('Tuesday', '08:00', 'Transit', 1, ['Commute to office']),
        _slot('Tuesday', '09:00', 'Working', 2, ['Check emails', 'Tech review']),
        _slot('Tuesday', '10:00', 'Working', 1, ['Architecture design']),
        _slot('Tuesday', '11:00', 'Working', 1, ['Dev pairing']),
        _slot('Tuesday', '12:00', 'Eating', 2, ['Lunch', 'Coffee']),
        _slot('Tuesday', '13:00', 'Working', 1, ['Bug triage']),
        _slot('Tuesday', '14:00', 'Working', 1, ['Feature build']),
        _slot('Tuesday', '15:00', 'Working', 2, ['Design sync', 'Code review']),
        _slot('Tuesday', '17:00', 'Transit', 1, ['Commute home']),
        _slot('Tuesday', '19:00', 'Eating', 2, ['Dinner', 'Tidy kitchen']),
        _slot('Tuesday', '21:00', 'Watching', 1, ['Movie / relaxation']),
      ],
      'Wednesday': [
        _slot('Wednesday', '05:00', 'Waking Up', 2, ['Dismiss alarm', 'Check phone']),
        _slot('Wednesday', '06:00', 'Bathing', 2, ['Shower', 'Get dressed']),
        _slot('Wednesday', '07:00', 'Eating', 2, ['Breakfast', 'Pack lunch']),
        _slot('Wednesday', '08:00', 'Transit', 1, ['Commute to office']),
        _slot('Wednesday', '09:00', 'Working', 2, ['Check emails', 'Morning standup']),
        _slot('Wednesday', '10:00', 'Working', 1, ['Deep work block']),
        _slot('Wednesday', '12:00', 'Eating', 2, ['Lunch', 'Short stroll']),
        _slot('Wednesday', '14:00', 'Working', 2, ['Sprint execution', 'Review']),
        _slot('Wednesday', '17:00', 'Transit', 1, ['Commute home']),
        _slot('Wednesday', '18:00', 'Relaxing', 2, ['Podcast', 'Workout']),
        _slot('Wednesday', '20:00', 'Eating', 1, ['Dinner']),
        _slot('Wednesday', '22:00', 'Relaxing', 2, ['Read fiction', 'Sleep prep']),
      ],
      'Thursday': [
        _slot('Thursday', '05:30', 'Waking Up', 2, ['Alarm', 'Hydrate']),
        _slot('Thursday', '06:30', 'Bathing', 2, ['Shower', 'Grooming']),
        _slot('Thursday', '07:30', 'Eating', 1, ['Breakfast']),
        _slot('Thursday', '08:30', 'Transit', 1, ['Commute']),
        _slot('Thursday', '09:30', 'Working', 2, ['Planning', 'Tasks']),
        _slot('Thursday', '12:30', 'Eating', 2, ['Lunch', 'Coffee']),
        _slot('Thursday', '14:00', 'Working', 2, ['Client presentation', 'Docs']),
        _slot('Thursday', '18:00', 'Transit', 1, ['Commute home']),
        _slot('Thursday', '20:00', 'Eating', 2, ['Dinner', 'Family call']),
        _slot('Thursday', '22:00', 'Watching', 1, ['Night show']),
      ],
      'Friday': [
        _slot('Friday', '06:00', 'Waking Up', 2, ['Wake up', 'Stretch']),
        _slot('Friday', '07:00', 'Eating', 2, ['Breakfast', 'Coffee']),
        _slot('Friday', '08:00', 'Transit', 1, ['Commute']),
        _slot('Friday', '09:00', 'Working', 2, ['Standup', 'Wrap sprint']),
        _slot('Friday', '12:00', 'Eating', 2, ['Team Friday lunch', 'Social']),
        _slot('Friday', '14:00', 'Working', 1, ['Weekly retrospective']),
        _slot('Friday', '17:00', 'Transit', 1, ['Head home / Weekend kickoff']),
        _slot('Friday', '19:00', 'Relaxing', 2, ['Dinner out', 'Friends']),
        _slot('Friday', '21:00', 'Watching', 1, ['Friday movie night']),
      ],
      'Saturday': [
        _slot('Saturday', '07:30', 'Waking Up', 1, ['Late rise', 'Coffee']),
        _slot('Saturday', '08:30', 'Eating', 2, ['Pancake breakfast', 'Tea']),
        _slot('Saturday', '10:00', 'Transit', 1, ['Farmers market / Groceries']),
        _slot('Saturday', '12:30', 'Eating', 2, ['Lunch', 'Dessert']),
        _slot('Saturday', '15:00', 'Relaxing', 2, ['Hobby time', 'Music']),
        _slot('Saturday', '18:00', 'Watching', 2, ['Sports match', 'Snacks']),
        _slot('Saturday', '20:30', 'Eating', 2, ['Dinner with friends', 'Walk']),
      ],
      'Sunday': [
        _slot('Sunday', '08:00', 'Waking Up', 1, ['Gentle wake up']),
        _slot('Sunday', '09:00', 'Eating', 2, ['Brunch', 'Newspaper']),
        _slot('Sunday', '11:00', 'Relaxing', 2, ['Park stroll', 'Reading']),
        _slot('Sunday', '13:30', 'Eating', 1, ['Lunch']),
        _slot('Sunday', '15:00', 'Relaxing', 2, ['Meal prep for week', 'Unwind']),
        _slot('Sunday', '18:00', 'Watching', 1, ['Documentary']),
        _slot('Sunday', '20:00', 'Eating', 1, ['Light dinner']),
        _slot('Sunday', '21:30', 'Relaxing', 2, ['Plan upcoming week', 'Early sleep']),
      ],
    };

    return WeeklySchedule(
      slotsByDay: slotsByDay,
      sourceFileName: 'Weekly Routine Template',
      updatedAt: DateTime.now(),
    );
  }

  static ScheduleActivitySlot _slot(
    String day,
    String time,
    String activity,
    int count,
    List<String> taskTitles,
  ) {
    return ScheduleActivitySlot(
      id: '${day}_${time}_${activity.hashCode}',
      day: day,
      time: time,
      activity: activity,
      taskCount: count,
      tasks: taskTitles
          .map((t) => ScheduleTaskItem(id: UniqueKey().toString(), title: t))
          .toList(),
    );
  }
}
