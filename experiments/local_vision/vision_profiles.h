#pragma once
#include <cstdint>
#include <string>

// Exact, fixed evaluation adapters; not arbitrary model discovery/loading.
struct VisionProfile {
    const char *name;
    uint64_t modelBytes, projectorBytes;
    const char *modelHash, *projectorHash, *templateVersion;
    bool explicitBos;
    std::string prefix, suffix;
    // Optional system turn, rendered before prefix; empty when unsupported.
    std::string systemPrefix = "", systemSuffix = "";
};
inline VisionProfile smolProfile() {
    return {"SmolVLM-500M-Instruct-Q8_0", 436806912, 108783360,
        "9d4612de6a42214499e301494a3ecc2be0abdd9de44e663bda63f1152fad1bf4",
        "d1eb8b6b23979205fdf63703ed10f788131a3f812c7b1f72e0119d5d81295150",
        "publisher-a7da5b9-single-user-image-text-v1", false,
        "<|im_start|>User:", "<end_of_utterance>\nAssistant:"};
}
inline VisionProfile liquidProfile() {
    return {"LFM2.5-VL-1.6B-Q8_0", 1246254880, 583109888,
        "a34bd1506a298d7ff07902e69baeac48c7c20bb85162e61218b743dc10be7c67",
        "2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d",
        "publisher-919fde3-single-user-image-text-v1", true,
        "<|startoftext|><|im_start|>user\n", "<|im_end|>\n<|im_start|>assistant\n"};
}
inline VisionProfile gemmaProfile() {
    // google/gemma-4-E2B-it chat_template.jinja at 3e22461f: optional system turn
    // (content trimmed), one image-first user turn, generation prompt, thinking off.
    return {"gemma-4-E2B-it-qat-q4_0", 3349516256, 986833664,
        "fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634",
        "021059cce659fe7f9170d5599761d7bbaf644b798dab9503aca30dc43e6beb14",
        "publisher-3e22461-system-single-user-image-text-v1", true,
        "<|turn>user\n", "<turn|>\n<|turn>model\n",
        "<|turn>system\n", "<turn|>\n"};
}
