import 'dart:async';
import 'dart:io';

import 'model_catalogue.dart';

class ModelOperationCancelled implements Exception {
  const ModelOperationCancelled();
}

/// Cancellation also interrupts silent network requests and file verification.
final class ModelCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const ModelOperationCancelled();
  }

  Future<T> wait<T>(Future<T> operation) {
    return Future.any([
      operation,
      _cancelled.future.then<T>((_) => throw const ModelOperationCancelled()),
    ]).then((value) {
      check();
      return value;
    });
  }
}

abstract interface class ModelDownload {
  Stream<List<int>> get bytes;
  Future<void> close();
}

abstract interface class ModelTransport {
  Future<ModelDownload> open(ModelArtifact artifact, ModelCancellation cancel);
}

/// No credentials, cookies, custom URLs, automatic retries or background work.
/// The final pinned hash remains mandatory even for an allowed CDN redirect.
final class HttpsModelTransport implements ModelTransport {
  const HttpsModelTransport();

  static bool permits(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      uri.fragment.isEmpty &&
      const {
        'huggingface.co',
        'cdn-lfs.huggingface.co',
        'cdn-lfs-us-1.huggingface.co',
        'cdn-lfs-eu-1.huggingface.co',
        'cas-bridge.xethub.hf.co',
        'us.aws.cdn.hf.co',
      }.contains(uri.host);

  @override
  Future<ModelDownload> open(
    ModelArtifact artifact,
    ModelCancellation cancel,
  ) async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 30)
      ..findProxy = (_) => 'DIRECT';
    try {
      var uri = artifact.downloadUri;
      for (var redirects = 0; redirects <= 5; redirects++) {
        cancel.check();
        if (!permits(uri)) throw const HttpException('Unapproved model host');
        final request = await cancel.wait(client.getUrl(uri));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final response = await cancel.wait(
          request.close().timeout(const Duration(seconds: 30)),
        );
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const HttpException('Missing redirect');
          uri = uri.resolve(location);
          // Do not drain an unbounded redirect body.
          await response.listen((_) {}).cancel();
          continue;
        }
        if (response.statusCode != HttpStatus.ok ||
            (response.contentLength != -1 &&
                response.contentLength != artifact.bytes) ||
            (response.headers.value(HttpHeaders.contentEncodingHeader) ??
                    'identity') !=
                'identity') {
          throw const HttpException('Unexpected model response');
        }
        return _HttpDownload(client, response);
      }
      throw const HttpException('Too many redirects');
    } on Object {
      client.close(force: true);
      rethrow;
    }
  }
}

final class _HttpDownload implements ModelDownload {
  _HttpDownload(this.client, this.response);
  final HttpClient client;
  final HttpClientResponse response;
  @override
  Stream<List<int>> get bytes => response.timeout(const Duration(seconds: 30));
  @override
  Future<void> close() async => client.close(force: true);
}
