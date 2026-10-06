#!/bin/bash
set -euo pipefail
eval_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$eval_dir/artifacts"
model="$eval_dir/artifacts/Qwen3-0.6B-Q4_K_M.gguf"
expected=ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a
if [[ ! -f "$model" ]]; then
  free_kib="$(df -k "$eval_dir" | tail -1 | awk '{print $4}')"
  if [[ "$free_kib" -lt 4718592 ]]; then
    echo 'Need at least 4.5 GiB free for model, reserve and build overhead.' >&2
    exit 1
  fi
  curl --fail --location --retry 2 --max-filesize 396705472 --output "$model.part" \
    https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf
  [[ "$(stat -f %z "$model.part")" == 396705472 ]]
  [[ "$(shasum -a 256 "$model.part" | awk '{print $1}')" == "$expected" ]]
  mv "$model.part" "$model"
fi
[[ "$(stat -f %z "$model")" == 396705472 ]]
[[ "$(shasum -a 256 "$model" | awk '{print $1}')" == "$expected" ]]
echo 'Model size and SHA-256 verified.'
publisher=https://huggingface.co/Qwen/Qwen3-0.6B/resolve/c1899de289a04d12100db370d81485cdf75e47ca
for filename in LICENSE README.md tokenizer.json tokenizer_config.json generation_config.json config.json; do
  curl --fail --location --silent --show-error --output "$eval_dir/artifacts/$filename" "$publisher/$filename"
done
curl --fail --location --silent --show-error --output "$eval_dir/artifacts/converter-README.md" \
  https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/README.md
