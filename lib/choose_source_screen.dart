import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'live_session_screen.dart';
import 'particle_background.dart';
import 'session/session_provider.dart';
import 'sources/source_manager.dart';
import 'sources/video_upload_source_adapter.dart';

const _imageExtensions = ['jpg', 'jpeg', 'png'];
const _videoExtensions = ['mp4', 'webm', 'mov', 'ogg', 'ogv'];

class ChooseSourceScreen extends StatefulWidget {
  const ChooseSourceScreen({super.key});

  @override
  State<ChooseSourceScreen> createState() => _ChooseSourceScreenState();
}

class _ChooseSourceScreenState extends State<ChooseSourceScreen> {
  SourceType _selected = SourceType.phone;
  bool _isStarting = false;
  bool _isPicking = false;
  PlatformFile? _pickedFile;
  String? _error;

  Future<void> _pickFile() async {
    setState(() {
      _isPicking = true;
      _error = null;
    });
    try {
      // FilePicker on web uses a hidden <input type="file"> internally.
      // Calling it outside a user-gesture context can throw a
      // LateInitializationError if its internal state isn't ready yet -
      // retrying once after a short delay resolves it.
      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [..._imageExtensions, ..._videoExtensions],
          withData: true,
        );
      } catch (_) {
        // Second attempt after a tick - handles web late-init edge case.
        await Future.delayed(const Duration(milliseconds: 80));
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [..._imageExtensions, ..._videoExtensions],
          withData: true,
        );
      }
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedFile = result!.files.first);
      }
    } catch (error) {
      final msg = '$error';
      setState(
        () => _error = msg.contains('LateInitializationError')
            ? 'File picker not ready — please try again.'
            : 'Could not open file picker: $error',
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _beginSession() async {
    if (_selected == SourceType.videoUpload && _pickedFile?.bytes == null) {
      setState(() => _error = 'Choose a photo or video file first.');
      return;
    }
    setState(() {
      _isStarting = true;
      _error = null;
    });
    final session = context.read<SessionProvider>();
    try {
      if (_selected == SourceType.videoUpload) {
        final file = _pickedFile!;
        final ext = (file.extension ?? '').toLowerCase();
        final adapter =
            session.sourceManager.adapterFor(SourceType.videoUpload)
                as VideoUploadSourceAdapter;
        adapter.setUploadedFile(
          file.bytes!,
          file.name,
          _imageExtensions.contains(ext),
        );
      }
      await session.sourceManager.switchSource(_selected);
      if (!session.state.isConnected) await session.connect();
      if (!session.state.isConnected) {
        throw Exception(session.state.lastError ?? 'Connect failed');
      }
      await session.startRuntime();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LiveSessionScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Widget _sourceTile({
    required SourceType type,
    required IconData icon,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    final selected = _selected == type;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled
          ? () => setState(() => _selected = type)
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Not available in this build yet.'),
                ),
              );
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTint : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: enabled ? AppColors.accentStrong : AppColors.textSecondary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
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

  Widget _filePickerRow() {
    final picked = _pickedFile;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: _isPicking ? null : _pickFile,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: picked != null
                ? AppColors.accentTint
                : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked != null ? AppColors.accent : AppColors.border,
              width: 1.5,
            ),
          ),
          child: _isPicking
              ? const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : picked == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file_rounded,
                      size: 36,
                      color: AppColors.accentStrong,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to choose a photo or video',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'JPG, PNG, MP4, MOV, WEBM supported',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        picked.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _pickFile,
                      child: const Text('Change'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose input source')),
      body: ParticleBackground(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sourceTile(
                    type: SourceType.phone,
                    icon: Icons.videocam_outlined,
                    title: 'Live Camera',
                    subtitle: 'Stream from your phone camera now',
                  ),
                  const SizedBox(height: 12),
                  _sourceTile(
                    type: SourceType.videoUpload,
                    icon: Icons.video_library_outlined,
                    title: 'Recorded Video',
                    subtitle: 'Process a photo or video file you already have',
                  ),
                  if (_selected == SourceType.videoUpload) _filePickerRow(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: AppColors.danger)),
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: _isStarting ? null : _beginSession,
                    child: _isStarting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Begin Session'),
                  ),
                ],
              ),
            ),
            // Connecting to the engines (loading ONNX models, opening the
            // WebSocket, starting the camera) can take a few seconds - the
            // button's own small spinner isn't obvious enough on its own.
            if (_isStarting)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 20),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.accent),
                          const SizedBox(height: 16),
                          Text(
                            'Connecting...',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
