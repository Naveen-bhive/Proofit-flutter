import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class PhotoViewerScreen extends StatefulWidget {
  final String beforeUrl;
  final String? afterUrl;
  const PhotoViewerScreen({super.key, required this.beforeUrl, this.afterUrl});
  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showBefore = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.afterUrl != null ? 2 : 1, vsync: this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _tabController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [

        // Full screen image
        PageView(
          onPageChanged: (i) => setState(() => _showBefore = i == 0),
          children: [
            _fullImage(widget.beforeUrl),
            if (widget.afterUrl != null) _fullImage(widget.afterUrl!),
          ],
        ),

        // Top bar
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
              ),
            ),
            const Spacer(),
            if (widget.afterUrl != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(_showBefore ? 'BEFORE' : 'AFTER',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1)),
              ),
          ]),
        )),

        // Swipe hint
        if (widget.afterUrl != null)
          Positioned(
            bottom: 40,
            left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _dot(!_showBefore ? AppColors.brand : Colors.white30),
              const SizedBox(width: 6),
              _dot(_showBefore ? AppColors.brand : Colors.white30),
            ]),
          ),
      ]),
    );
  }

  Widget _fullImage(String url) => InteractiveViewer(
    child: Image.network(url, fit: BoxFit.contain, width: double.infinity, height: double.infinity,
        loadingBuilder: (_, child, progress) => progress == null ? child
            : const Center(child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2)),
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white30, size: 60))),
  );

  Widget _dot(Color color) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 8, height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}