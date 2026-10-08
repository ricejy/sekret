import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/models/background_model_download.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/models/model_download.dart';
import 'package:sekret/core/models/model_store.dart';

final payload = [1, 2, 3, 4];
final fixture = CatalogueModel(
  id: 'test-model',
  name: 'Fixture',
  kind: CatalogueModelKind.downloadable,
  integrationReady: false,
  capabilities: {ModelCapability.generalText},
  artifact: ModelArtifact(
    repository: 'test/model',
    revision: 'pinned',
    filename: 'test.gguf',
    bytes: payload.length,
    sha256: sha256.convert(payload).toString(),
  ),
);

class Policy implements ModelStoragePolicy {
  int free = 1000000000;
  bool fail = false;
  @override
  Future<int> prepare(Directory directory) async {
    if (fail) throw StateError('Protection unavailable');
    return free;
  }
}

class Download implements ModelDownload {
  Download(this.bytes);
  @override
  final Stream<List<int>> bytes;
  bool closed = false;
  @override
  Future<void> close() async {
    closed = true;
  }
}

class Transport implements ModelTransport {
  Stream<List<int>> Function() source = () => Stream.value(payload);
  int calls = 0;
  Download? last;
  @override
  Future<ModelDownload> open(
    ModelArtifact artifact,
    ModelCancellation cancel,
  ) async {
    calls++;
    return last = Download(source());
  }
}

/// Native-hash stand-in; [gate] holds the result until the test releases it.
class Hasher implements ModelFileHasher {
  String digest = sha256.convert(payload).toString();
  Completer<void>? gate;
  final hashed = <String>[];
  @override
  Future<({int bytes, String sha256})> hash(File file) async {
    hashed.add(file.path);
    await gate?.future;
    return (bytes: await file.length(), sha256: digest);
  }
}

void main() {
  late Directory directory;
  late Policy policy;
  late Transport transport;
  late ModelStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sekret-model-store-');
    policy = Policy();
    transport = Transport();
    store = ModelStore(
      directory: directory,
      policy: policy,
      transport: transport,
      model: fixture,
    );
    await store.initialize();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'explicit install verifies disk bytes, leases block removal, removal preserves unrelated files',
    () async {
      expect(transport.calls, 0);
      await File('${directory.path}/unrelated.txt').writeAsString('keep');
      await store.install();
      expect(store.state.phase, ModelInstallPhase.installed);
      final lease = store.acquire();
      expect(await File(lease.path).readAsBytes(), payload);
      await expectLater(store.remove(), throwsStateError);
      expect(store.state.phase, ModelInstallPhase.installed);
      lease.release();
      lease.release();
      await store.remove();
      expect(await File(lease.path).exists(), false);
      expect(
        await File('${directory.path}/unrelated.txt').readAsString(),
        'keep',
      );
      expect(transport.last!.closed, true);
    },
  );

  for (final bad in <List<int>>[
    [1, 2],
    [1, 2, 3, 4, 5],
    [4, 3, 2, 1],
  ]) {
    test('rejects invalid artifact $bad without publication', () async {
      transport.source = () => Stream.value(bad);
      await expectLater(store.install(), throwsException);
      expect(store.state.phase, ModelInstallPhase.failed);
      expect(store.acquire, throwsStateError);
      expect(await directory.list().toList(), isEmpty);
      expect(transport.last!.closed, true);
    });
  }

  test('low disk and failed protection never contact network', () async {
    policy.free = fixture.artifact!.bytes + ModelStore.freeSpaceReserve - 1;
    await expectLater(store.install(), throwsStateError);
    policy.free = 1000000000;
    policy.fail = true;
    await expectLater(store.install(), throwsStateError);
    expect(transport.calls, 0);
  });

  test(
    'cancel a silent transfer, reject concurrent work, then explicitly restart',
    () async {
      final silent = StreamController<List<int>>();
      transport.source = () => silent.stream;
      final operation = store.install();
      final failure = expectLater(
        operation,
        throwsA(isA<ModelOperationCancelled>()),
      );
      while (transport.last == null) {
        await Future<void>.delayed(Duration.zero);
      }
      await expectLater(store.install(), throwsStateError);
      await expectLater(store.remove(), throwsStateError);
      expect(store.acquire, throwsStateError);
      await store.cancel().timeout(const Duration(seconds: 2));
      await failure;
      expect(await directory.list().toList(), isEmpty);
      transport.source = () => Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]);
      await store.install();
      expect(store.state.phase, ModelInstallPhase.installed);
      await silent.close();
    },
  );

  test('network failure removes staging and closes transport', () async {
    transport.source = () async* {
      yield [1];
      throw const SocketException('offline');
    };
    await expectLater(store.install(), throwsA(isA<SocketException>()));
    expect(await directory.list().toList(), isEmpty);
    expect(transport.last!.closed, true);
  });

  test(
    'restart cleans abandoned partial and verifies installed content offline',
    () async {
      await store.install();
      await store.close();
      await File('${directory.path}/download.partial').writeAsBytes([9]);
      store = ModelStore(
        directory: directory,
        policy: policy,
        transport: transport,
        model: fixture,
      );
      await store.initialize();
      expect(store.state.phase, ModelInstallPhase.installed);
      expect(transport.calls, 1);
      expect(await File('${directory.path}/download.partial').exists(), false);
      final lease = store.acquire();
      lease.release();
      await File(lease.path).writeAsBytes([0, 0, 0, 0]);
      await store.close();
      store = ModelStore(
        directory: directory,
        policy: policy,
        transport: transport,
        model: fixture,
      );
      await expectLater(store.initialize(), throwsException);
      expect(store.acquire, throwsStateError);
      await store.remove();
    },
  );

  test('reject symlink staging and do not touch the target', () async {
    final outside = await Directory.systemTemp.createTemp('sekret-outside-');
    try {
      final target = await File(
        '${outside.path}/precious',
      ).writeAsString('keep');
      await Link('${directory.path}/download.partial').create(target.path);
      await expectLater(store.install(), throwsStateError);
      await expectLater(store.remove(), throwsStateError);
      expect(await target.readAsString(), 'keep');
      expect(transport.calls, 0);
    } finally {
      await outside.delete(recursive: true);
    }
  });

  test('native hasher verifies the install and every restart', () async {
    final hasher = Hasher();
    await store.close();
    store = ModelStore(
      directory: directory,
      policy: policy,
      transport: transport,
      hasher: hasher,
      model: fixture,
    );
    await store.initialize();
    await store.install();
    expect(hasher.hashed.single, endsWith('download.partial'));
    await store.close();
    hasher.digest = '0' * 64;
    store = ModelStore(
      directory: directory,
      policy: policy,
      transport: transport,
      hasher: hasher,
      model: fixture,
    );
    await expectLater(store.initialize(), throwsException);
    expect(hasher.hashed.last, endsWith('${fixture.artifact!.sha256}.gguf'));
    expect(store.acquire, throwsStateError);
    await store.remove();
  });

  test('transport restricts redirects to exact HTTPS hostnames', () {
    expect(
      HttpsModelTransport.permits(
        Uri.parse('https://us.aws.cdn.hf.co/pinned?signature=test'),
      ),
      true,
    );
    expect(
      HttpsModelTransport.permits(
        Uri.parse('https://us.aws.cdn.hf.co.evil.test/pinned'),
      ),
      false,
    );
    for (final bad in [
      'http://huggingface.co/a',
      'https://huggingface.co.evil.test/a',
      'https://user:password@huggingface.co/a',
      'https://huggingface.co:444/a',
      'https://127.0.0.1/a',
      'file:///tmp/model',
      'https://evil.test/a',
    ]) {
      expect(HttpsModelTransport.permits(Uri.parse(bad)), false, reason: bad);
    }
    expect(HttpsModelTransport.permits(fixture.artifact!.downloadUri), true);
    expect(
      HttpsModelTransport.permits(
        Uri.parse('https://cas-bridge.xethub.hf.co/x?signature=y'),
      ),
      true,
    );
  });
}
