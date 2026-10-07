// Diagnostic only: independent C++ caller, shared pinned runtime and weights.
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <llama/llama.h>
#include <algorithm>
#include <fstream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

static std::string hex(const unsigned char *bytes) {
    const char *digits = "0123456789abcdef";
    std::string result;
    for (int i = 0; i < 32; ++i) { result += digits[bytes[i] >> 4]; result += digits[bytes[i] & 15]; }
    return result;
}
static std::string hash(const std::string &value) {
    unsigned char bytes[32]; CC_SHA256(value.data(), (CC_LONG)value.size(), bytes); return hex(bytes);
}
static void verifyModel(const char *path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("missing model");
    CC_SHA256_CTX state; CC_SHA256_Init(&state);
    std::vector<char> buffer(1024 * 1024); uint64_t size = 0;
    while (stream) {
        stream.read(buffer.data(), buffer.size()); auto count = stream.gcount(); size += count;
        CC_SHA256_Update(&state, buffer.data(), (CC_LONG)count);
    }
    unsigned char digest[32]; CC_SHA256_Final(digest, &state);
    if (size != 2497281120ULL || hex(digest) != "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597")
        throw std::runtime_error("model pin mismatch");
}
static NSString *ns(const std::string &s) {
    NSString *value = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    if (!value) throw std::runtime_error("invalid UTF-8");
    return value;
}
static std::string piece(const llama_vocab *vocab, llama_token token, bool special = false) {
    std::vector<char> data(512);
    int count = llama_token_to_piece(vocab, token, data.data(), (int)data.size(), 0, special);
    if (count < 0) { data.resize(-count); count = llama_token_to_piece(vocab, token, data.data(), (int)data.size(), 0, special); }
    if (count < 0) throw std::runtime_error("token render failed");
    return std::string(data.data(), count);
}
static std::vector<llama_token> tokenize(const llama_vocab *vocab, const std::string &s, bool automaticBOS) {
    std::vector<llama_token> tokens(s.size() + 16);
    int count = llama_tokenize(vocab, s.data(), (int)s.size(), tokens.data(), (int)tokens.size(), automaticBOS, true);
    if (count <= 0 || count > (int)tokens.size()) throw std::runtime_error("tokenization failed");
    tokens.resize(count); return tokens;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        try {
            if (argc != 6) throw std::runtime_error("control MODEL PROMPT metal|cpu baseline|greedy legacy|ext");
            std::string backend = argv[3], sampling = argv[4], api = argv[5];
            if ((backend != "metal" && backend != "cpu") ||
                (sampling != "baseline" && sampling != "greedy") ||
                (api != "legacy" && api != "ext")) throw std::runtime_error("unknown control");
            verifyModel(argv[1]);
            NSError *error = nil;
            NSString *userString = [NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:&error];
            if (!userString) throw std::runtime_error("prompt unavailable");
            std::string user = userString.UTF8String;
            if (user.size() > 65536 || user.find("<|") != std::string::npos || user.find('\0') != std::string::npos)
                throw std::runtime_error("invalid diagnostic prompt");
            std::string system = "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data.";
            std::string body = "<|im_start|>system\n" + system + "<|im_end|>\n<|im_start|>user\n" + user + "<|im_end|>\n<|im_start|>assistant\n";
            std::string prompt = body; // Qwen publisher template: no BOS, no thinking suffix.
            llama_backend_init();
            auto mp = llama_model_default_params(); mp.n_gpu_layers = backend == "metal" ? 99 : 0;
            auto model = llama_model_load_from_file(argv[1], mp);
            if (!model) throw std::runtime_error("model load failed");
            auto vocab = llama_model_get_vocab(model);
            auto tokens = tokenize(vocab, prompt, false);
            if (tokens.front() != 151644 || std::count(tokens.begin(), tokens.end(), 151643) != 0 ||
                llama_vocab_eos(vocab) != 151645 || !llama_vocab_is_eog(vocab, 151645) || !llama_vocab_is_eog(vocab, 151643))
                throw std::runtime_error("Qwen special-token framing mismatch");
            if (tokens.size() + 128 > 2048) throw std::runtime_error("context overflow");
            std::string roundtrip, tokenIDs;
            for (auto token : tokens) {
                roundtrip += piece(vocab, token, true);
                if (!tokenIDs.empty()) tokenIDs += ",";
                tokenIDs += std::to_string(token);
            }
            if (roundtrip != prompt) throw std::runtime_error("token roundtrip mismatch");
            auto cp = llama_context_default_params();
            cp.n_ctx = 2048; cp.n_batch = 128; cp.n_ubatch = 128; cp.n_threads = 4; cp.n_threads_batch = 4;
            if (backend == "cpu") { cp.offload_kqv = false; cp.op_offload = false; }
            auto ctx = llama_init_from_model(model, cp);
            if (!ctx) throw std::runtime_error("context failed");
            auto sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
            if (sampling == "greedy") llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
            else {
                llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20));
                llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.8, 1));
                llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7));
                llama_sampler_chain_add(sampler, llama_sampler_init_dist(42));
            }
            auto batch = llama_batch_init(128, 0, 1);
            auto ext = llama_batch_ext_init(ctx);
            auto decode = [&](const llama_token *ids, int count, int offset) {
                int status;
                if (api == "legacy") {
                    batch.n_tokens = count;
                    for (int i = 0; i < count; ++i) {
                        batch.token[i] = ids[i]; batch.pos[i] = offset + i;
                        batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0;
                        batch.logits[i] = i == count - 1;
                    }
                    status = llama_decode(ctx, batch);
                } else {
                    llama_batch_ext_clear(ext);
                    for (int i = 0; i < count; ++i) {
                        auto index = llama_batch_ext_add_token(ext, 0, ids[i]);
                        llama_pos pos = offset + i;
                        if (!llama_batch_ext_set_pos(ext, index, &pos)) throw std::runtime_error("position failed");
                    }
                    if (!llama_batch_ext_set_output_logits(ext, count - 1, true)) throw std::runtime_error("logit flag failed");
                    status = llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, ext);
                }
                if (status) throw std::runtime_error("decode failed");
            };
            for (int offset = 0; offset < (int)tokens.size(); offset += 128)
                decode(tokens.data() + offset, std::min(128, (int)tokens.size() - offset), offset);
            float *logits = llama_get_logits_ith(ctx, -1);
            if (!logits) throw std::runtime_error("no logits");
            std::vector<int> indices(llama_vocab_n_tokens(vocab)); std::iota(indices.begin(), indices.end(), 0);
            std::partial_sort(indices.begin(), indices.begin() + 8, indices.end(), [&](int a, int b) { return logits[a] > logits[b]; });
            NSMutableArray *top = [NSMutableArray array];
            for (int i = 0; i < 8; ++i) [top addObject:@{@"id": @(indices[i]), @"piece": ns(piece(vocab, indices[i], true)), @"logit": @(logits[indices[i]])}];
            std::string response, outcome = "output-limit";
            int count = 0;
            while (count < 128) {
                auto token = llama_sampler_sample(sampler, ctx, -1);
                if (llama_vocab_is_eog(vocab, token)) { outcome = "completed"; break; }
                response += piece(vocab, token); ++count;
                if (count < 128) decode(&token, 1, (int)tokens.size() + count - 1);
            }
            NSDictionary *report = @{
                @"qualification": @"diagnostic control only; not a replacement quality score",
                @"backend": ns(backend), @"sampling": ns(sampling), @"decode_api": ns(api),
                @"prompt": ns(prompt), @"prompt_sha256": ns(hash(prompt)), @"token_ids_sha256": ns(hash(tokenIDs)),
                @"prompt_tokens": @(tokens.size()), @"token_ids": ns(tokenIDs), @"bos": @(llama_vocab_bos(vocab)),
                @"eos": @(llama_vocab_eos(vocab)), @"no_bos_template": @YES, @"roundtrip_matches": @YES,
                @"raw_first_token_top8": top, @"response": ns(response), @"outcome": ns(outcome),
                @"model_template": @(llama_model_chat_template(model, nullptr)),
            };
            NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
            if (!json) throw std::runtime_error("JSON failed");
            [[NSFileHandle fileHandleWithStandardOutput] writeData:json];
            llama_batch_ext_free(ext); llama_batch_free(batch); llama_sampler_free(sampler);
            llama_free(ctx); llama_model_free(model); llama_backend_free();
            return 0;
        } catch (const std::exception &error) {
            fprintf(stderr, "DIAGNOSTIC FAILED: %s\n", error.what()); return 1;
        }
    }
}
