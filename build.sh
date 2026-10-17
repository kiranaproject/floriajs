#!/usr/bin/env bash
set -euo pipefail

# Build script for floriajs supporting compile, test, install, and clean

TARGET="${1:-compile}"

case "${TARGET}" in
  compile)
    echo "==> Compiling floriajs library..."
    shift 1 || true
    pasbuild compile "$@"
    ;;
  test)
    echo "==> Running floriajs tests..."
    shift 1 || true
    pasbuild test "$@"
    ;;
  install)
    echo "==> Installing floriajs to local repository..."
    shift 1 || true
    pasbuild install "$@"
    ;;
  examples)
    echo "==> Building floriajs examples..."
    shift 1 || true
    ./examples/build_examples.sh "$@"
    ;;
  clean)
    echo "==> Cleaning target artifacts..."
    shift 1 || true
    pasbuild clean "$@"
    rm -f examples/hello_floriajs examples/parse_ftml_demo examples/reactive_ftml_demo examples/parse_qml_demo examples/reactive_qml_demo
    ;;
  *)
    echo "Usage: $0 [compile|test|install|examples|clean]"
    exit 1
    ;;
esac
