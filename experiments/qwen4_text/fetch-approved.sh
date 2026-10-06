#!/bin/bash
set -euo pipefail
eval_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$eval_dir/artifacts"
model="$eval_dir/artifacts/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
expected=3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597
if [[ ! -f "$model" ]]; then
  free_kib="$(df -k "$eval_dir" | tail -1 | awk '{print $4}')"
  if [[ "$free_kib" -lt 4718592 ]]; then
    echo 'Need at least 4.5 GiB free for model, reserve and build overhead.' >&2
    exit 1
  fi
  curl --fail --location --retry 2 --max-filesize 2497281120 --output "$model.part" \
    https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q4_K_M.gguf
  [[ "$(stat -f %z "$model.part")" == 2497281120 ]]
  [[ "$(shasum -a 256 "$model.part" | awk '{print $1}')" == "$expected" ]]
  mv "$model.part" "$model"
fi
[[ "$(stat -f %z "$model")" == 2497281120 ]]
[[ "$(shasum -a 256 "$model" | awk '{print $1}')" == "$expected" ]]
echo 'Model size and SHA-256 verified.'
publisher=https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/resolve/cdbee75f17c01a7cc42f958dc650907174af0554
for filename in LICENSE README.md tokenizer.json tokenizer_config.json generation_config.json config.json; do
  curl --fail --location --silent --show-error --output "$eval_dir/artifacts/$filename" "$publisher/$filename"
done
curl --fail --location --silent --show-error --output "$eval_dir/artifacts/converter-README.md" \
  https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/README.md
