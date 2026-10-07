import 'package:flutter/cupertino.dart';
import '../../core/knowledge/knowledge_base.dart';
import '../../core/platform/document_image_picker.dart';
import '../../core/platform/file_selector_pdf_picker.dart';
import '../../core/platform/pdf_file_picker.dart';
import '../../core/platform/photos_document_image_picker.dart';
import '../../core/storage/local_data_vault.dart';
import 'import_sheet.dart';

/// Both entry points admit through KnowledgeBase's existing local pipeline.
/// Callers own duplicate decisions and whether the result becomes a chat source.
Future<KnowledgeImportResult?> importKnowledgeSource(
  BuildContext context,
  KnowledgeBase knowledge,
  KnowledgeSourceType type, {
  PdfFilePicker pdfPicker = const FileSelectorPdfPicker(),
  DocumentImagePicker imagePicker = const PhotosDocumentImagePicker(),
}) async {
  switch (type) {
    case KnowledgeSourceType.pastedText:
      return Navigator.of(context).push<KnowledgeImportResult>(
        CupertinoPageRoute(
          fullscreenDialog: true,
          builder: (_) => PasteKnowledge(knowledge: knowledge),
        ),
      );
    case KnowledgeSourceType.pdf:
      final picked = await pdfPicker.pickPdf();
      if (!context.mounted || picked == null) return null;
      return knowledge.importSource(
        title: picked.name,
        sourceName: picked.name,
        sourceType: type,
        bytes: picked.bytes,
      );
    case KnowledgeSourceType.photo:
      final picked = await imagePicker.pickImage();
      if (!context.mounted || picked == null) return null;
      return knowledge.importSource(
        title: picked.name,
        sourceName: picked.name,
        sourceType: type,
        bytes: picked.bytes,
      );
  }
}
