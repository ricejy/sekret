#!/bin/bash
set -euo pipefail
vision_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$vision_dir/artifacts/gemma"
free_kib="$(df -k "$vision_dir" | tail -1 | awk '{print $4}')"
# 4.039 GiB pair + 1.5 GiB reserve.
if [[ "$free_kib" -lt 5872026 ]]; then
  echo 'Need at least 5.6 GiB free before retrieving this approved pair.' >&2
  exit 1
fi
base='https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/resolve/675cff42a74c774d6cb76f76d8eacb49b48c9b93'
fetch_one() {
  local name="$1" bytes="$2" digest="$3"
  local target="$vision_dir/artifacts/gemma/$name"
  if [[ ! -f "$target" ]]; then
    curl --fail --location --retry 2 --continue-at - --output "$target.part" "$base/$name"
    [[ "$(stat -f %z "$target.part")" == "$bytes" ]]
    [[ "$(shasum -a 256 "$target.part" | awk '{print $1}')" == "$digest" ]]
    mv "$target.part" "$target"
  fi
  [[ "$(stat -f %z "$target")" == "$bytes" ]]
  [[ "$(shasum -a 256 "$target" | awk '{print $1}')" == "$digest" ]]
  echo "Verified $name ($bytes bytes)"
}
fetch_one gemma-4-E2B_q4_0-it.gguf 3349516256 fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634
fetch_one gemma-4-E2B-it-mmproj.gguf 986833664 021059cce659fe7f9170d5599761d7bbaf644b798dab9503aca30dc43e6beb14
curl --fail --location --output "$vision_dir/artifacts/gemma/model-card.md" "$base/README.md"
checkpoint='https://huggingface.co/google/gemma-4-E2B-it/resolve/3e22461f65e89153144f8adb70e3b8c2cc9845a7'
curl --fail --location --output "$vision_dir/artifacts/gemma/chat_template.jinja" "$checkpoint/chat_template.jinja"
curl --fail --location --output "$vision_dir/artifacts/gemma/processor_config.json" "$checkpoint/processor_config.json"
