#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p ../target/units

echo "Building floriajs examples..."
for ex in hello_floriajs parse_qml_demo reactive_qml_demo; do
    echo "  Compiling ${ex}.pas..."
    fpc -Mobjfpc -Sh -FU../target/units -Fu../src/main/pascal -FE. "${ex}.pas"
done
echo "All examples built successfully."
