#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <CommonCrypto/CommonDigest.h>
#include <llama/llama.h>
#include <llama/mtmd.h>
#include <llama/mtmd-helper.h>
#include <mach/mach.h>
#include <sys/resource.h>
#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include "vision_profiles.h"

using Clock = std::chrono::steady_clock;
static volatile sig_atomic_t stopped = 0;
static void interrupt(int) { stopped = 1; }
static bool aborted(void *) { return stopped != 0; }
static double seconds(Clock::time_point from) {
    return std::chrono::duration<double>(Clock::now() - from).count();
}
static std::string hashFile(const std::string &path, uint64_t expected = 0) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("Cannot read local file: " + path);
    CC_SHA256_CTX state;
    CC_SHA256_Init(&state);
    std::vector<char> buffer(1024 * 1024);
    uint64_t bytes = 0;
    while (file) {
        file.read(buffer.data(), buffer.size());
        auto count = file.gcount();
        bytes += count;
        CC_SHA256_Update(&state, buffer.data(), (CC_LONG)count);
        if (stopped) throw std::runtime_error("Interrupted during hash verification");
    }
    if (expected && bytes != expected) throw std::runtime_error("Artifact byte count mismatch");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &state);
    char hex[65] = {};
    for (int i = 0; i < 32; ++i) std::snprintf(hex + 2*i, 3, "%02x", digest[i]);
    return hex;
}
static uint64_t footprint() {
    task_vm_info_data_t info{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS
        ? info.phys_footprint : 0;
}
struct MemoryProbe {
    std::atomic<bool> active{true};
    std::atomic<uint64_t> peak{0};
    std::thread worker;
    MemoryProbe() : worker([this] {
        while (active) {
            auto value = footprint();
            if (value > peak) peak = value;
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
    }) {}
    ~MemoryProbe() { active = false; worker.join(); }
};
struct Pixels { size_t width, height; std::vector<unsigned char> rgb; };
static Pixels readImage(NSString *path) {
    auto url = [NSURL fileURLWithPath:path];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attributes || [attributes fileSize] > 32 * 1024 * 1024) {
        throw std::runtime_error("Image unavailable or larger than 32 MiB");
    }
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!source) throw std::runtime_error("ImageIO could not read image");
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @1024,
        (id)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image) throw std::runtime_error("ImageIO could not decode image");
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (!width || !height || width > 1024 || height > 1024) {
        CGImageRelease(image);
        throw std::runtime_error("Unexpected decoded dimensions");
    }
    std::vector<unsigned char> rgba(width * height * 4);
    CGColorSpaceRef colors = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef canvas = CGBitmapContextCreate(rgba.data(), width, height, 8, width * 4,
        colors, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colors);
    if (!canvas) { CGImageRelease(image); throw std::runtime_error("RGB canvas failed"); }
    CGContextSetRGBFillColor(canvas, 1, 1, 1, 1);
    CGContextFillRect(canvas, CGRectMake(0, 0, width, height));
    CGContextDrawImage(canvas, CGRectMake(0, 0, width, height), image);
    CGContextRelease(canvas);
    CGImageRelease(image);
    Pixels pixels{width, height, std::vector<unsigned char>(width * height * 3)};
    for (size_t i = 0; i < width * height; ++i) {
        for (int c = 0; c < 3; ++c) pixels.rgb[3*i+c] = rgba[4*i+c];
    }
    return pixels;
}
static void writeJSON(NSDictionary *value, NSString *path) {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!json || ![json writeToFile:path options:NSDataWritingAtomic error:&error]) {
        throw std::runtime_error("Cannot write result JSON");
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        try {
            const bool liquid = argc == 7 && std::string(argv[1]) == "--liquid";
            if (liquid) { ++argv; --argc; }
            const auto profile = liquid ? liquidProfile() : smolProfile();
            if (argc != 6) {
                std::fprintf(stderr, "usage: local-vision-eval [--liquid] model.gguf projector.gguf image prompt result.json\n");
                return 2;
            }
            std::signal(SIGINT, interrupt);
            std::signal(SIGTERM, interrupt);
            const auto started = Clock::now();
            const std::string modelHash = hashFile(argv[1], profile.modelBytes);
            const std::string projectorHash = hashFile(argv[2], profile.projectorBytes);
            if (modelHash != profile.modelHash || projectorHash != profile.projectorHash) {
                throw std::runtime_error("Pinned artifact SHA-256 mismatch");
            }
            const auto imageHash = hashFile(argv[3]);
            const std::string question = argv[4];
            if (question.empty() || question.size() > 4096 || question.find('<') != std::string::npos) {
                throw std::runtime_error("Use a plain-text evaluation question, at most 4096 bytes");
            }
            MemoryProbe memory;
            llama_backend_init();
            const auto loadStarted = Clock::now();
            auto modelParams = llama_model_default_params();
            modelParams.n_gpu_layers = 99;
            std::unique_ptr<llama_model, decltype(&llama_model_free)> model(
                llama_model_load_from_file(argv[1], modelParams), llama_model_free);
            if (!model) throw std::runtime_error("Language GGUF loading failed");
            auto visionParams = mtmd_context_params_default();
            visionParams.use_gpu = true;
            visionParams.n_threads = 4;
            visionParams.warmup = false;
            if (liquid) {
                visionParams.image_min_tokens = 64;
                visionParams.image_max_tokens = 256;
            }
            std::unique_ptr<mtmd_context, decltype(&mtmd_free)> vision(
                mtmd_init_from_file(argv[2], model.get(), visionParams), mtmd_free);
            if (!vision || !mtmd_support_vision(vision.get())) throw std::runtime_error("Vision projector loading failed");
            const double loadSeconds = seconds(loadStarted);
            auto pixels = readImage([NSString stringWithUTF8String:argv[3]]);
            std::unique_ptr<mtmd_bitmap, decltype(&mtmd_bitmap_free)> bitmap(
                mtmd_bitmap_init((uint32_t)pixels.width, (uint32_t)pixels.height, pixels.rgb.data()), mtmd_bitmap_free);
            if (!bitmap) throw std::runtime_error("RGB bitmap admission failed");
            mtmd_bitmap_set_id(bitmap.get(), imageHash.c_str());
            // Exact single user turn subset of the publisher's pinned template.
            // libmtmd replaces its media marker with this architecture's image tokens.
            const std::string prompt = profile.prefix + mtmd_default_marker() + question + profile.suffix;
            auto input = mtmd_input_text{prompt.c_str(), prompt.size(), !profile.explicitBos, true};
            const mtmd_bitmap *images[] = {bitmap.get()};
            std::unique_ptr<mtmd_input_chunks, decltype(&mtmd_input_chunks_free)> chunks(
                mtmd_input_chunks_init(), mtmd_input_chunks_free);
            if (mtmd_tokenize(vision.get(), chunks.get(), &input, images, 1)) {
                throw std::runtime_error("Multimodal tokenization failed");
            }
            auto vocab = llama_model_get_vocab(model.get());
            int bosCount = 0;
            NSMutableArray *chunkDetails = [NSMutableArray array];
            for (size_t i = 0; i < mtmd_input_chunks_size(chunks.get()); ++i) {
                auto chunk = mtmd_input_chunks_get(chunks.get(), i);
                auto type = mtmd_input_chunk_get_type(chunk);
                size_t count = 0;
                if (type == MTMD_INPUT_CHUNK_TYPE_TEXT) {
                    auto tokens = mtmd_input_chunk_get_tokens_text(chunk, &count);
                    for (size_t t = 0; t < count; ++t) if (tokens[t] == llama_vocab_bos(vocab)) ++bosCount;
                }
                [chunkDetails addObject:@{@"type": @(type), @"tokens": @(mtmd_input_chunk_get_n_tokens(chunk))}];
            }
            if (liquid && bosCount != 1) throw std::runtime_error("Liquid prompt must have exactly one BOS token");
            constexpr int contextSize = 2048, outputCap = 128, batchSize = 512;
            const size_t inputTokens = mtmd_helper_get_n_tokens(chunks.get());
            const auto positions = mtmd_helper_get_n_pos(chunks.get());
            if (inputTokens + outputCap > contextSize || positions + outputCap > contextSize) {
                throw std::runtime_error("Image/text input plus output reservation exceeds context; no truncation");
            }
            auto params = llama_context_default_params();
            params.n_ctx = contextSize;
            params.n_batch = batchSize;
            params.n_ubatch = batchSize;
            params.n_threads = 4;
            params.n_threads_batch = 4;
            params.abort_callback = aborted;
            std::unique_ptr<llama_context, decltype(&llama_free)> context(
                llama_init_from_model(model.get(), params), llama_free);
            if (!context) throw std::runtime_error("Decoder context failed");
            const auto generationStarted = Clock::now();
            llama_pos past = 0;
            int status = mtmd_helper_eval_chunks(vision.get(), context.get(), chunks.get(), 0, 0, batchSize, true, &past);
            if (status) throw std::runtime_error("Multimodal encoding/evaluation failed: " + std::to_string(status));
            const double prefillSeconds = seconds(generationStarted);
            std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(
                llama_sampler_init_greedy(), llama_sampler_free);
            std::string output, outcome = "output-limit";
            double firstTokenSeconds = -1;
            int outputTokens = 0;
            for (; outputTokens < outputCap && !stopped; ) {
                llama_token token = llama_sampler_sample(sampler.get(), context.get(), -1);
                if (llama_vocab_is_eog(vocab, token)) { outcome = "completed"; break; }
                std::vector<char> piece(256);
                int count = llama_token_to_piece(vocab, token, piece.data(), (int)piece.size(), 0, false);
                if (count < 0) {
                    piece.resize(-count);
                    count = llama_token_to_piece(vocab, token, piece.data(), (int)piece.size(), 0, false);
                }
                if (count < 0) throw std::runtime_error("Token rendering failed");
                output.append(piece.data(), count);
                ++outputTokens;
                if (firstTokenSeconds < 0) firstTokenSeconds = seconds(generationStarted);
                auto batch = llama_batch_get_one(&token, 1);
                if (outputTokens < outputCap && llama_decode(context.get(), batch)) {
                    throw std::runtime_error("Decoder failed or interrupted");
                }
            }
            if (stopped) outcome = "interrupted";
            NSString *response = [[NSString alloc] initWithBytes:output.data() length:output.size() encoding:NSUTF8StringEncoding];
            if (!response) throw std::runtime_error("Incomplete UTF-8 output");
            rusage usage{};
            getrusage(RUSAGE_SELF, &usage);
            NSDictionary *result = @{
                @"qualification": @"Mac-only feasibility; not iPhone or production acceptance",
                @"runtime": @"llama.cpp b11429 / d81235049384534c167caea52b85a694f6103d14",
                @"model_sha256": @(modelHash.c_str()), @"projector_sha256": @(projectorHash.c_str()),
                @"image_sha256": @(imageHash.c_str()), @"image_path": @(argv[3]), @"question": @(argv[4]),
                @"model": @(profile.name), @"template": @(profile.templateVersion),
                @"sampling": @"greedy", @"bos_count_in_text_chunks": @(bosCount), @"chunks": chunkDetails,
                @"configured_image_min_tokens": @(visionParams.image_min_tokens),
                @"configured_image_max_tokens": @(visionParams.image_max_tokens),
                @"prompt": @(prompt.c_str()), @"outcome": @(outcome.c_str()), @"response": response,
                @"decoded_width": @(pixels.width), @"decoded_height": @(pixels.height),
                @"preprocessing": @"ImageIO oriented sRGB white-alpha composite; longest edge capped 1024; mtmd model preprocessing",
                @"input_tokens": @(inputTokens), @"input_positions": @(positions),
                @"context": @(contextSize), @"output_cap": @(outputCap), @"output_tokens": @(outputTokens),
                @"load_seconds": @(loadSeconds), @"prefill_seconds": @(prefillSeconds),
                @"first_token_seconds_after_context": @(firstTokenSeconds),
                @"generation_seconds": @(seconds(generationStarted)), @"total_seconds_with_hashing": @(seconds(started)),
                @"sampled_peak_footprint_bytes": @(memory.peak.load()), @"process_peak_rss_bytes": @(usage.ru_maxrss),
                @"thermal_state": @([NSProcessInfo processInfo].thermalState),
                @"os": [NSProcessInfo processInfo].operatingSystemVersionString,
            };
            writeJSON(result, [NSString stringWithUTF8String:argv[5]]);
            std::printf("%s\n", response.UTF8String);
            return stopped ? 130 : 0;
        } catch (const std::exception &error) {
            std::fprintf(stderr, "VISION EVALUATION FAILED: %s\n", error.what());
            return 1;
        }
    }
}
