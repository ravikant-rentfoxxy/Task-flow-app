import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../data/taskflow_api.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Downloads an upload (auth required) and opens it with the OS viewer.
Future<void> openAttachment(BuildContext context, Attachment a) async {
  final api = Get.find<TaskFlowApi>();
  if (a.isImage) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ImageViewer(attachment: a)));
    return;
  }
  try {
    toast('Downloading ${a.fileName}…');
    final bytes = await api.client.getBytes('/uploads/${a.id}');
    final dir = await getTemporaryDirectory();
    final safeName = a.fileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final file = File('${dir.path}/tf_${a.id}_$safeName');
    await file.writeAsBytes(bytes);
    final ok = await launchUrl(Uri.file(file.path));
    if (!ok) toast('Saved to ${file.path}');
  } catch (e) {
    toastError(e, 'Could not open file');
  }
}

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({super.key, required this.attachment, this.compact = false});
  final Attachment attachment;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    if (a.isImage) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openAttachment(context, a),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AuthImage(attachmentId: a.id, height: compact ? 120 : 160, width: double.infinity),
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openAttachment(context, a),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: TF.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TF.line),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: TF.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(a.isAudio ? Icons.graphic_eq_rounded : Icons.description_outlined, color: TF.primaryDeep, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              Text(
                [formatBytes(a.size), if (a.uploaderName != null) a.uploaderName!, if (a.createdAt != null) timeAgo(a.createdAt)]
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                style: const TextStyle(fontSize: 11, color: TF.muted),
              ),
            ]),
          ),
          const Icon(Icons.open_in_new_rounded, size: 18, color: TF.muted),
        ]),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const Border(),
          title: Text(attachment.fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: AuthImage(attachmentId: attachment.id, fit: BoxFit.contain)),
        ),
      );
}
