import 'package:flutter/cupertino.dart';
import '../../core/storage/local_data_vault.dart';
import '../sekret_brand.dart';

String sourceTypeLabel(KnowledgeSourceType type) => switch (type) {
  KnowledgeSourceType.pastedText => 'Text',
  KnowledgeSourceType.pdf => 'PDF',
  KnowledgeSourceType.photo => 'Photo',
};

String sourceSizeLabel(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

String importDateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}

/// What the person sees: a source either made it into the vault or did not.
/// Work in progress (including a pause that resumes in the foreground) is
/// shown transiently as adding.
enum SourceStatus {
  adding,
  ready,
  failed;

  String get label => switch (this) {
    ready => 'Ready',
    failed => 'Failed',
    adding => 'Adding…',
  };

  static SourceStatus of(KnowledgeProcessingState state) => switch (state) {
    KnowledgeProcessingState.indexed => ready,
    KnowledgeProcessingState.failed ||
    KnowledgeProcessingState.needsReindexing => failed,
    KnowledgeProcessingState.processing ||
    KnowledgeProcessingState.paused => adding,
  };
}

class SourceStatusBadge extends StatelessWidget {
  const SourceStatusBadge(this.status, {super.key, this.progress});
  final SourceStatus status;

  /// Fraction of the current processing stage, shown while adding.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SourceStatus.ready => SekretBrand.accent,
      SourceStatus.failed => CupertinoColors.systemRed,
      SourceStatus.adding => SekretBrand.secondary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == SourceStatus.adding)
          // Static rather than spinning: it fills as the checkpoint advances.
          CupertinoActivityIndicator.partiallyRevealed(
            radius: 6,
            progress: (progress ?? 0).clamp(.15, 1),
          )
        else
          Icon(
            status == SourceStatus.ready
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.exclamationmark_circle_fill,
            size: 14,
            color: color,
          ),
        const SizedBox(width: 5),
        Text(
          status.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
