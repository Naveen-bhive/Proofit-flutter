import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/app_colors.dart';

/// Full-screen playback for a report video — a remote URL or, before upload
/// finishes, the local file.
class VideoPlayerScreen extends StatefulWidget {
  final String? url;
  final File? file;
  final String title;

  const VideoPlayerScreen({super.key, this.url, this.file, this.title = 'Video'})
      : assert(url != null || file != null);

  static Future<void> open(BuildContext context, {String? url, File? file, String title = 'Video'}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(url: url, file: file, title: title),
      ));

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.file != null
        ? VideoPlayerController.file(widget.file!)
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: SafeArea(
        child: _failed
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('This video could not be played. It may have been deleted or your connection dropped.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                ),
              )
            : !value.isInitialized
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : Column(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => value.isPlaying ? _controller.pause() : _controller.play(),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: value.aspectRatio,
                            child: Stack(alignment: Alignment.center, children: [
                              VideoPlayer(_controller),
                              if (!value.isPlaying)
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                                ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(children: [
                        IconButton(
                          icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                          onPressed: () => value.isPlaying ? _controller.pause() : _controller.play(),
                        ),
                        Text(_fmt(value.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(playedColor: AppColors.brand, bufferedColor: Colors.white24, backgroundColor: Colors.white12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_fmt(value.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                  ]),
      ),
    );
  }
}
