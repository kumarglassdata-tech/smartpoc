import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'app_logger.dart';
import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'env_config.dart';
import 'session/session_provider.dart';

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
  Size? _lastCenteredViewportSize;

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

  // InteractiveViewer aligns an oversized child to the viewport's top-left
  // by default rather than centering it - the graph canvas (680x560, see
  // _BehaviourGraph._canvasSize) is wider than almost any phone viewport, so
  // without this the hub renders pinned to the left edge with everything
  // else cut off on the right instead of centered. Re-centers once per
  // distinct viewport size (e.g. after a rotation), not on every rebuild.
  void _centerGraphIfNeeded(Size viewportSize) {
    if (_lastCenteredViewportSize == viewportSize) return;
    _lastCenteredViewportSize = viewportSize;
    const canvasCenter = Offset(340, 280); // half of _BehaviourGraph._canvasSize
    final dx = viewportSize.width / 2 - canvasCenter.dx;
    final dy = viewportSize.height / 2 - canvasCenter.dy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _graphTransformController.value = Matrix4.identity()..translateByDouble(dx, dy, 0, 1);
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Behaviour Analysis'),
        actions: [IconButton(onPressed: () => setState(_load), icon: const Icon(Icons.refresh))],
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
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'How the Behaviour Engine organizes what it tracks about you - the hub is your '
                  'profile, each branch is a category of signal it collects from your sessions. '
                  'Pinch to zoom, drag to pan.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _centerGraphIfNeeded(constraints.biggest);
                  return InteractiveViewer(
                    transformationController: _graphTransformController,
                    minScale: 0.5,
                    maxScale: 4,
                    boundaryMargin: const EdgeInsets.all(200),
                    child: _BehaviourGraph(nodes: data.nodes, edges: data.edges),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: data.nodes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final node = data.nodes[index];
                  // Hub chip gets accent fill; branches get surface+border.
                  final isHub = node.isHub;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isHub ? AppColors.accentTint : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isHub ? AppColors.accent : AppColors.border,
                        width: isHub ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      node.label,
                      style: TextStyle(
                        color: isHub ? AppColors.accentStrong : AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: isHub ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
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
          return const SizedBox(height: 190, child: Center(child: CircularProgressIndicator()));
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Behaviour episodes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              if (episodes.isEmpty)
                Text('No episode history recorded yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
              else
                SizedBox(
                  height: 150,
                  child: PageView.builder(
                    controller: PageController(viewportFraction: 0.82),
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

// Full-screen pinch-to-zoom detail view for a single episode - same
// InteractiveViewer pattern as the graph above, so an episode's details are
// as readable/zoomable as the graph nodes are.
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

class _BehaviourGraph extends StatelessWidget {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;

  const _BehaviourGraph({required this.nodes, required this.edges});

  static const _canvasSize = Size(680, 560);

  // /be/analytics/graph only guarantees x/y on the 6 fixed taxonomy branches -
  // the real, dynamic nodes (detected objects, behavioural states, places)
  // come back with none at all. Project real positions when every node has
  // one; otherwise fall back to a hub-and-spoke layout driven by actual
  // connectivity (highest-degree node at the center, the rest spaced evenly
  // around it) - mirrors C:\Dev\smartglass_flutter's same fallback.
  Map<String, Offset> _layout() {
    final hasAllPositions = nodes.every((n) => n.x != null && n.y != null);
    return hasAllPositions ? _projectGivenPositions() : _computeConnectivityLayout();
  }

  Map<String, Offset> _projectGivenPositions() {
    const paddingX = 70.0;
    const paddingTop = 70.0;
    const paddingBottom = 110.0;
    final xs = nodes.map((n) => n.x!);
    final ys = nodes.map((n) => n.y!);
    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);
    final width = maxX == minX ? 1.0 : maxX - minX;
    final height = maxY == minY ? 1.0 : maxY - minY;
    final scale = min((_canvasSize.width - paddingX * 2) / width, (_canvasSize.height - paddingTop - paddingBottom) / height);
    return {
      for (final n in nodes) n.id: Offset(paddingX + (n.x! - minX) * scale, paddingTop + (n.y! - minY) * scale),
    };
  }

  Map<String, Offset> _computeConnectivityLayout() {
    final degree = <String, int>{for (final n in nodes) n.id: 0};
    for (final e in edges) {
      if (degree.containsKey(e.from)) degree[e.from] = degree[e.from]! + 1;
      if (degree.containsKey(e.to)) degree[e.to] = degree[e.to]! + 1;
    }
    final sorted = [...nodes]..sort((a, b) => degree[b.id]!.compareTo(degree[a.id]!));
    final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
    final radius = min(_canvasSize.width, _canvasSize.height) / 2 - 70;

    final positions = <String, Offset>{sorted.first.id: center};
    final rest = sorted.skip(1).toList();
    for (var i = 0; i < rest.length; i++) {
      final angle = (2 * pi * i) / rest.length;
      positions[rest[i].id] = center + Offset(radius * cos(angle), radius * sin(angle));
    }
    return positions;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _canvasSize.width,
      height: _canvasSize.height,
      child: CustomPaint(painter: _GraphPainter(nodes: nodes, edges: edges, positions: _layout(), isDark: AppColors.isDark)),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final Map<String, Offset> positions;
  final bool isDark;

  _GraphPainter({required this.nodes, required this.edges, required this.positions, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final nodeById = {for (final n in nodes) n.id: n};

    for (final edge in edges) {
      final from = nodeById[edge.from];
      final to = nodeById[edge.to];
      if (from == null || to == null) continue;
      final p1 = positions[from.id];
      final p2 = positions[to.id];
      if (p1 == null || p2 == null) continue;

      canvas.drawLine(p1, p2, Paint()..color = edge.color..strokeWidth = 2..style = PaintingStyle.stroke);

      final dir = p2 - p1;
      final len = dir.distance;
      if (len > 0) {
        final unit = dir / len;
        final arrowBase = p2 - unit * 20;
        final normal = Offset(-unit.dy, unit.dx);
        final path = Path()
          ..moveTo(p2.dx - unit.dx * 8, p2.dy - unit.dy * 8)
          ..lineTo((arrowBase + normal * 6).dx, (arrowBase + normal * 6).dy)
          ..lineTo((arrowBase - normal * 6).dx, (arrowBase - normal * 6).dy)
          ..close();
        canvas.drawPath(path, Paint()..color = edge.color);
      }
    }

    for (final node in nodes) {
      final center = positions[node.id];
      if (center == null) continue;
      final isHub = node.isHub;
      final radius = (node.size.clamp(10, 60)) * (isHub ? 1.35 : 1.15);
      final (emoji, text) = _splitLeadingEmoji(node.label);

      // Soft glow behind the bubble, tinted with the node's own color.
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = node.border.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );

      final fillShader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.95,
        colors: [Color.lerp(node.background, Colors.white, 0.4)!, node.background],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, Paint()..shader = fillShader);
      canvas.drawCircle(center, radius, Paint()..color = node.border..style = PaintingStyle.stroke..strokeWidth = 2.5);

      if (emoji != null) {
        final emojiTp = TextPainter(
          text: TextSpan(text: emoji, style: TextStyle(fontSize: radius * 0.95)),
          textDirection: TextDirection.ltr,
        )..layout();
        emojiTp.paint(canvas, center - Offset(emojiTp.width / 2, emojiTp.height / 2));
      }

      // Only the hub's label is long enough to need real wrapping and has
      // the radius to fit it (~47px) - every other node (including the
      // dynamic ones with no fixed x/y, which tend to have longer labels
      // like "Purchase Consideration" on a much smaller ~16px radius) reads
      // better as a caption pill below the bubble than text crammed inside it.
      if (isHub) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: TextStyle(color: node.fontColor, fontWeight: FontWeight.w800, fontSize: 14)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: radius * 1.6);
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      } else if (emoji == null || text.isNotEmpty) {
        final captionTp = TextPainter(
          text: TextSpan(text: text, style: TextStyle(color: node.fontColor, fontSize: 12, fontWeight: FontWeight.w700)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 110);
        final captionCenter = Offset(center.dx, center.dy + radius + 10 + captionTp.height / 2);
        final pillRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: captionCenter, width: captionTp.width + 16, height: captionTp.height + 8),
          const Radius.circular(10),
        );
        // Caption pill: warm surface + border (no hardcoded white/dark)
        final pillBg = isDark ? const Color(0xFF2A2420) : const Color(0xFFFBF6EC);
        final pillBdr = isDark ? const Color(0xFF3A342C) : const Color(0xFFEAE0CF);
        canvas.drawRRect(pillRect, Paint()..color = pillBg);
        canvas.drawRRect(pillRect, Paint()..color = pillBdr..style = PaintingStyle.stroke..strokeWidth = 1.2);
        captionTp.paint(canvas, captionCenter - Offset(captionTp.width / 2, captionTp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.nodes != nodes || oldDelegate.edges != edges || oldDelegate.isDark != isDark;
}
