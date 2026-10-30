// Leak detection off at build time (ASan/UBSan stay on); linked into every fuzz + standalone binary.
extern "C" int __lsan_is_turned_off() { return 1; }
