/// Frozen initial offering. Inclusion is not installation or device approval.
enum CatalogueModelKind { appleManaged, downloadable }

enum ModelCapability { generalText }

class ModelArtifact {
  const ModelArtifact({
    required this.repository,
    required this.revision,
    required this.filename,
    required this.bytes,
    required this.sha256,
  });

  final String repository;
  final String revision;
  final String filename;
  final int bytes;
  final String sha256;

  Uri get downloadUri =>
      Uri.https('huggingface.co', '/$repository/resolve/$revision/$filename');
}

class CatalogueModel {
  const CatalogueModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.integrationReady,
    required this.capabilities,
    this.artifact,
  });

  final String id;
  final String name;
  final CatalogueModelKind kind;

  /// Not a runtime availability result or an approved device profile.
  final bool integrationReady;
  final Set<ModelCapability> capabilities;
  final ModelArtifact? artifact;
}

abstract final class ModelCatalogue {
  static const apple = CatalogueModel(
    id: 'apple-foundation-models',
    name: 'Apple Intelligence',
    kind: CatalogueModelKind.appleManaged,
    integrationReady: true,
    capabilities: {ModelCapability.generalText},
  );

  static const qwen = CatalogueModel(
    id: 'qwen3-4b-instruct-2507-q3-k-m',
    name: 'Qwen3-4B-Instruct-2507',
    kind: CatalogueModelKind.downloadable,
    integrationReady: false,
    capabilities: {ModelCapability.generalText},
    artifact: ModelArtifact(
      repository: 'unsloth/Qwen3-4B-Instruct-2507-GGUF',
      revision: 'a06e946bb6b655725eafa393f4a9745d460374c9',
      filename: 'Qwen3-4B-Instruct-2507-Q3_K_M.gguf',
      bytes: 2075618400,
      sha256:
          '9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9',
    ),
  );

  static const entries = [apple, qwen];
}
