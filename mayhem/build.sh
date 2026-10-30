#!/usr/bin/env bash
#
# mayhem/build.sh — build perfetto's libFuzzer harnesses (sanitized, DWARF 3, one `-standalone`
# reproducer each) and the trace_processor_shell test oracle (normal flags). Idempotent and
# air-gapped on re-run: the first (online) run fills /opt/toolchains/perfetto-deps with the
# build deps that tools/install-build-deps would download into the (gitignored) tree; every run
# restores them from there.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${DEPS_CACHE:=/opt/toolchains/perfetto-deps}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

FUZZERS="buffered_frame_deserializer_fuzzer protozero_decoder_fuzzer protozero_bytecode_parser_fuzzer
protozero_message_filter_fuzzer packet_stream_validator_fuzzer trace_processor_fuzzer cpu_reader_fuzzer
end_to_end_shared_memory_fuzzer producer_socket_fuzzer shared_ring_buffer_fuzzer
shared_ring_buffer_write_fuzzer unwinding_fuzzer"

# 0) Build deps: fetch once into the in-image cache, then restore into the tree.
if [ ! -e "$DEPS_CACHE/.complete" ]; then
  python3 mayhem/fetch-deps.py "$SRC" "$DEPS_CACHE"
  touch "$DEPS_CACHE/.complete"
fi
cp -au "$DEPS_CACHE"/buildtools "$DEPS_CACHE"/third_party "$SRC"/
GN="$SRC/third_party/gn/gn"

COMMON_ARGS="is_clang=true is_debug=false is_hermetic_clang=false use_custom_libcxx=false \
is_cross_compiling=true skip_buildtools_check=true is_system_compiler=true \
cc=\"$CC\" cxx=\"$CXX\" linker=\"lld\""

# 1) Sanitized fuzz build (project + harnesses), as oss-fuzz does it.
mkdir -p out
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o out/lsan_off.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/sock_init.cc -o out/sock_init.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "${STANDALONE_FUZZ_MAIN:-/opt/mayhem/StandaloneFuzzTargetMain.c}" -o out/standalone_main.o

FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fno-sanitize=vptr -Wno-implicit-int-float-conversion"
FUZZ_ARGS="$COMMON_ARGS is_fuzzer=true use_libfuzzer=false link_fuzzer=\"-fsanitize=fuzzer\" \
extra_target_cflags=\"$FUZZ_CFLAGS\" extra_target_cxxflags=\"$FUZZ_CFLAGS\" \
extra_target_ldflags=\"$SANITIZER_FLAGS $SRC/out/lsan_off.o\""
case "$SANITIZER_FLAGS" in *address*) FUZZ_ARGS="$FUZZ_ARGS is_asan=true" ;; esac
$GN gen out/fuzz --args="$FUZZ_ARGS" --check
ninja -d keeprsp -C out/fuzz -j"$MAYHEM_JOBS" fuzzers   # keep the link .rsp files: step 2 re-links from them

# 2) Fuzzer binaries at /mayhem/<name> and non-fuzzer `-standalone` reproducers (same link line
#    with the run-once driver instead of libFuzzer).
# The two service-starting fuzzers also link mayhem/sock_init.cc (per-process socket paths).
SOCK_FUZZERS=" end_to_end_shared_memory_fuzzer producer_socket_fuzzer "
for f in $FUZZERS; do
  extra=""
  case "$SOCK_FUZZERS" in *" $f "*) extra="$SRC/out/sock_init.o" ;; esac
  if [ -n "$extra" ]; then
    rm -f "$SRC/$f"
    (cd out/fuzz && ninja -t commands "$f" | tail -1 \
      | sed -e "s# -o \./$f && .*# $extra -o $SRC/$f#" | bash -e)
  else
    ln -f "out/fuzz/$f" "$SRC/$f"
  fi
  (cd out/fuzz && ninja -t commands "$f" | tail -1 \
    | sed -e "s# -fsanitize=fuzzer # $SRC/out/standalone_main.o #" -e "s# -o \./$f && .*# $extra -o $SRC/$f-standalone#" \
    | bash -e)
done

# 3) Test oracle: trace_processor_shell with the project's NORMAL flags.
TEST_ARGS="$COMMON_ARGS extra_target_cflags=\"$COVERAGE_FLAGS\" extra_target_cxxflags=\"$COVERAGE_FLAGS\" \
extra_target_ldflags=\"$COVERAGE_FLAGS\""
$GN gen out/test --args="$TEST_ARGS" --check
ninja -C out/test -j"$MAYHEM_JOBS" trace_processor_shell
