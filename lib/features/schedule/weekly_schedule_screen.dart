import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../auth/auth_provider.dart';
import '../../models/weekly_schedule_model.dart';
import '../../particle_background.dart';
import '../../services/schedule_parser_service.dart';
import '../../session/session_provider.dart';
import 'widgets/deep_analysis_card.dart';
import 'widgets/feature_attribution_insights_card.dart';
import 'widgets/user_intention_popup.dart';

class WeeklyScheduleScreen extends StatefulWidget {
  final WeeklySchedule? initialSchedule;

  const WeeklyScheduleScreen({super.key, this.initialSchedule});

  @override
  State<WeeklyScheduleScreen> createState() => _WeeklyScheduleScreenState();
}

class _WeeklyScheduleScreenState extends State<WeeklyScheduleScreen> {
  late WeeklySchedule _schedule;
  bool _isLoading = true;
  String _selectedDay = 'Wednesday';
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    _initToday();
    if (widget.initialSchedule != null) {
      _schedule = widget.initialSchedule!;
      _isLoading = false;
    } else {
      _loadSchedule();
    }
  }

  void _initToday() {
    final now = DateTime.now();
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final todayName = weekdayNames[(now.weekday - 1) % 7];
    _selectedDay = todayName;
  }

  String get _currentActualDay {
    final now = DateTime.now();
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdayNames[(now.weekday - 1) % 7];
  }

  Future<void> _loadSchedule() async {
    if (widget.initialSchedule != null) {
      setState(() {
        _schedule = widget.initialSchedule!;
        _isLoading = false;
      });
      return;
    }

    final auth = context.read<AuthProvider>();
    final uid = await auth.resolveUserId() ?? 0;
    _userId = uid;

    final loaded = await ScheduleParserService.loadSchedule(uid);
    if (mounted) {
      setState(() {
        _schedule = loaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveCurrentSchedule() async {
    await ScheduleParserService.saveSchedule(_userId, _schedule);
    if (mounted) setState(() {});
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes != null && bytes.isNotEmpty) {
          if (!mounted) return;
          final session = context.read<SessionProvider>();
          final parsed = ScheduleParserService.parseFile(bytes, file.name);
          setState(() {
            _schedule = parsed;
          });
          await _saveCurrentSchedule();

          // Upload to POST /api/v1/be/schedule/{user_id}/upload
          try {
            final targetUid = _userId != 0 ? _userId : (session.userId ?? 'default_user');
            session.behaviourEngineClient.uploadScheduleFile(
              userId: targetUid,
              bytes: bytes,
              fileName: file.name,
            );
          } catch (_) {}

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Uploaded & synced ${parsed.totalActivities} routine slots from ${file.name}',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                backgroundColor: AppColors.successTint,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Could not read file data. Please try again.'),
                backgroundColor: AppColors.danger,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to parse schedule file: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _toggleTask(ScheduleActivitySlot slot, ScheduleTaskItem task) {
    setState(() {
      task.isCompleted = !task.isCompleted;
    });
    _saveCurrentSchedule();
  }

  SessionProvider? _getSession({bool listen = false}) {
    try {
      return Provider.of<SessionProvider>(context, listen: listen);
    } catch (_) {
      return null;
    }
  }

  void _showUserIntention(ScheduleActivitySlot slot, {double? intentionPercent}) {
    final session = _getSession();
    final be = session?.lastPipelineResult?.behaviourEngineResponse;
    final ce = session?.lastPipelineResult?.contextEngineResponse;
    final percent = intentionPercent ?? be?.relevanceScore ?? ce?.overallConfidence ?? 0.0;

    showUserIntentionDialog(
      context,
      activityName: slot.activity,
      emoji: slot.emoji,
      intentionPercent: percent,
      customOverline: 'USER INTENTION MAY BE:',
    );
  }

  void _showFeatureAttribution([ScheduleActivitySlot? slot]) {
    final session = _getSession();
    final be = session?.lastPipelineResult?.behaviourEngineResponse;
    final ce = session?.lastPipelineResult?.contextEngineResponse;
    final ceActivity = ce?.currentActivity ?? ce?.activityInformation?['activity']?.toString();
    final ceLoc = ce?.currentLocation ?? ce?.locationInformation?['current_location']?.toString();

    Map<String, dynamic>? beOutput;
    if (be != null) {
      beOutput = {
        ...be.rawJson,
        if (be.behavioralState != null) 'behavioral_state': be.behavioralState,
        if (be.relevanceScore != null) 'relevance_score': be.relevanceScore,
        if (be.stateConfidence != null) 'state_confidence': be.stateConfidence,
        if (be.hesitationScore != null) 'hesitation_score': be.hesitationScore,
        if (be.lifestyleCluster != null) 'lifestyle_cluster': be.lifestyleCluster,
        if (be.recommendedProduct != null) 'recommended_product': be.recommendedProduct,
        if (be.attributionBreakdown != null) 'attribution_breakdown': be.attributionBreakdown,
        if (be.compositeAttributionScore != null) 'composite_attribution_score': be.compositeAttributionScore,
        if (be.eligibilityBlocked != null) 'eligibility_blocked': be.eligibilityBlocked,
        if (be.blockedReason != null) 'blocked_reason': be.blockedReason,
        'venue': ?ceLoc,
        'schedule_activity': ?ceActivity,
      };
    }

    showFeatureAttributionDialog(
      context,
      slot: slot,
      beOutput: beOutput,
      ceLocation: ceLoc,
    );
  }

  void _showDeepAnalysis(ScheduleActivitySlot slot) {
    final session = _getSession();
    final ce = session?.lastPipelineResult?.contextEngineResponse;
    final be = session?.lastPipelineResult?.behaviourEngineResponse;
    final ceActivity = ce?.currentActivity ?? ce?.activityInformation?['activity']?.toString() ?? slot.activity.toLowerCase();
    final beState = be?.behavioralState ?? (session?.state.isRuntimeActive == true ? 'Engaged' : null);
    final relevance = be?.relevanceScore;

    final isMatched = slot.activity.toLowerCase().contains(ceActivity.toLowerCase()) ||
        ceActivity.toLowerCase().contains(slot.activity.toLowerCase());
    final drift = isMatched ? 0.0 : 0.75;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF13110F),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modal drag handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

              // Modal header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accentTint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.auto_graph_rounded, color: AppColors.accent, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Deep Activity Analysis',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$_selectedDay • ${slot.time}',
                                style: const TextStyle(
                                  color: Color(0xFFA89F95),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFA89F95)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // The exact deep analysis card with live CE actual activity & BE state
              DeepAnalysisCard(
                slot: slot,
                driftFraction: drift,
                customActualActivity: ceActivity,
                behavioralState: beState,
                relevanceScore: relevance,
              ),
              const SizedBox(height: 18),

              // Activity Subtasks Section
              Text(
                'ACTIVITY SUBTASKS (${slot.completedCount}/${slot.tasks.length})',
                style: const TextStyle(
                  color: Color(0xFF8C827A),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              if (slot.tasks.isEmpty)
                const Text(
                  'No subtasks configured for this activity.',
                  style: TextStyle(color: Color(0xFFA89F95), fontSize: 13),
                )
              else
                ...slot.tasks.map((task) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1B18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2824)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          task.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: task.isCompleted ? AppColors.success : const Color(0xFFA89F95),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            task.title,
                            style: TextStyle(
                              color: task.isCompleted ? const Color(0xFF8C827A) : Colors.white,
                              fontSize: 13,
                              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  },
);
}

  void _editSlot(ScheduleActivitySlot slot) {
    final titleController = TextEditingController(text: slot.activity);
    final timeController = TextEditingController(text: slot.time);
    final notesController = TextEditingController(text: slot.notes ?? '');
    final tasksList = List<ScheduleTaskItem>.from(
      slot.tasks.map((t) => t.copyWith()),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Row(
                      children: [
                        Text(
                          '${slot.emoji} Edit Activity',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () {
                            setState(() {
                              _schedule.slotsByDay[_selectedDay]?.removeWhere(
                                (s) => s.id == slot.id,
                              );
                            });
                            _saveCurrentSchedule();
                            Navigator.pop(ctx);
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Activity Name',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: timeController,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Time Slot (e.g. 09:00)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Subtasks',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            setSheetState(() {
                              tasksList.add(
                                ScheduleTaskItem(
                                  id: UniqueKey().toString(),
                                  title: 'New Subtask',
                                ),
                              );
                            });
                          },
                          icon: Icon(Icons.add, size: 16, color: AppColors.accent),
                          label: Text(
                            'Add Task',
                            style: TextStyle(color: AppColors.accent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...tasksList.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final t = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: t.isCompleted,
                              activeColor: AppColors.accent,
                              onChanged: (val) {
                                setSheetState(() {
                                  t.isCompleted = val ?? false;
                                });
                              },
                            ),
                            Expanded(
                              child: TextFormField(
                                initialValue: t.title,
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: AppColors.surfaceMuted,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                ),
                                onChanged: (val) => t.title = val,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline, size: 18, color: AppColors.textSecondary),
                              onPressed: () {
                                setSheetState(() {
                                  tasksList.removeAt(idx);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            slot.activity = titleController.text.trim();
                            slot.time = timeController.text.trim();
                            slot.notes = notesController.text.trim();
                            slot.tasks = tasksList;
                            slot.taskCount = tasksList.length;
                            _schedule.slotsByDay[_selectedDay]?.sort((a, b) => a.time.compareTo(b.time));
                          });
                          _saveCurrentSchedule();
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

  void _addNewSlot() {
    final titleController = TextEditingController(text: 'Working');
    final timeController = TextEditingController(text: '10:00');
    final subtaskController = TextEditingController(text: 'Focus session');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('Add Activity Slot', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Activity',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: timeController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Time (e.g. 14:00)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: subtaskController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Initial Subtask',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newSlot = ScheduleActivitySlot(
                id: '${_selectedDay}_${timeController.text}_${DateTime.now().millisecondsSinceEpoch}',
                day: _selectedDay,
                time: timeController.text.trim(),
                activity: titleController.text.trim(),
                taskCount: 1,
                tasks: [
                  ScheduleTaskItem(
                    id: UniqueKey().toString(),
                    title: subtaskController.text.trim(),
                  ),
                ],
              );
              setState(() {
                _schedule.slotsByDay.putIfAbsent(_selectedDay, () => []).add(newSlot);
                _schedule.slotsByDay[_selectedDay]?.sort((a, b) => a.time.compareTo(b.time));
              });
              _saveCurrentSchedule();
              Navigator.pop(ctx);
            },
            child: const Text('Add Slot', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final session = _getSession(listen: true);
    final ce = session?.lastPipelineResult?.contextEngineResponse;
    final be = session?.lastPipelineResult?.behaviourEngineResponse;
    final liveActivity = ce?.currentActivity ?? ce?.activityInformation?['activity']?.toString();
    final liveBeState = be?.behavioralState;
    final liveConfidence = be?.relevanceScore ?? ce?.overallConfidence;

    final slots = _schedule.slotsForDay(_selectedDay);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Schedule',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            Text(
              _schedule.sourceFileName,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Why? (Feature Attribution)',
            icon: Icon(Icons.insights_rounded, color: AppColors.accent),
            onPressed: () => _showFeatureAttribution(),
          ),
          IconButton(
            tooltip: 'Upload Excel/CSV',
            icon: Icon(Icons.upload_file, color: AppColors.accent),
            onPressed: _pickAndUploadFile,
          ),
          IconButton(
            tooltip: 'Add Activity',
            icon: Icon(Icons.add_circle_outline, color: AppColors.textSecondary),
            onPressed: _addNewSlot,
          ),
        ],
      ),
      body: ParticleBackground(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _buildDaySelector(),
            const SizedBox(height: 10),
            Expanded(
              child: slots.isEmpty
                  ? _buildEmptyState(
                      liveActivity: liveActivity,
                      liveConfidence: liveConfidence,
                    )
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildCurrentActivityBanner(
                              slots,
                              liveActivity: liveActivity,
                              liveBeState: liveBeState,
                              liveConfidence: liveConfidence,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildSummaryBar(slots),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
                          sliver: SliverList.separated(
                            itemCount: slots.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _buildTimelineCard(slots[index]);
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentActivityBanner(
    List<ScheduleActivitySlot> slots, {
    String? liveActivity,
    String? liveBeState,
    double? liveConfidence,
  }) {
    if (slots.isEmpty) return const SizedBox.shrink();

    final isToday = _selectedDay.toLowerCase() == _currentActualDay.toLowerCase();

    // Pick active slot: if liveActivity is detected today, match it; else match by current hour
    ScheduleActivitySlot? activeSlot;
    if (isToday && liveActivity != null && liveActivity.isNotEmpty) {
      final actLower = liveActivity.toLowerCase();
      activeSlot = slots.cast<ScheduleActivitySlot?>().firstWhere(
            (s) => s != null && (s.activity.toLowerCase().contains(actLower) || actLower.contains(s.activity.toLowerCase())),
            orElse: () => null,
          );
    }

    if (activeSlot == null) {
      final currentHour = DateTime.now().hour;
      for (final s in slots) {
        final hour = int.tryParse(s.time.split(':').first);
        if (hour != null && hour <= currentHour) {
          activeSlot = s;
        }
      }
      activeSlot ??= slots.first;
    }

    final intentionScore = liveConfidence != null && liveConfidence > 0
        ? (liveConfidence * 100).round()
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () => _showUserIntention(activeSlot!, intentionPercent: liveConfidence),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF2563EB).withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Left icon container
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                  ),
                ),
                child: Center(
                  child: Text(activeSlot.emoji, style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              // Middle Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF3B82F6),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              isToday
                                  ? (liveActivity != null ? 'LIVE MATCH' : 'CURRENT')
                                  : 'ROUTINE',
                              style: const TextStyle(
                                color: Color(0xFF60A5FA),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          activeSlot.time,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (liveBeState != null && liveBeState.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• $liveBeState',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      activeSlot.activity,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Intention Donut Indicator trigger
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: intentionScore > 0 ? const Color(0xFF261907) : const Color(0xFF181B24),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: intentionScore > 0 ? const Color(0xFF9A5B0B) : const Color(0xFF2D3748),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$intentionScore%',
                      style: TextStyle(
                        color: intentionScore > 0 ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.donut_large_rounded,
                      size: 14,
                      color: intentionScore > 0 ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const fullDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(days.length, (i) {
          final short = days[i];
          final full = fullDays[i];
          final isSelected = _selectedDay.toLowerCase() == full.toLowerCase();
          final isToday = _currentActualDay.toLowerCase() == full.toLowerCase();

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _selectedDay = full;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.accentTint
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : (isToday ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border),
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      short,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.accentStrong : AppColors.textSecondary,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'TODAY',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSummaryBar(List<ScheduleActivitySlot> slots) {
    final completed = slots.fold(0, (acc, s) => acc + s.completedCount);
    final total = slots.fold(0, (acc, s) => acc + s.tasks.length);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$_selectedDay Schedule',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${slots.length} Slots · $completed/$total done',
                style: TextStyle(
                  color: AppColors.accentStrong,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(ScheduleActivitySlot slot) {
    final accent = slot.accentColor;
    final isDone = slot.isAllCompleted;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Accent Border
            Container(
              width: 4.5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            // Time Section
            Container(
              width: 76,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                slot.time,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // Divider
            Container(width: 1, color: AppColors.border),
            // Activity Content Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      children: [
                        Text(
                          slot.emoji,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            slot.activity,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDone ? AppColors.textSecondary : AppColors.textPrimary,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _showFeatureAttribution(slot),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.insights_rounded, size: 16, color: const Color(0xFFF59E0B)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _showDeepAnalysis(slot),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.auto_graph_rounded, size: 16, color: AppColors.accent),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _editSlot(slot),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Subtasks / Chips Row
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        // Insights Pill (Why?)
                        InkWell(
                          onTap: () => _showFeatureAttribution(slot),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B1B15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.insights_rounded,
                                  size: 12,
                                  color: Color(0xFFF59E0B),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Insights',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Deep Analysis Pill
                        InkWell(
                          onTap: () => _showDeepAnalysis(slot),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF221E1A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 12,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Deep Analysis',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Completion Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDone
                                ? AppColors.successTint
                                : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDone
                                  ? AppColors.success.withValues(alpha: 0.5)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 12,
                                color: isDone ? AppColors.success : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${slot.completedCount}/${slot.tasks.length} done',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDone ? AppColors.success : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Individual Subtask Pills
                        ...slot.tasks.map((task) {
                          return InkWell(
                            onTap: () => _toggleTask(slot, task),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: task.isCompleted
                                    ? AppColors.accentTint
                                    : AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: task.isCompleted
                                      ? AppColors.accent.withValues(alpha: 0.6)
                                      : AppColors.border,
                                ),
                              ),
                              child: Text(
                                task.title,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: task.isCompleted
                                      ? AppColors.accentStrong
                                      : AppColors.textPrimary,
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({String? liveActivity, double? liveConfidence}) {
    final hasLive = liveActivity != null && liveActivity.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasLive ? Icons.sensors_rounded : Icons.event_busy_outlined,
              size: 52,
              color: hasLive ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              hasLive
                  ? 'Live Activity Detected: ${liveActivity.toUpperCase()}'
                  : 'No activities scheduled for $_selectedDay',
              style: TextStyle(
                color: hasLive ? Colors.white : AppColors.textSecondary,
                fontSize: 15,
                fontWeight: hasLive ? FontWeight.w700 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasLive && liveConfidence != null && liveConfidence > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Live Confidence: ${(liveConfidence * 100).round()}%',
                style: const TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Upload your routine spreadsheet (.xlsx / .csv) or add custom activity slots.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _pickAndUploadFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text(
                    'Upload Routine File',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _addNewSlot,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Add Slot',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
