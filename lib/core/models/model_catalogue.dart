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

  /// Apple's on-device speech recognition. iOS fetches its speech model only
  /// when the person taps Download, outside Sekret's pinned path (ADR 0006).
  static const appleSpeech = CatalogueModel(
    id: 'apple-speech',
    name: 'Apple Speech',
    kind: ModelKind.voiceInput,
    runtime: ModelRuntime.apple,
    capabilities: {},
    summary:
        'Built into iOS 26 and later. Turns what you say into text in the message field on this iPhone; nothing is sent until you tap Send. '
        'The first time, iOS downloads Apple’s speech model for your language after you tap Download. Audio is never saved.',
    isNew: true,
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
  static const entries = [apple, qwen, appleSpeech];

  static CatalogueModel? byId(String id) =>
      entries.where((model) => model.id == id).firstOrNull;
}
