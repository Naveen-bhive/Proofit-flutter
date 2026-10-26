import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/ui_kit.dart';

/// Shares a report PDF together with its videos.
///
/// Two WhatsApp behaviours drive this:
///  * one share containing a PDF *and* videos (mixed types) arrives as text
///    only — every file is dropped — so the PDF and the videos go as two
///    shares, each of a type every app accepts;
///  * a file share that also carries text can arrive as the text alone, so
///    file shares carry no text — the message is copied to the clipboard for
///    pasting instead.
/// "Share everything at once" (one mixed share, with the message) remains for
/// apps that handle it, e.g. Gmail and Drive.
Future<void> shareReportFiles(
  BuildContext context, {
  required XFile pdf,
  List<XFile> videos = const [],
  required String text,
  String subject = 'Work Completion Report',
}) async {
  Rect? origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  }

  Future<void> share(List<XFile> files, {String? message}) => SharePlus.instance.share(ShareParams(
        files: files,
        text: message,
        subject: subject,
        sharePositionOrigin: origin(),
      ));

  // The message travels via the clipboard so file shares stay file-only.
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Message copied — paste it in the chat if you want to send it.'),
      duration: Duration(seconds: 4),
    ));
  }

  if (videos.isEmpty) return share([pdf]);
  if (!context.mounted) return;

  final count = videos.length;
  final videoLabel = '$count video${count == 1 ? '' : 's'}';
  var pdfDone = false;
  var videosDone = false;

  await AppSheet.show<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => AppSheet(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Share report', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Photos are inside the PDF. The $videoLabel go as a second share, because apps like WhatsApp '
            "can't send a PDF and videos in one message.",
            style: const TextStyle(color: AppColors.silver, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 18),
          _StepButton(
            step: 1,
            label: 'Share PDF',
            icon: Icons.picture_as_pdf_outlined,
            done: pdfDone,
            onTap: () async {
              await share([pdf]);
              setSheet(() => pdfDone = true);
            },
          ),
          const SizedBox(height: 10),
          _StepButton(
            step: 2,
            label: 'Share $videoLabel',
            icon: Icons.videocam_outlined,
            done: videosDone,
            onTap: () async {
              await share(videos);
              setSheet(() => videosDone = true);
            },
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () async {
              await share([pdf, ...videos], message: text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Share everything at once (Gmail, Drive…)'),
          ),
        ]),
      ),
    ),
  );
}

class _StepButton extends StatelessWidget {
  final int step;
  final String label;
  final IconData icon;
  final bool done;
  final VoidCallback onTap;
  const _StepButton({required this.step, required this.label, required this.icon, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) => SurfaceCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        borderColor: done ? AppColors.green.withValues(alpha: 0.5) : null,
        child: Row(children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: done ? AppColors.green : AppColors.brandSoft,
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text('$step', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: AppColors.light, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15))),
          Text(done ? 'Shared' : 'Share', style: TextStyle(color: done ? AppColors.greenDark : AppColors.brand, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// MIME type for a downloaded video file, so share targets treat it as video.
String videoMimeFor(String path) => switch (path.split('.').last.toLowerCase()) {
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      '3gp' => 'video/3gpp',
      _ => 'video/mp4',
    };
