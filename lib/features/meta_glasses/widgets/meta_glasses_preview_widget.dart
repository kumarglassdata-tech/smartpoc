import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../../../services/meta_glasses_service.dart';

class MetaGlassesPreviewWidget extends StatelessWidget {
  final VoidCallback? onStreamingStarted;
  final VoidCallback? onStreamingStopped;
  final bool showControls;

  const MetaGlassesPreviewWidget({
    super.key,
    this.onStreamingStarted,
    this.onStreamingStopped,
    this.showControls = true,
  });

  @override
  Widget build(BuildContext context) {
    final service = MetaGlassesService.instance;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Viewfinder Aspect Box
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Live Frame Render
                  ValueListenableBuilder(
                    valueListenable: service.currentFrameNotifier,
                    builder: (context, frameBytes, _) {
                      if (frameBytes == null || frameBytes.isEmpty) {
                        return Center(
                          child: ValueListenableBuilder(
                            valueListenable: service.statusNotifier,
                            builder: (context, status, _) {
                              if (status == MetaGlassesStatus.connecting ||
                                  status == MetaGlassesStatus.registering) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: AppColors.accent,
                                      strokeWidth: 2.5,
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      service.statusMessageNotifier.value ?? 'Connecting to glasses...',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.visibility_outlined,
                                    size: 48,
                                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Ray-Ban Meta Viewfinder',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    status == MetaGlassesStatus.connected
                                        ? 'Glasses ready. Tap Start Stream below.'
                                        : 'Pair glasses via Meta View app to start.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      }

                      return Image.memory(
                        frameBytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true, // Prevents flickering between frames
                      );
                    },
                  ),

                  // Top Status Pill
                  Positioned(
                    top: 12,
                    left: 12,
                    child: ValueListenableBuilder(
                      valueListenable: service.statusNotifier,
                      builder: (context, status, _) {
                        Color badgeColor = AppColors.surfaceMuted;
                        Color dotColor = AppColors.textSecondary;
                        String label = 'Disconnected';

                        switch (status) {
                          case MetaGlassesStatus.streaming:
                            badgeColor = Colors.black.withValues(alpha: 0.6);
                            dotColor = AppColors.success;
                            label = 'LIVE STREAM';
                            break;
                          case MetaGlassesStatus.connected:
                            badgeColor = Colors.black.withValues(alpha: 0.6);
                            dotColor = AppColors.accent;
                            label = 'READY';
                            break;
                          case MetaGlassesStatus.connecting:
                          case MetaGlassesStatus.registering:
                            badgeColor = Colors.black.withValues(alpha: 0.6);
                            dotColor = Colors.amber;
                            label = 'CONNECTING';
                            break;
                          case MetaGlassesStatus.registered:
                            badgeColor = Colors.black.withValues(alpha: 0.6);
                            dotColor = AppColors.accentStrong;
                            label = 'REGISTERED';
                            break;
                          case MetaGlassesStatus.error:
                            badgeColor = Colors.black.withValues(alpha: 0.6);
                            dotColor = AppColors.danger;
                            label = 'ERROR';
                            break;
                          case MetaGlassesStatus.disconnected:
                            badgeColor = Colors.black.withValues(alpha: 0.6);
                            dotColor = AppColors.textSecondary;
                            label = 'STANDBY';
                            break;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Top Right: Glasses Battery Level Indicator
                  Positioned(
                    top: 12,
                    right: 12,
                    child: ValueListenableBuilder<int?>(
                      valueListenable: service.batteryLevelNotifier,
                      builder: (context, battery, _) {
                        if (battery == null || battery < 0) return const SizedBox.shrink();

                        final Color batteryColor = battery > 50
                            ? AppColors.success
                            : battery > 20
                                ? Colors.amber
                                : AppColors.danger;

                        final IconData batteryIcon = battery > 80
                            ? Icons.battery_full_rounded
                            : battery > 60
                                ? Icons.battery_6_bar_rounded
                                : battery > 40
                                    ? Icons.battery_4_bar_rounded
                                    : battery > 20
                                        ? Icons.battery_2_bar_rounded
                                        : Icons.battery_alert_rounded;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(batteryIcon, color: batteryColor, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '$battery%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Control Bar (if enabled)
          if (showControls)
            Padding(
              padding: const EdgeInsets.all(14),
              child: ValueListenableBuilder(
                valueListenable: service.statusNotifier,
                builder: (context, status, _) {
                  final isStreaming = status == MetaGlassesStatus.streaming;
                  final isBusy = status == MetaGlassesStatus.connecting || status == MetaGlassesStatus.registering;

                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () async {
                                  await service.startRegistration();
                                },
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('Pair / Register'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isBusy
                              ? null
                              : () async {
                                  if (isStreaming) {
                                    await service.stopCameraStream();
                                    onStreamingStopped?.call();
                                  } else {
                                    final ok = await service.startCameraStream();
                                    if (ok) onStreamingStarted?.call();
                                  }
                                },
                          style: isStreaming
                              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                              : null,
                          icon: Icon(
                            isStreaming ? Icons.stop_rounded : Icons.videocam_rounded,
                            size: 18,
                          ),
                          label: Text(isStreaming ? 'Stop' : 'Start Stream'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
