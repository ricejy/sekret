import 'dart:io';

import 'package:flutter/services.dart';

import '../models/background_model_download.dart';
import '../models/model_catalogue.dart';
import '../models/model_download.dart';

final class AppleModelDownload implements BackgroundModelDownload {
  const AppleModelDownload({
    this.channel = const MethodChannel('com.ricejy.sekret/model_download'),
    this.pollInterval = const Duration(milliseconds: 500),
  });
  final MethodChannel channel;
  final Duration pollInterval;

  @override
  Future<bool> hasPending() async =>
      await channel.invokeMethod<bool>('hasPending') ?? false;

  @override
  Future<void> transfer({
    required ModelArtifact artifact,
    required File destination,
    required ModelCancellation cancel,
    required void Function(int) onProgress,
  }) async {
    try {
      cancel.check();
      // Await admission before cancellation, so Cancel cannot race a late Start.
      await channel.invokeMethod<void>('start', {
        'url': artifact.downloadUri.toString(),
        'bytes': artifact.bytes,
        'sha256': artifact.sha256,
        'destination': destination.path,
      });
      while (true) {
        cancel.check();
        final state = await channel.invokeMapMethod<String, Object?>('status');
        cancel.check();
        final bytes = state?['bytes'];
        if (bytes is! int || bytes < 0 || bytes > artifact.bytes) {
          throw const FormatException('Invalid background transfer progress');
        }
        onProgress(bytes);
        switch (state?['phase']) {
          case 'complete':
            return; // Store verifies persisted size/hash before publication.
          case 'downloading':
            await cancel.wait(Future<void>.delayed(pollInterval));
          default:
            throw const HttpException('Background model download failed');
        }
      }
    } on Object {
      await this.cancel();
      rethrow;
    }
  }

  @override
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
}
