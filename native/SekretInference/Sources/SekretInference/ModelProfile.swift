import Foundation
import llama

/// How a reviewed chat model's turns are framed. Not a Jinja implementation:
/// each family renders the publisher's no-tools subset (one system message,
/// alternating user/assistant, ending in user) and must equal llama.cpp's
/// built-in formatter for that family.
public enum TemplateFamily: String, CaseIterable {
    /// `<|im_start|>role\ncontent<|im_end|>\n` (Qwen3, Qwen3.5, MiniCPM5).
    case chatml
    /// `<|start_of_role|>role<|end_of_role|>content<|end_of_text|>\n` (Granite 4.1).
    case granite

    /// llama.cpp's built-in template name for this family.
    public var nativeName: String { rawValue }
    public var turnStart: String {
        switch self {
        case .chatml: return "<|im_start|>"
        case .granite: return "<|start_of_role|>"
        }
    }
    public var turnEnd: String {
        switch self {
        case .chatml: return "<|im_end|>"
        case .granite: return "<|end_of_text|>"
        }
    }

    func render(_ messages: [LocalModelMessage]) -> String {
        switch self {
        case .chatml:
            return messages.map { "<|im_start|>\($0.role)\n\($0.content)<|im_end|>\n" }.joined()
                + "<|im_start|>assistant\n"
        case .granite:
            return messages.map { "<|start_of_role|>\($0.role)<|end_of_role|>\($0.content)<|end_of_text|>\n" }.joined()
                + "<|start_of_role|>assistant<|end_of_role|>"
        }
    }
}

/// Thinking is always off. A thinking-capable template is told so explicitly by
/// prefilling the empty reasoning block its `enable_thinking=false` branch emits.
public enum ThinkingRule: Equatable {
    /// The template has no thinking mode (Qwen3-4B-Instruct-2507, Granite 4.1).
    case notSupported
    /// Append `<think>\n\n</think>\n\n` after the assistant header (Qwen3.5, MiniCPM5).
    case prefillEmpty

    public static let emptyBlock = "<think>\n\n</think>\n\n"
}

/// Whether the prompt starts with the vocabulary's BOS token.
public enum BOSRule: Equatable {
    /// Never add one; the pinned Qwen3-4B framing.
    case never
    /// Follow the GGUF's `add_bos_token`, as llama-server does.
    case fromVocabulary
}

public struct SamplerSettings: Equatable {
    public let topK: Int32
    public let topP: Float
    public let temperature: Float
    /// 0 disables the penalty sampler.
    public let presencePenalty: Float
    public let seed: UInt32
}

/// Exact token ids checked at load, for a profile whose GGUF has been inspected.
public struct PinnedTokenIDs: Equatable {
    public let turnStart: llama_token
    public let turnEnd: llama_token
    public let eos: llama_token
    public let endOfGeneration: [llama_token]
}

/// Everything Sekret pins about running one reviewed GGUF. The Dart catalogue's
/// `LocalModelProfile` carries the same id, context and output cap.
public struct ModelProfile {
    public let id: String
    public let sha256: String
    public let bytes: UInt64
    public let family: TemplateFamily
    public let thinking: ThinkingRule
    public let bos: BOSRule
    public let sampler: SamplerSettings
    public let context: Int
    public let output: Int
    public let templateVersion: String
    /// The vocabulary's EOS token text.
    public let eosText: String
    /// Tokens llama.cpp must report as end-of-generation (`llama_vocab_is_eog`).
    public let endOfGenerationTexts: [String]
    /// Extra tokens that end an answer even when the GGUF does not mark them as
    /// end-of-generation (MiniCPM5's EOS is `</s>`, but turns end with `<|im_end|>`).
    public let stopTexts: [String]
    public let pinnedIDs: PinnedTokenIDs?
    /// Check at load that llama.cpp reads the GGUF's embedded `chat_template`
    /// as this family and renders it exactly as `family` does.
    public let checksEmbeddedTemplate: Bool

    /// Free memory required before loading: the weights plus the margin that
    /// Qwen3-4B was admitted with (2.5 GiB for 2,075,618,400 bytes of weights).
    public static let memoryMargin: UInt64 = 608_736_160
    public var admissionBytes: UInt64 { bytes + Self.memoryMargin }

    /// Opening text of the assistant's turn after the family's header.
    public var assistantPrefill: String { thinking == .prefillEmpty ? ThinkingRule.emptyBlock : "" }

    /// Turn markers that must never appear in user, system or history text.
    /// Prompt text is tokenized with special-token parsing, so this list is
    /// what keeps user text from forging framing tokens.
    public var forbiddenContent: [String] {
        ["\0", "<|", "<think>", "</think>"] + (eosText == "</s>" ? ["<s>", "</s>"] : [])
    }

    /// Publisher's recommended non-thinking sampler for Qwen3 and Qwen3.5 instruct.
    static let qwenSampler = SamplerSettings(topK: 20, topP: 0.8, temperature: 0.7, presencePenalty: 0, seed: 42)
    static let qwen35Sampler = SamplerSettings(topK: 20, topP: 0.8, temperature: 0.7, presencePenalty: 1.5, seed: 42)
    /// Sekret's default for publishers without a pinned recommendation;
    /// revisit with the held-out ratings.
    static let defaultSampler = qwenSampler

    public static let qwen3_4b = ModelProfile(
        id: "qwen3-4b-instruct-2507",
        sha256: "9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9",
        bytes: 2_075_618_400, family: .chatml, thinking: .notSupported, bos: .never,
        sampler: qwenSampler, context: 2048, output: 256,
        templateVersion: "qwen3-4b-instruct-2507-alternating-chat-no-tools-v1",
        eosText: "<|im_end|>", endOfGenerationTexts: ["<|im_end|>", "<|endoftext|>"], stopTexts: [],
        pinnedIDs: PinnedTokenIDs(turnStart: 151644, turnEnd: 151645, eos: 151645, endOfGeneration: [151645, 151643]),
        checksEmbeddedTemplate: false)

    public static let qwen35_4b = ModelProfile(
        id: "qwen3.5-4b",
        sha256: "d6981ab4d77ba712b48ef69d69042d75b5e39b9dce5fb5a5b054fd08e06afb95",
        bytes: 2_293_388_448, family: .chatml, thinking: .prefillEmpty, bos: .fromVocabulary,
        sampler: qwen35Sampler, context: 2048, output: 256,
        templateVersion: "qwen3.5-chatml-no-tools-no-thinking-v1",
        eosText: "<|im_end|>", endOfGenerationTexts: ["<|im_end|>"], stopTexts: [],
        pinnedIDs: nil, checksEmbeddedTemplate: true)

    public static let qwen35_2b = ModelProfile(
        id: "qwen3.5-2b",
        sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223",
        bytes: 1_280_835_840, family: .chatml, thinking: .prefillEmpty, bos: .fromVocabulary,
        sampler: qwen35Sampler, context: 2048, output: 256,
        templateVersion: "qwen3.5-chatml-no-tools-no-thinking-v1",
        eosText: "<|im_end|>", endOfGenerationTexts: ["<|im_end|>"], stopTexts: [],
        pinnedIDs: nil, checksEmbeddedTemplate: true)

    public static let minicpm5_2b = ModelProfile(
        id: "minicpm5-2b",
        sha256: "ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd",
        bytes: 1_561_318_368, family: .chatml, thinking: .prefillEmpty, bos: .fromVocabulary,
        sampler: defaultSampler, context: 2048, output: 256,
        templateVersion: "minicpm5-chatml-no-tools-no-thinking-v1",
        eosText: "</s>", endOfGenerationTexts: ["</s>"], stopTexts: ["<|im_end|>"],
        pinnedIDs: nil, checksEmbeddedTemplate: true)

    public static let minicpm5_1b = ModelProfile(
        id: "minicpm5-1b",
        sha256: "81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa",
        bytes: 688_065_920, family: .chatml, thinking: .prefillEmpty, bos: .fromVocabulary,
        sampler: defaultSampler, context: 2048, output: 256,
        templateVersion: "minicpm5-chatml-no-tools-no-thinking-v1",
        eosText: "</s>", endOfGenerationTexts: ["</s>"], stopTexts: ["<|im_end|>"],
        pinnedIDs: nil, checksEmbeddedTemplate: true)

    public static let granite41_3b = ModelProfile(
        id: "granite-4.1-3b",
        sha256: "662b0626cd58f443baea23559b469df6576a81d349649c59413b36a9fb32eb29",
        bytes: 2_099_501_664, family: .granite, thinking: .notSupported, bos: .fromVocabulary,
        sampler: defaultSampler, context: 2048, output: 256,
        templateVersion: "granite-4.1-roles-no-tools-no-documents-v1",
        eosText: "<|end_of_text|>", endOfGenerationTexts: ["<|end_of_text|>"], stopTexts: [],
        pinnedIDs: nil, checksEmbeddedTemplate: true)

    public static let all: [ModelProfile] = [qwen3_4b, qwen35_4b, qwen35_2b, minicpm5_2b, minicpm5_1b, granite41_3b]

    public static func byID(_ id: String) -> ModelProfile? { all.first { $0.id == id } }
}
