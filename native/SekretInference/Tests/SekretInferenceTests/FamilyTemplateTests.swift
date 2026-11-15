import XCTest
@testable import SekretInference

final class FamilyTemplateTests: XCTestCase {
    let chat: [LocalModelMessage] = [
        .init(role: "system", content: "Be brief."), .init(role: "user", content: "Hello"),
        .init(role: "assistant", content: "Hi."), .init(role: "user", content: "Name a bird."),
    ]

    func testQwen35PrefillsEmptyThinking() throws {
        for profile in [ModelProfile.qwen35_4b, .qwen35_2b] {
            XCTAssertEqual(try LocalRuntime.template(system: "Be brief.", user: "Hello", profile: profile),
                "<|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nHello<|im_end|>\n"
                + "<|im_start|>assistant\n<think>\n\n</think>\n\n")
            XCTAssertEqual(profile.eosText, "<|im_end|>")
            XCTAssertEqual(profile.stopTexts, [])
            XCTAssertEqual(profile.sampler.presencePenalty, 1.5)
        }
    }

    func testMiniCPM5StopsOnImEndAndTurnsThinkingOff() throws {
        for profile in [ModelProfile.minicpm5_2b, .minicpm5_1b] {
            XCTAssertEqual(try LocalRuntime.template(messages: chat, profile: profile),
                "<|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nHello<|im_end|>\n"
                + "<|im_start|>assistant\nHi.<|im_end|>\n<|im_start|>user\nName a bird.<|im_end|>\n"
                + "<|im_start|>assistant\n<think>\n\n</think>\n\n")
            XCTAssertEqual(profile.eosText, "</s>")
            XCTAssertEqual(profile.endOfGenerationTexts, ["</s>"])
            XCTAssertEqual(profile.stopTexts, ["<|im_end|>"])
            XCTAssertEqual(profile.thinking, .prefillEmpty)
        }
    }

    func testGraniteRoleTagsWithoutThinking() throws {
        let profile = ModelProfile.granite41_3b
        XCTAssertEqual(try LocalRuntime.template(messages: chat, profile: profile),
            "<|start_of_role|>system<|end_of_role|>Be brief.<|end_of_text|>\n"
            + "<|start_of_role|>user<|end_of_role|>Hello<|end_of_text|>\n"
            + "<|start_of_role|>assistant<|end_of_role|>Hi.<|end_of_text|>\n"
            + "<|start_of_role|>user<|end_of_role|>Name a bird.<|end_of_text|>\n"
            + "<|start_of_role|>assistant<|end_of_role|>")
        XCTAssertEqual(profile.assistantPrefill, "")
        XCTAssertEqual(profile.eosText, "<|end_of_text|>")
    }

    /// The load-time check hands llama.cpp the GGUF's embedded Jinja; these
    /// excerpts carry the markers it detects each family by.
    func testEmbeddedTemplatesAreReadAsTheirFamily() throws {
        let excerpts: [(TemplateFamily, String)] = [
            (.chatml, "{%- for message in messages %}{{- '<|im_start|>' + message.role + '\\n' + message.content + '<|im_end|>' + '\\n' }}{%- endfor %}{%- if add_generation_prompt %}{{- '<|im_start|>assistant\\n' }}{%- if enable_thinking is defined and enable_thinking is false %}{{- '<think>\\n\\n</think>\\n\\n' }}{%- endif %}{%- endif %}<tool_call>"),
            (.granite, "{%- for message in messages %}{{- '<|start_of_role|>' + message['role'] + '<|end_of_role|>' + message['content'] + '<|end_of_text|>\\n' }}{%- endfor %}{%- if add_generation_prompt %}{{- '<|start_of_role|>assistant<|end_of_role|>' }}{%- endif %}<tool_call><tools>"),
        ]
        for (family, excerpt) in excerpts {
            XCTAssertEqual(try LocalRuntime.render(LocalRuntime.probe, template: excerpt), family.render(LocalRuntime.probe))
        }
    }

    func testEveryFamilyMatchesTheNativeFormatter() throws {
        for family in TemplateFamily.allCases {
            XCTAssertEqual(try LocalRuntime.render(chat, template: family.nativeName), family.render(chat))
        }
    }

    func testProfileTable() {
        XCTAssertEqual(ModelProfile.all.map(\.id),
            ["qwen3-4b-instruct-2507", "qwen3.5-4b", "qwen3.5-2b", "minicpm5-2b", "minicpm5-1b", "granite-4.1-3b"])
        XCTAssertEqual(Set(ModelProfile.all.map(\.sha256)).count, ModelProfile.all.count)
        for profile in ModelProfile.all {
            XCTAssertNotNil(profile.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
            XCTAssertEqual(profile.context, 2048)
            XCTAssertEqual(profile.output, 256)
            XCTAssertEqual(profile.admissionBytes, profile.bytes + 608_736_160)
            XCTAssertNoThrow(try LocalModelOptions(context: profile.context, output: profile.output))
            XCTAssertTrue(profile.stopTexts.allSatisfy { $0 == profile.family.turnEnd })
            XCTAssertEqual(ModelProfile.byID(profile.id)?.sha256, profile.sha256)
            if profile.id != ModelProfile.qwen3_4b.id {
                XCTAssertTrue(profile.checksEmbeddedTemplate)
                XCTAssertNil(profile.pinnedIDs)
                XCTAssertEqual(profile.bos, .fromVocabulary)
            }
        }
        XCTAssertNil(ModelProfile.byID("unknown"))
    }

    func testThinkingLeakDetection() {
        XCTAssertTrue(LocalRuntime.leaksThinking("<think>plan"))
        XCTAssertTrue(LocalRuntime.leaksThinking("done</think>"))
        XCTAssertFalse(LocalRuntime.leaksThinking("Copper Finch."))
    }
}
