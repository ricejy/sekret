#include <llama/llama.h>
#include <llama/mtmd.h>
#include <llama/mtmd-helper.h>
#include <cstdio>

int main() {
    auto params = mtmd_context_params_default();
    auto chunks = mtmd_input_chunks_init();
    if (!chunks || !mtmd_default_marker()) return 1;
    std::printf("mtmd marker=%s chunks=%zu threads=%d\n",
                mtmd_default_marker(), mtmd_input_chunks_size(chunks), params.n_threads);
    mtmd_input_chunks_free(chunks);
    // Volatile references force link resolution without loading model weights.
    auto volatile load = &mtmd_init_from_file;
    auto volatile evaluate = &mtmd_helper_eval_chunks;
    auto volatile tokenize = &mtmd_tokenize;
    auto volatile bitmap = &mtmd_bitmap_init;
    return !load || !evaluate || !tokenize || !bitmap;
}
