// Linked into the two fuzzers that start a tracing service (end_to_end_shared_memory_fuzzer,
// producer_socket_fuzzer). Upstream's TestHelper listens on the fixed, host-global
// /tmp/perfetto-producer and /tmp/perfetto-consumer, so concurrent fuzz processes steal each other's
// sockets ("Address already in use", "Consumer unexpectedly disconnected"). TestHelper takes its
// socket names from these two env vars, so give every process a private directory instead.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <string>

namespace {
std::string g_dir;
std::string g_producer;
std::string g_consumer;

void RemoveSockets() {
  unlink(g_producer.c_str());
  unlink(g_consumer.c_str());
  rmdir(g_dir.c_str());
}
}  // namespace

extern "C" int LLVMFuzzerInitialize(int*, char***) {
  const char* tmp = getenv("TMPDIR");
  std::string tmpl = std::string(tmp && *tmp ? tmp : "/tmp") + "/perfetto-fuzz-XXXXXX";
  if (!mkdtemp(&tmpl[0])) {
    perror("mkdtemp");
    abort();
  }
  g_dir = tmpl;
  g_producer = g_dir + "/producer";
  g_consumer = g_dir + "/consumer";
  // sockaddr_un::sun_path is 108 bytes.
  if (g_producer.size() >= 100 || g_consumer.size() >= 100) {
    fprintf(stderr, "socket path too long: %s\n", g_producer.c_str());
    abort();
  }
  setenv("PERFETTO_PRODUCER_SOCK_NAME", g_producer.c_str(), 1);
  setenv("PERFETTO_CONSUMER_SOCK_NAME", g_consumer.c_str(), 1);
  atexit(RemoveSockets);
  return 0;
}
