#!/bin/bash
set -euo pipefail
eval_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$eval_dir"
runtime_archive="artifacts/llama-b11429-xcframework.zip"
expected_runtime="e26a6a0a813f5760fe45834ce239d5b525e4e2442d4fd017221d9f0438383174"
actual_runtime="$(shasum -a 256 "$runtime_archive" | awk '{print $1}')"
if [[ "$actual_runtime" != "$expected_runtime" ]]; then
  echo "Runtime archive hash mismatch. Do not execute." >&2
  exit 1
fi
swift build -c release >&2
has_prompt=false
for argument in "$@"; do
  if [[ "$argument" == "--prompt-file" ]]; then has_prompt=true; fi
done
if [[ "$has_prompt" == false ]]; then
  set -- --prompt-file "$eval_dir/prompts/concise.txt" "$@"
fi
exec .build/release/local-generation-eval \
  --model "$eval_dir/artifacts/Qwen3-0.6B-Q8_0.gguf" \
  "$@"
