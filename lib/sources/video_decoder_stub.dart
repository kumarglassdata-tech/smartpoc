import 'dart:typed_data';

// Native (Android/iOS) video frame extraction. video_thumbnail (the usual
// package for this) is unmaintained and its Gradle script uses the removed
// jcenter() repo, breaking the build on modern AGP - so real video-file
// frame extraction isn't available here. Image uploads (the common case)
// are unaffected; a video upload falls back to the adapter's placeholder
// frame instead of a real decoded one.
class VideoDecoder {
  Future<void> loadVideo(Uint8List bytes, {String? fileName}) async {}

  Future<Uint8List?> getNextFrame() async => null;

  Future<void> dispose() async {}
}
