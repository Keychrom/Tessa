#!/bin/sh
# Run the parser fuzz pass with the system ASan runtime preloaded. Zig 0.16
# does not expose compile-time AddressSanitizer instrumentation, so this is an
# allocator/interceptor pass over the same Debug-safety build.
set -eu

cd "$(dirname "$0")/.."
TESSA_FUZZ_ASAN=1 TESSA_FUZZ_ITERS="${TESSA_FUZZ_ITERS:-60}" exec sh tests/fuzz-parsers.sh "$@"
