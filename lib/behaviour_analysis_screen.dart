import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'app_logger.dart';
import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'env_config.dart';
import 'features/owned_objects/owned_objects_card.dart';
import 'features/schedule/weekly_schedule_screen.dart';
import 'services/schedule_parser_service.dart';
import 'session/session_provider.dart';
import 'package:file_picker/file_picker.dart';

// ── Theme-mapped node/edge roles ─────────────────────────────────────────────
// The API sends pink/magenta colors from its own design system. We ignore them
// entirely and remap every node to the app's own warm amber palette.
//
// Hub  (id == 'user' or size >= 30):
//   fill  = accent (0xFFE8963C)   border = accentStrong
//   font  = white
//
// Branch:
//   fill  = surface/surfaceMuted  border = border token
//   font  = textPrimary

const _hubFill = Color(0xFFE8963C); // AppColors.accent
const _hubBorder = Color(0xFFC97B2E); // AppColors.accentStrong light
const _hubFont = Colors.white;

class _GraphNode {
  final String id;
  final String label;
  final Color background;
  final Color border;
  final Color fontColor;
  final double size;
  final double? x;
  final double? y;
  final bool isHub;

  _GraphNode({
    required this.id,
    required this.label,
    required this.background,
    required this.border,
    required this.fontColor,
    required this.size,
    required this.x,
    required this.y,
    required this.isHub,
  });

  factory _GraphNode.parse(Map<String, dynamic> json) {
    final size = (json['size'] as num?)?.toDouble() ?? 24;
    final id = json['id']?.toString() ?? '';
    final isHub = id == 'user' || size >= 30;

    // Ignore API colors — remap to app theme.
    final bg = isHub ? _hubFill : AppColors.surface;
    final border = isHub ? _hubBorder : AppColors.border;
    final font = isHub ? _hubFont : AppColors.textPrimary;

    // /be/analytics/graph only guarantees x/y on the 6 fixed taxonomy
    // branches - the real, dynamic nodes (detected objects, behavioural
    // states, places) come back with no position at all. Left null here
    // rather than defaulted to 0, so _BehaviourGraph can tell the two cases
    // apart and fall back to a connectivity layout instead of stacking every
    // unpositioned node on top of each other.
    return _GraphNode(
      id: id,
      label: json['label']?.toString() ?? id,
      background: bg,
      border: border,
      fontColor: font,
      size: size,
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
      isHub: isHub,
    );
  }
}

class _GraphEdge {
  final String from;
  final String to;
  final String label;
  final Color color;

  _GraphEdge({required this.from, required this.to, required this.label, required this.color});

  factory _GraphEdge.parse(Map<String, dynamic> json) {
    return _GraphEdge(
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      // Edge lines: accent at low opacity — visible on both light/dark bg.
      color: AppColors.accent.withValues(alpha: 0.35),
    );
  }
}

// Most branch labels the API sends are "<emoji> <text>" (e.g. "👁️ Objects") -
// splitting them lets the emoji render big as the bubble's icon and the text
// as a caption underneath, instead of cramming both as one small string.
// Heuristic: first whitespace-separated token is treated as the icon only if
// every code point in it is non-ASCII (hub labels like "Shopper Profile"
// have an ASCII first word, so they fall through untouched).
(String?, String) _splitLeadingEmoji(String label) {
  final trimmed = label.trim();
  final firstSpace = trimmed.indexOf(' ');
  if (firstSpace <= 0) return (null, trimmed);
  final first = trimmed.substring(0, firstSpace);
  final rest = trimmed.substring(firstSpace + 1).trim();
  final isEmoji = first.runes.every((r) => r > 127);
  if (isEmoji && rest.isNotEmpty) return (first, rest);
  return (null, trimmed);
}

// One entry from /be/analytics/episodes - field priority matches the
// documented 'activity' field first, with fallbacks for older payload shapes
// (mirrors C:\Dev\smartglass_flutter's EpisodeEntry.fromJson).
class _Episode {
  final String type;
  final String summary;
  final int? durationMs;
  final String? primaryObject;
  final double? avgHesitation;
  final int? timestampMs;

  _Episode({
    required this.type,
    required this.summary,
    this.durationMs,
    this.primaryObject,
    this.avgHesitation,
    this.timestampMs,
  });

  factory _Episode.parse(Map<String, dynamic> json) {
    final ts = json['timestamp_ms'] ?? json['timestamp'];
    final durationMs = json['duration_ms'];
    final avgHesitation = json['avg_hesitation'];
    return _Episode(
      type: (json['activity'] ?? json['episode_type'] ?? json['type'] ?? json['category'] ?? 'episode').toString(),
      summary: (json['summary'] ?? json['description'] ?? json['object_class'] ?? json['label'] ?? '').toString(),
      durationMs: durationMs is num ? durationMs.toInt() : null,
      primaryObject: json['primary_object']?.toString(),
      avgHesitation: avgHesitation is num ? avgHesitation.toDouble() : null,
      timestampMs: ts is num ? ts.toInt() : null,
    );
  }

  String get durationLabel {
    final ms = durationMs;
    if (ms == null) return '—';
    final seconds = ms ~/ 1000;
    return seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}m ${seconds % 60}s';
  }

  String get timeLabel {
    final ms = timestampMs;
    if (ms == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// Renders the Behaviour Engine's own graph endpoint (nodes + edges) as an
// actual node-link diagram rather than a list - positions come straight from
// the API, colors are remapped to the app's own theme (see _GraphNode.parse).
// Also surfaces /be/analytics/episodes as a swipeable carousel underneath.
class BehaviourAnalysisScreen extends StatefulWidget {
  const BehaviourAnalysisScreen({super.key});

  @override
  State<BehaviourAnalysisScreen> createState() => _BehaviourAnalysisScreenState();
}

class _BehaviourAnalysisScreenState extends State<BehaviourAnalysisScreen> {
  late Future<({List<_GraphNode> nodes, List<_GraphEdge> edges})> _graphFuture;
  late Future<List<_Episode>> _episodesFuture;
  Object? _lastSeenPipelineResult;
  SessionProvider? _session;
  final _graphTransformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
    _session = context.read<SessionProvider>();
    _session!.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _graphTransformController.dispose();
    super.dispose();
  }

  // A session keeps running in the background regardless of which screen is
  // in the foreground. BE runs on every single pipeline tick with no gating
  // (unlike ecom/safety - see pipeline_coordinator.dart), so "refresh
  // whenever BE has just processed" means "refresh on every new tick": a new
  // PipelineResult instance is what _runPipeline() produces each time it
  // completes, so comparing identity (not equality) against the previously
  // seen one is exactly that signal, without needing a separate counter.
  void _onSessionChanged() {
    final current = _session?.lastPipelineResult;
    if (current == null || identical(current, _lastSeenPipelineResult)) return;
    _lastSeenPipelineResult = current;
    if (mounted) setState(_load);
  }

  void _load() {
    _graphFuture = _fetchGraph();
    _episodesFuture = _fetchEpisodes();
  }

  // Always the real authenticated account - NOT the live pipeline's echoed
  // BE user_id. SessionProvider is a single app-lifetime instance (see
  // main.dart), so lastPipelineResult can still hold a PREVIOUS account's
  // result right after switching users on the same app instance; preferring
  // it here showed one account's graph under a different, freshly-logged-in
  // account. Confirmed server-side that /be/analytics/graph does correctly
  // differentiate by user_id once a real account has session history.
  dynamic _resolveUserId() => context.read<AuthProvider>().userId;

  Future<({List<_GraphNode> nodes, List<_GraphEdge> edges})> _fetchGraph() async {
    final userId = _resolveUserId();
    final url = Uri.parse(EnvConfig.behaviourGetGraphUrl).replace(
      queryParameters: userId != null ? {'user_id': '$userId'} : null,
    );
    AppLogger.log('BE_GRAPH_REQUEST', 'GET $url');
    final response = await http.get(url, headers: {'Accept': 'application/json'});
    AppLogger.log('BE_GRAPH_RESPONSE', '${response.statusCode} ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Graph request failed: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final nodes = ((body['nodes'] as List?) ?? const [])
        .whereType<Map>()
        .map((n) => _GraphNode.parse(n.cast<String, dynamic>()))
        .toList();
    final edges = ((body['edges'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => _GraphEdge.parse(e.cast<String, dynamic>()))
        .toList();
    return (nodes: nodes, edges: edges);
  }

  Future<List<_Episode>> _fetchEpisodes() async {
    final userId = _resolveUserId();
    final url = Uri.parse(EnvConfig.behaviourGetEpisodesUrl).replace(
      queryParameters: userId != null ? {'user_id': '$userId'} : null,
    );
    AppLogger.log('BE_EPISODES_REQUEST', 'GET $url');
    final response = await http.get(url, headers: {'Accept': 'application/json'});
    AppLogger.log('BE_EPISODES_RESPONSE', '${response.statusCode} ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Episodes request failed: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (body['episodes'] ?? body['data'] ?? body['results']) as List?;
    return (list ?? const []).whereType<Map>().map((e) => _Episode.parse(e.cast<String, dynamic>())).toList();
  }

  Future<void> _uploadScheduleFile() async {
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
          final parsed = ScheduleParserService.parseFile(bytes, file.name);
          if (!mounted) return;
          final auth = context.read<AuthProvider>();
          final session = context.read<SessionProvider>();
          final uid = await auth.resolveUserId() ?? session.userId ?? 0;
          await ScheduleParserService.saveSchedule(uid is int ? uid : int.tryParse('$uid') ?? 0, parsed);

          // Upload to POST /api/v1/be/schedule/{user_id}/upload
          final targetUid = uid != 0 ? uid : 'default_user';
          session.behaviourEngineClient.uploadScheduleFile(
            userId: targetUid,
            bytes: bytes,
            fileName: file.name,
          );

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploaded & synced ${parsed.totalActivities} routine slots from ${file.name}'),
              backgroundColor: AppColors.successTint,
            ),
          );

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WeeklyScheduleScreen(initialSchedule: parsed),
            ),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not read file data. Please try again.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load schedule: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showSyncScheduleModal() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accentTint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.sync, color: AppColors.accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weekly Routine & Schedule',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Sync schedule with Behaviour Engine',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    tileColor: AppColors.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.border),
                    ),
                    leading: Icon(Icons.calendar_month_outlined, color: AppColors.accent),
                    title: Text('View Weekly Calendar Timeline', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Inspect & edit your hour-by-hour activity cards', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const WeeklyScheduleScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    tileColor: AppColors.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.border),
                    ),
                    leading: Icon(Icons.upload_file_outlined, color: AppColors.success),
                    title: Text('Upload Weekly Schedule (Excel / CSV)', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Import .xlsx, .xls or .csv spreadsheet file', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _uploadScheduleFile();
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    tileColor: AppColors.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.border),
                    ),
                    leading: Icon(Icons.inventory_2_outlined, color: AppColors.accent),
                    title: Text('Manage Owned Objects & Products', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Batch-remove owned items via BE', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    onTap: () {
                      Navigator.pop(ctx);
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => SafeArea(
                          child: Container(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(context).size.height * 0.88,
                            ),
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                              left: 16,
                              right: 16,
                              top: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 4,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: AppColors.border,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const OwnedObjectsCard(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    tileColor: AppColors.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.border),
                    ),
                    leading: Icon(Icons.refresh, color: AppColors.accentStrong),
                    title: Text('Refresh Behaviour Graph & Episodes', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Re-fetch live taxonomy from BE backend', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(_load);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _selectedCategory;
  BoxConstraints? _lastViewportConstraints;

  void _resetZoom({BoxConstraints? constraints}) {
    final c = constraints ?? _lastViewportConstraints;
    if (c != null && c.maxWidth > 0 && c.maxHeight > 0) {
      const canvasDim = 700.0;
      final scale = min(c.maxWidth / canvasDim, c.maxHeight / canvasDim) * 0.95;
      final tx = (c.maxWidth - canvasDim * scale) / 2;
      final ty = (c.maxHeight - canvasDim * scale) / 2;

      _graphTransformController.value = Matrix4.translationValues(tx, ty, 0.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0);
    } else {
      _graphTransformController.value = Matrix4.identity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Behaviour Analysis',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Sync Weekly Schedule',
            icon: Icon(Icons.sync, color: AppColors.accent, size: 22),
            onPressed: _showSyncScheduleModal,
          ),
          IconButton(
            tooltip: 'Refresh Graph',
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh, size: 22),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _graphSection()),
          _episodesSection(),
        ],
      ),
    );
  }

  Widget _graphSection() {
    return FutureBuilder(
      future: _graphFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load the behaviour graph.', style: TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: () => setState(_load), child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data!;
        if (data.nodes.isEmpty) {
          return Center(child: Text('No behaviour graph data yet.', style: TextStyle(color: AppColors.textSecondary)));
        }

        // Build list of unique primary category branches
        final hub = data.nodes.firstWhere((n) => n.isHub || n.id == 'user', orElse: () => data.nodes.first);
        final branchNodes = data.nodes.where((n) => n.id != hub.id && (n.isHub || data.edges.any((e) => (e.from == hub.id && e.to == n.id) || (e.to == hub.id && e.from == n.id)))).toList();
        
        // If branch nodes empty, pick top level nodes
        final categoryList = <String>['All'];
        for (final b in branchNodes) {
          final (_, label) = _splitLeadingEmoji(b.label);
          if (!categoryList.contains(label)) categoryList.add(label);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hub_outlined, color: AppColors.accent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Interactive Taxonomy Map · Pinch to zoom, drag to pan. Tap filter pills below to focus.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (_lastViewportConstraints == null ||
                          _lastViewportConstraints!.maxWidth != constraints.maxWidth ||
                          _lastViewportConstraints!.maxHeight != constraints.maxHeight) {
                        _lastViewportConstraints = constraints;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _resetZoom(constraints: constraints);
                        });
                      }

                      return InteractiveViewer(
                        transformationController: _graphTransformController,
                        minScale: 0.15,
                        maxScale: 3.5,
                        boundaryMargin: const EdgeInsets.all(300),
                        constrained: false,
                        child: _BehaviourGraph(
                          nodes: data.nodes,
                          edges: data.edges,
                          canvasSize: const Size(700, 700),
                          selectedCategory: _selectedCategory,
                          onNodeTapped: (nodeId) {
                            final node = data.nodes.firstWhere((n) => n.id == nodeId, orElse: () => hub);
                            final (_, label) = _splitLeadingEmoji(node.label);
                            setState(() {
                              if (_selectedCategory == label) {
                                _selectedCategory = null;
                              } else {
                                _selectedCategory = label;
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter_graph',
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.accentStrong,
                      elevation: 2,
                      tooltip: 'Fit Full Map',
                      onPressed: () => _resetZoom(),
                      child: const Icon(Icons.fit_screen_outlined, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Category Filter Pills
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: categoryList.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = categoryList[index];
                  final isSelected = (_selectedCategory == null && cat == 'All') || (_selectedCategory == cat);
                  
                  return FilterChip(
                    label: Text(
                      cat == 'All' ? 'All Signals (${data.nodes.length})' : cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.surfaceMuted,
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: isSelected ? AppColors.accentStrong : AppColors.border,
                      width: 1.2,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = cat == 'All' ? null : cat;
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Widget _episodesSection() {
    return FutureBuilder<List<_Episode>>(
      future: _episodesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: 80,
            child: Center(
              child: Text('Could not load episodes: ${snapshot.error}', style: TextStyle(color: AppColors.danger, fontSize: 12), textAlign: TextAlign.center),
            ),
          );
        }
        final episodes = snapshot.data ?? const [];
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Behaviour episodes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  if (episodes.isNotEmpty)
                    Text('${episodes.length} recorded', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              if (episodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No episode history recorded yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                )
              else
                SizedBox(
                  height: 140,
                  child: PageView.builder(
                    controller: PageController(viewportFraction: 0.84),
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _EpisodeCard(
                          episode: episode,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _EpisodeFullScreenPage(episode: episode))),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final _Episode episode;
  final VoidCallback onTap;

  const _EpisodeCard({required this.episode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    episode.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accentStrong, fontSize: 13),
                  ),
                ),
                Icon(Icons.fullscreen, size: 16, color: AppColors.textSecondary),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                episode.summary.isEmpty ? (episode.primaryObject ?? 'No summary') : episode.summary,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5, height: 1.3),
              ),
            ),
            const SizedBox(height: 6),
            Text('${episode.durationLabel} · ${episode.timeLabel}', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _EpisodeFullScreenPage extends StatelessWidget {
  final _Episode episode;

  const _EpisodeFullScreenPage({required this.episode});

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(episode.type)),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        boundaryMargin: const EdgeInsets.all(100),
        child: Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _row('Activity', episode.type),
                _row('Summary', episode.summary.isEmpty ? '—' : episode.summary),
                _row('Primary object', episode.primaryObject ?? '—'),
                _row('Duration', episode.durationLabel),
                _row('Time', episode.timeLabel),
                if (episode.avgHesitation != null) _row('Avg. hesitation', episode.avgHesitation!.toStringAsFixed(2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _getSmartEmojiForNode(String label) {
  final l = label.toLowerCase();
  if (l.contains('bingo') || l.contains('chip') || l.contains('snack')) return '🥔';
  if (l.contains('cadbur') || l.contains('choc')) return '🍫';
  if (l.contains('dove') || l.contains('soap') || l.contains('wash')) return '🧼';
  if (l.contains('cola') || l.contains('drink') || l.contains('bever')) return '🥤';
  if (l.contains('kindle') || l.contains('book')) return '📖';
  if (l.contains('office') || l.contains('work')) return '🏢';
  if (l.contains('restaurant') || l.contains('cafe') || l.contains('food')) return '🍽️';
  if (l.contains('kitchen')) return '🍳';
  if (l.contains('indoor')) return '🏠';
  if (l.contains('store') || l.contains('market') || l.contains('shop')) return '🛍️';
  if (l.contains('transit') || l.contains('car') || l.contains('bus')) return '🚗';
  if (l.contains('like') || l.contains('pref')) return '❤️';
  if (l.contains('object')) return '👁️';
  if (l.contains('place')) return '📍';
  if (l.contains('activ')) return '🏃';
  if (l.contains('metric') || l.contains('base')) return '🧠';
  if (l.contains('commerce') || l.contains('cart')) return '🛒';
  return '🏷️';
}

class _BehaviourGraph extends StatelessWidget {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final Size canvasSize;
  final String? selectedCategory;
  final ValueChanged<String>? onNodeTapped;

  const _BehaviourGraph({
    required this.nodes,
    required this.edges,
    required this.canvasSize,
    this.selectedCategory,
    this.onNodeTapped,
  });

  Map<String, Offset> _layout() {
    if (nodes.isEmpty) return {};
    return _computeHierarchicalOrbitLayout();
  }

  Map<String, Offset> _computeHierarchicalOrbitLayout() {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final positions = <String, Offset>{};

    // 1. Identify Hub
    final hub = nodes.firstWhere((n) => n.isHub || n.id == 'user', orElse: () => nodes.first);
    positions[hub.id] = center;

    // 2. Build adjacency
    final childrenOf = <String, List<String>>{};
    final parentOf = <String, String>{};
    for (final e in edges) {
      if (e.from == hub.id) {
        childrenOf.putIfAbsent(hub.id, () => []).add(e.to);
        parentOf[e.to] = hub.id;
      } else if (e.to == hub.id) {
        childrenOf.putIfAbsent(hub.id, () => []).add(e.from);
        parentOf[e.from] = hub.id;
      } else {
        childrenOf.putIfAbsent(e.from, () => []).add(e.to);
        parentOf[e.to] = e.from;
      }
    }

    // 3. Primary Branch Nodes (Ring 1)
    var branchIds = (childrenOf[hub.id] ?? []).toSet().toList();
    final remainingNodes = nodes.where((n) => n.id != hub.id && !branchIds.contains(n.id)).map((n) => n.id).toList();

    if (branchIds.isEmpty && nodes.length > 1) {
      final sorted = nodes.where((n) => n.id != hub.id).toList();
      branchIds = sorted.take(6).map((n) => n.id).toList();
      remainingNodes.removeWhere((id) => branchIds.contains(id));
    }

    final minDim = min(canvasSize.width, canvasSize.height);
    final r1 = (minDim * 0.22).clamp(110.0, 160.0); // Ring 1: Primary branches
    final r2 = (minDim * 0.40).clamp(200.0, 290.0); // Ring 2: Child leaves

    final branchCount = branchIds.length;
    for (var i = 0; i < branchCount; i++) {
      final bId = branchIds[i];
      final angle = (2 * pi * i) / max(1, branchCount) - (pi / 2);
      final branchPos = center + Offset(r1 * cos(angle), r1 * sin(angle));
      positions[bId] = branchPos;

      // Children under this branch
      final childIds = (childrenOf[bId] ?? []).where((cId) => cId != hub.id && !branchIds.contains(cId)).toList();
      final childCount = childIds.length;
      if (childCount > 0) {
        final arcSpread = min(pi / 2.2, max(0.35, (childCount - 1) * 0.30));
        final startAngle = angle - arcSpread / 2;
        for (var j = 0; j < childCount; j++) {
          final childAngle = childCount == 1 ? angle : startAngle + (arcSpread * j) / (childCount - 1);
          positions[childIds[j]] = center + Offset(r2 * cos(childAngle), r2 * sin(childAngle));
          remainingNodes.remove(childIds[j]);
        }
      }
    }

    // 4. Place remaining dynamic/orphan nodes in outer orbit
    if (remainingNodes.isNotEmpty) {
      final orphanCount = remainingNodes.length;
      for (var i = 0; i < orphanCount; i++) {
        final orphanId = remainingNodes[i];
        final angle = (2 * pi * i) / orphanCount;
        positions[orphanId] = center + Offset(r2 * 1.15 * cos(angle), r2 * 1.15 * sin(angle));
      }
    }

    // 5. Force-directed repulsion pass (push overlapping nodes apart)
    final allIds = positions.keys.toList();
    for (int iter = 0; iter < 45; iter++) {
      for (int i = 0; i < allIds.length; i++) {
        for (int j = i + 1; j < allIds.length; j++) {
          final idA = allIds[i];
          final idB = allIds[j];
          if (idA == hub.id || idB == hub.id) continue;

          final posA = positions[idA]!;
          final posB = positions[idB]!;
          final delta = posA - posB;
          final dist = delta.distance;
          const minDist = 90.0;
          if (dist < minDist && dist > 0.001) {
            final push = (delta / dist) * ((minDist - dist) * 0.45);
            positions[idA] = positions[idA]! + push;
            positions[idB] = positions[idB]! - push;
          }
        }
      }
    }

    // 6. Clamp to canvas margins
    const pad = 48.0;
    return {
      for (final entry in positions.entries)
        entry.key: Offset(
          entry.value.dx.clamp(pad, canvasSize.width - pad),
          entry.value.dy.clamp(pad, canvasSize.height - pad),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: canvasSize.width,
      height: canvasSize.height,
      child: CustomPaint(
        painter: _GraphPainter(
          nodes: nodes,
          edges: edges,
          positions: _layout(),
          selectedCategory: selectedCategory,
          isDark: AppColors.isDark,
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final Map<String, Offset> positions;
  final String? selectedCategory;
  final bool isDark;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.positions,
    this.selectedCategory,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeById = {for (final n in nodes) n.id: n};
    final hub = nodes.firstWhere((n) => n.isHub || n.id == 'user', orElse: () => nodes.first);
    final hubPos = positions[hub.id] ?? Offset(size.width / 2, size.height / 2);

    // Determine node active states based on category filter
    final isCategoryFiltered = selectedCategory != null && selectedCategory != 'All';

    // Draw Edges with smooth lines and glow
    for (final edge in edges) {
      final from = nodeById[edge.from];
      final to = nodeById[edge.to];
      if (from == null || to == null) continue;
      final p1 = positions[from.id];
      final p2 = positions[to.id];
      if (p1 == null || p2 == null) continue;

      bool edgeActive = true;
      if (isCategoryFiltered) {
        final (_, fromLabel) = _splitLeadingEmoji(from.label);
        final (_, toLabel) = _splitLeadingEmoji(to.label);
        edgeActive = fromLabel == selectedCategory || toLabel == selectedCategory || from.id == hub.id || to.id == hub.id;
      }

      final edgeOpacity = edgeActive ? 0.65 : 0.12;
      final strokeWidth = edgeActive ? 2.2 : 1.0;
      final edgePaint = Paint()
        ..color = AppColors.accent.withValues(alpha: edgeOpacity)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      // Curved bezier path
      final midPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      final controlPoint = Offset(midPoint.dx + (p1.dy - p2.dy) * 0.08, midPoint.dy + (p2.dx - p1.dx) * 0.08);

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, p2.dx, p2.dy);

      canvas.drawPath(path, edgePaint);

      // Arrow head
      final dir = p2 - controlPoint;
      final len = dir.distance;
      if (len > 0) {
        final unit = dir / len;
        final arrowBase = p2 - unit * 22;
        final normal = Offset(-unit.dy, unit.dx);
        final arrowPath = Path()
          ..moveTo(p2.dx - unit.dx * 10, p2.dy - unit.dy * 10)
          ..lineTo((arrowBase + normal * 5).dx, (arrowBase + normal * 5).dy)
          ..lineTo((arrowBase - normal * 5).dx, (arrowBase - normal * 5).dy)
          ..close();
        canvas.drawPath(arrowPath, Paint()..color = AppColors.accent.withValues(alpha: edgeOpacity));
      }
    }

    // Draw Nodes
    for (final node in nodes) {
      final center = positions[node.id];
      if (center == null) continue;
      final isHub = node.isHub;
      final (rawEmoji, text) = _splitLeadingEmoji(node.label);
      final emoji = rawEmoji ?? (isHub ? null : _getSmartEmojiForNode(text));

      bool nodeActive = true;
      if (isCategoryFiltered && !isHub) {
        final (_, nodeCategory) = _splitLeadingEmoji(node.label);
        nodeActive = nodeCategory.toLowerCase().contains(selectedCategory!.toLowerCase()) ||
                     selectedCategory!.toLowerCase().contains(nodeCategory.toLowerCase()) ||
                     text.toLowerCase().contains(selectedCategory!.toLowerCase());
      }

      final nodeOpacity = nodeActive ? 1.0 : 0.20;
      final radius = (isHub ? 42.0 : (emoji != null ? 24.0 : 18.0));

      // Glow behind active nodes
      if (nodeActive) {
        canvas.drawCircle(
          center,
          radius + 6,
          Paint()
            ..color = (isHub ? AppColors.accent : node.border).withValues(alpha: isHub ? 0.35 : 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }

      // Background fill shader
      final fillShader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.95,
        colors: [
          Color.lerp(node.background, Colors.white, isHub ? 0.3 : 0.15)!.withValues(alpha: nodeOpacity),
          node.background.withValues(alpha: nodeOpacity),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, Paint()..shader = fillShader);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = (isHub ? AppColors.accentStrong : node.border).withValues(alpha: nodeOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHub ? 3.0 : 2.0,
      );

      // Node Icon / Emoji inside the circle
      if (emoji != null) {
        final emojiTp = TextPainter(
          text: TextSpan(text: emoji, style: TextStyle(fontSize: radius * (isHub ? 0.8 : 0.95))),
          textDirection: TextDirection.ltr,
        )..layout();
        emojiTp.paint(canvas, center - Offset(emojiTp.width / 2, emojiTp.height / 2));
      }

      // Node Text
      if (isHub) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(color: node.fontColor, fontWeight: FontWeight.w800, fontSize: 13),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: radius * 1.8);
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      } else if (text.isNotEmpty) {
        // Calculate radial direction vector from center to position label without colliding
        final delta = center - hubPos;
        final dist = delta.distance;
        final unit = dist > 0 ? (delta / dist) : const Offset(0, 1);

        final captionTp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: isDark ? Colors.white : AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 110);

        // Position caption pill along radial direction
        final captionDist = radius + 12 + captionTp.height / 2;
        final captionCenter = center + Offset(unit.dx * captionDist, unit.dy * captionDist);

        final pillRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: captionCenter,
            width: captionTp.width + 14,
            height: captionTp.height + 8,
          ),
          const Radius.circular(8),
        );

        final pillBg = isDark ? const Color(0xFF1E2330).withValues(alpha: nodeOpacity) : const Color(0xFFFAF7F2).withValues(alpha: nodeOpacity);
        final pillBdr = (isHub ? AppColors.accent : AppColors.border).withValues(alpha: nodeOpacity);

        // Drop shadow for pill
        if (nodeActive) {
          canvas.drawRRect(
            pillRect.shift(const Offset(0, 2)),
            Paint()..color = Colors.black.withValues(alpha: 0.25),
          );
        }

        canvas.drawRRect(pillRect, Paint()..color = pillBg);
        canvas.drawRRect(
          pillRect,
          Paint()
            ..color = pillBdr
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );

        captionTp.paint(canvas, captionCenter - Offset(captionTp.width / 2, captionTp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.edges != edges ||
      oldDelegate.selectedCategory != selectedCategory ||
      oldDelegate.isDark != isDark;
}

