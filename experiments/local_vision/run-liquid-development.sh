#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 experiments/local_vision/run-liquid-development.py
