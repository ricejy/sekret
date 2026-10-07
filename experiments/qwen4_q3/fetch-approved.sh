#!/bin/bash
set -euo pipefail
eval_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$eval_dir/artifacts"
model="$eval_dir/artifacts/Qwen3-4B-Instruct-2507-Q3_K_M.gguf"
expected=9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9
if [[ ! -f "$model" ]]; then
  free_kib="$(df -k "$eval_dir" | tail -1 | awk '{print $4}')"
  if [[ "$free_kib" -lt 10000000 ]]; then
    echo 'Need at least 10.24 GB free before downloading, to retain the evaluation reserve.' >&2
    exit 1
  fi
  curl --fail --location --retry 2 --max-filesize 2075618400 --output "$model.part" \
    https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q3_K_M.gguf
  [[ "$(stat -f %z "$model.part")" == 2075618400 ]]
  [[ "$(shasum -a 256 "$model.part" | awk '{print $1}')" == "$expected" ]]
  mv "$model.part" "$model"
fi
[[ "$(stat -f %z "$model")" == 2075618400 ]]
[[ "$(shasum -a 256 "$model" | awk '{print $1}')" == "$expected" ]]
echo 'Q3 model size and SHA-256 verified.'
