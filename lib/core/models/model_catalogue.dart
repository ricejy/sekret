/// What a catalogue entry is for. Chat models answer turns; voice-input and
/// read-aloud models never produce or read chat evidence.
enum ModelKind { chat, voiceInput, readAloud }

/// Who runs the model. Apple entries are managed by iOS and never downloaded
/// by Sekret; the others are reviewed, pinned downloads (ADR 0005, ADR 0006).
enum ModelRuntime { apple, llamaCpp, fluidAudio }

/// Static catalogue claims; photo questions also need iOS 27 at runtime.
enum ModelCapability { generalText, photoQuestions }

/// What a pinned file is used for. Informational only: every file, whatever
/// its role, must match its exact size and SHA-256 before the model is usable.
enum ArtifactRole {
  weights,
  projector,
  config,
  tokenizer,
  voice,
  lexicon,
  constants,
  license,
}

/// One pinned file of a reviewed model, fetched from an immutable commit.
class ModelArtifact {
  const ModelArtifact({
    required this.repository,
    required this.revision,
    required this.path,
    required this.bytes,
    required this.sha256,
    this.role = ArtifactRole.weights,
  });

  final String repository;
  final String revision;

  /// Repository-relative path; also the installed path inside the model's
  /// own folder, because some runtimes load a directory laid out as published.
  final String path;
  final int bytes;
  final String sha256;
  final ArtifactRole role;

  static final _segment = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]*$');

  /// Rejects anything that could leave the model folder or name a hidden file.
  bool get valid =>
      bytes > 0 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) &&
      RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) &&
      path.split('/').every(_segment.hasMatch) &&
      !path.split('/').contains('..');

  Uri get downloadUri =>
      Uri.https('huggingface.co', '/$repository/resolve/$revision/$path');
}

/// Credit and licence text shown in a model's information sheet. Attribution
/// licences (CC-BY) must name the creator here (ADR 0006).
class ModelNotice {
  const ModelNotice({
    required this.license,
    required this.credit,
    this.assets = const [],
    this.attribution,
  });

  /// SPDX-style identifier, for example `Apache-2.0` or `CC-BY-4.0`.
  final String license;

  /// Who made the model and who converted or quantized it.
  final String credit;

  /// Bundled licence texts, shown in full.
  final List<String> assets;

  /// Required attribution wording, when the licence asks for one.
  final String? attribution;
}

/// How Sekret runs a downloaded chat model, recorded in each turn's
/// provenance. The native side keeps the matching template and sampler.
class LocalModelProfile {
  const LocalModelProfile({
    required this.id,
    required this.quantization,
    required this.runtime,
    required this.template,
    required this.instructions,
    required this.context,
    required this.outputCap,
  });

  final String id;
  final String quantization;
  final String runtime;
  final String template;
  final String instructions;
  final int context;
  final int outputCap;
}

class CatalogueModel {
  const CatalogueModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.runtime,
    required this.capabilities,
    required this.summary,
    this.artifacts = const [],
    this.notice,
    this.addOnFor,
    this.profile,
    this.isNew = false,
    this.legacyStorage = false,
  });

  final String id;
  final String name;
  final ModelKind kind;
  final ModelRuntime runtime;
  final Set<ModelCapability> capabilities;

  /// One or two plain sentences for the information sheet.
  final String summary;

  /// Every pinned file. Empty for Apple-managed entries.
  final List<ModelArtifact> artifacts;
  final ModelNotice? notice;

  /// Id of the base model this add-on extends (a vision projector shares the
  /// base model's weights). An add-on is installed separately and needs the
  /// base installed to be used.
  final String? addOnFor;

  /// Runtime profile of a downloaded chat model: template and limits.
  final LocalModelProfile? profile;

  /// Shown with a "New" chip until it has been measured.
  final bool isNew;

  /// Installed before per-model folders existed: a single file stored as
  /// `reviewed-models/<sha256>.gguf`. Kept so existing installs are not
  /// downloaded again.
  final bool legacyStorage;

  bool get downloadable => runtime != ModelRuntime.apple;

  int get totalBytes => artifacts.fold(0, (sum, file) => sum + file.bytes);

  /// The primary weights file, used by single-file runtimes and provenance.
  ModelArtifact? get weights =>
      artifacts.where((file) => file.role == ArtifactRole.weights).firstOrNull;
}

abstract final class ModelCatalogue {
  static const apple = CatalogueModel(
    id: 'apple-foundation-models',
    name: 'Apple Intelligence',
    kind: ModelKind.chat,
    runtime: ModelRuntime.apple,
    capabilities: {ModelCapability.generalText, ModelCapability.photoQuestions},
    summary:
        'Built into iOS and runs on this iPhone. Sekret does not download or remove it.',
  );

  static const qwen = CatalogueModel(
    id: 'qwen3-4b-instruct-2507-q3-k-m',
    name: 'Qwen3-4B-Instruct-2507',
    kind: ModelKind.chat,
    runtime: ModelRuntime.llamaCpp,
    capabilities: {ModelCapability.generalText},
    summary:
        'Text chat only: no images or Knowledge Vault answers. Runs entirely on this iPhone after download. Answers may stop if the phone gets too hot.',
    profile: LocalModelProfile(
      id: 'qwen3-4b-instruct-2507',
      quantization: 'Q3_K_M',
      runtime: 'llama.cpp-b11429',
      template: 'chatml-general-json-v1',
      instructions: 'local-general-v1',
      context: 2048,
      outputCap: 256,
    ),
    legacyStorage: true,
    notice: ModelNotice(
      license: 'Apache-2.0',
      credit:
          'Qwen3-4B-Instruct-2507 by Qwen\nQ3_K_M quantization by Unsloth\n'
          'Publisher license revision: cdbee75f17c01a7cc42f958dc650907174af0554',
      assets: ['assets/licenses/Qwen-Apache-2.0.txt'],
    ),
    artifacts: [
      ModelArtifact(
        repository: 'unsloth/Qwen3-4B-Instruct-2507-GGUF',
        revision: 'a06e946bb6b655725eafa393f4a9745d460374c9',
        path: 'Qwen3-4B-Instruct-2507-Q3_K_M.gguf',
        bytes: 2075618400,
        sha256:
            '9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9',
      ),
    ],
  );

  static const _localChatSummary =
      'Text chat only: no images or Knowledge Vault answers. Runs entirely on '
      'this iPhone after download. Answers may stop if the phone gets too hot.';

  static const qwen35FourB = CatalogueModel(
    id: 'qwen3.5-4b-q3km',
    name: 'Qwen3.5-4B',
    kind: ModelKind.chat,
    runtime: ModelRuntime.llamaCpp,
    capabilities: {ModelCapability.generalText},
    summary: _localChatSummary,
    isNew: true,
    profile: LocalModelProfile(
      id: 'qwen3.5-4b',
      quantization: 'Q3_K_M',
      runtime: 'llama.cpp-b11429',
      template: 'qwen3.5-chatml-no-tools-no-thinking-v1',
      instructions: 'local-general-v1',
      context: 2048,
      outputCap: 256,
    ),
    notice: ModelNotice(
      license: 'Apache-2.0',
      credit:
          'Qwen3.5-4B by Qwen\nQ3_K_M quantization by Unsloth\n'
          'Licence record: README.md at e87f176479d0855a907a41277aca2f8ee7a09523',
      assets: ['assets/licenses/Apache-2.0.txt'],
    ),
    artifacts: [
      ModelArtifact(
        repository: 'unsloth/Qwen3.5-4B-GGUF',
        revision: 'e87f176479d0855a907a41277aca2f8ee7a09523',
        path: 'Qwen3.5-4B-Q3_K_M.gguf',
        bytes: 2293388448,
        sha256:
            'd6981ab4d77ba712b48ef69d69042d75b5e39b9dce5fb5a5b054fd08e06afb95',
      ),
      ModelArtifact(
        repository: 'unsloth/Qwen3.5-4B-GGUF',
        revision: 'e87f176479d0855a907a41277aca2f8ee7a09523',
        path: 'README.md',
        bytes: 78906,
        sha256:
            '28546f5fc4f22ee1b3f17b908957f17fcfa66174032136265bdb27f404bc1e6c',
        role: ArtifactRole.license,
      ),
    ],
  );

  static const qwen35TwoB = CatalogueModel(
    id: 'qwen3.5-2b-q4km',
    name: 'Qwen3.5-2B',
    kind: ModelKind.chat,
    runtime: ModelRuntime.llamaCpp,
    capabilities: {ModelCapability.generalText},
    summary: _localChatSummary,
    isNew: true,
    profile: LocalModelProfile(
      id: 'qwen3.5-2b',
      quantization: 'Q4_K_M',
      runtime: 'llama.cpp-b11429',
      template: 'qwen3.5-chatml-no-tools-no-thinking-v1',
      instructions: 'local-general-v1',
      context: 2048,
      outputCap: 256,
    ),
    notice: ModelNotice(
      license: 'Apache-2.0',
      credit:
          'Qwen3.5-2B by Qwen\nQ4_K_M quantization by Unsloth\n'
          'Licence record: README.md at f6d5376be1edb4d416d56da11e5397a961aca8ae',
      assets: ['assets/licenses/Apache-2.0.txt'],
    ),
    artifacts: [
      ModelArtifact(
        repository: 'unsloth/Qwen3.5-2B-GGUF',
        revision: 'f6d5376be1edb4d416d56da11e5397a961aca8ae',
        path: 'Qwen3.5-2B-Q4_K_M.gguf',
        bytes: 1280835840,
        sha256:
            'aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223',
      ),
      ModelArtifact(
        repository: 'unsloth/Qwen3.5-2B-GGUF',
        revision: 'f6d5376be1edb4d416d56da11e5397a961aca8ae',
        path: 'README.md',
        bytes: 64059,
        sha256:
            'd6507c9243588d5526ceb08840ebd759b0d05aeb96c8aeb42e59f4727df0143a',
        role: ArtifactRole.license,
      ),
    ],
  );

  static const miniCpm5TwoB = CatalogueModel(
    id: 'minicpm5-2b-q4km',
    name: 'MiniCPM5-2B',
    kind: ModelKind.chat,
    runtime: ModelRuntime.llamaCpp,
    capabilities: {ModelCapability.generalText},
    summary: _localChatSummary,
    isNew: true,
    profile: LocalModelProfile(
      id: 'minicpm5-2b',
      quantization: 'Q4_K_M',
      runtime: 'llama.cpp-b11429',
      template: 'minicpm5-chatml-no-tools-no-thinking-v1',
      instructions: 'local-general-v1',
      context: 2048,
      outputCap: 256,
    ),
    notice: ModelNotice(
      license: 'Apache-2.0',
      credit:
          'MiniCPM5-2B by OpenBMB\nQ4_K_M GGUF by OpenBMB\n'
          'Licence record: README.md at 8ad02b786ab81e33d465e1c80562640c55ab2877',
      assets: ['assets/licenses/Apache-2.0.txt'],
    ),
    artifacts: [
      ModelArtifact(
        repository: 'openbmb/MiniCPM5-2B-GGUF',
        revision: '8ad02b786ab81e33d465e1c80562640c55ab2877',
        path: 'MiniCPM5-2B-Q4_K_M.gguf',
        bytes: 1561318368,
        sha256:
            'ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd',
      ),
      ModelArtifact(
        repository: 'openbmb/MiniCPM5-2B-GGUF',
        revision: '8ad02b786ab81e33d465e1c80562640c55ab2877',
        path: 'README.md',
        bytes: 112758,
        sha256:
            'aa1c0fac166d44aaf0d0529731137028252ff8207eb51e795aeca96195283879',
        role: ArtifactRole.license,
      ),
    ],
  );

  static const miniCpm5OneB = CatalogueModel(
    id: 'minicpm5-1b-q4km',
    name: 'MiniCPM5-1B',
    kind: ModelKind.chat,
    runtime: ModelRuntime.llamaCpp,
    capabilities: {ModelCapability.generalText},
    summary: _localChatSummary,
    isNew: true,
    profile: LocalModelProfile(
      id: 'minicpm5-1b',
      quantization: 'Q4_K_M',
      runtime: 'llama.cpp-b11429',
      template: 'minicpm5-chatml-no-tools-no-thinking-v1',
      instructions: 'local-general-v1',
      context: 2048,
      outputCap: 256,
    ),
    notice: ModelNotice(
      license: 'Apache-2.0',
      credit:
          'MiniCPM5-1B by OpenBMB\nQ4_K_M GGUF by OpenBMB\n'
          'Licence record: README.md at 5385560dd3e232bcc3577fd9442c332cad2facbd',
      assets: ['assets/licenses/Apache-2.0.txt'],
    ),
    artifacts: [
      ModelArtifact(
        repository: 'openbmb/MiniCPM5-1B-GGUF',
        revision: '5385560dd3e232bcc3577fd9442c332cad2facbd',
        path: 'MiniCPM5-1B-Q4_K_M.gguf',
        bytes: 688065920,
        sha256:
            '81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa',
      ),
      ModelArtifact(
        repository: 'openbmb/MiniCPM5-1B-GGUF',
        revision: '5385560dd3e232bcc3577fd9442c332cad2facbd',
        path: 'README.md',
        bytes: 23879,
        sha256:
            '1e0e46b152bc2fdfdb27232bb9a7511d104a67bd8fcedc8321fb755dd68a7ea3',
        role: ArtifactRole.license,
      ),
    ],
  );

  static const granite41ThreeB = CatalogueModel(
    id: 'granite-4.1-3b-q4km',
    name: 'Granite 4.1 3B',
    kind: ModelKind.chat,
    runtime: ModelRuntime.llamaCpp,
    capabilities: {ModelCapability.generalText},
    summary: _localChatSummary,
    isNew: true,
    profile: LocalModelProfile(
      id: 'granite-4.1-3b',
      quantization: 'Q4_K_M',
      runtime: 'llama.cpp-b11429',
      template: 'granite-4.1-roles-no-tools-no-documents-v1',
      instructions: 'local-general-v1',
      context: 2048,
      outputCap: 256,
    ),
    notice: ModelNotice(
      license: 'Apache-2.0',
      credit:
          'Granite 4.1 3B by IBM\nQ4_K_M GGUF by IBM\n'
          'Licence record: README.md at ab4701481089b58a082ef63cc1cee738887293ff',
      assets: ['assets/licenses/Apache-2.0.txt'],
    ),
    artifacts: [
      ModelArtifact(
        repository: 'ibm-granite/granite-4.1-3b-GGUF',
        revision: 'ab4701481089b58a082ef63cc1cee738887293ff',
        path: 'granite-4.1-3b-Q4_K_M.gguf',
        bytes: 2099501664,
        sha256:
            '662b0626cd58f443baea23559b469df6576a81d349649c59413b36a9fb32eb29',
      ),
      ModelArtifact(
        repository: 'ibm-granite/granite-4.1-3b-GGUF',
        revision: 'ab4701481089b58a082ef63cc1cee738887293ff',
        path: 'README.md',
        bytes: 450,
        sha256:
            '2c2c51c0bd6f0884c7363b304b2fd7ac89a2db65fa07ff0e1da2b1eb82e613bb',
        role: ArtifactRole.license,
      ),
    ],
  );

  /// Runtime notices shown with every model that uses that runtime.
  static const runtimeNotices = {
    ModelRuntime.llamaCpp: (
      credit: 'llama.cpp b11429 · d81235049384534c167caea52b85a694f6103d14',
      asset: 'assets/licenses/llama-MIT.txt',
    ),
  };

  /// Every id that has ever shipped stays listed, so older chat labels and
  /// saved selections still resolve. Entries join only when their runtime
  /// integration has passed a phone smoke test.
  static const entries = [
    apple,
    qwen,
    qwen35FourB,
    qwen35TwoB,
    miniCpm5TwoB,
    miniCpm5OneB,
    granite41ThreeB,
  ];

  static CatalogueModel? byId(String id) =>
      entries.where((model) => model.id == id).firstOrNull;
}
