#!/usr/bin/env python3
"""Populate an out-of-tree cache with the build deps tools/install-build-deps would
download into the tree (minus the clang toolchain, clang-format, dev tools and test data)."""
import importlib.machinery, importlib.util, os, sys

src, cache = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
os.makedirs(cache, exist_ok=True)
loader = importlib.machinery.SourceFileLoader('install_build_deps', os.path.join(src, 'tools/install-build-deps'))
spec = importlib.util.spec_from_loader('install_build_deps', loader)
ibd = importlib.util.module_from_spec(spec)
loader.exec_module(ibd)

ibd.ROOT_DIR = cache
stub = os.path.join(cache, 'test_data_stub.py')
open(stub, 'w').write('import sys\nsys.exit(0)\n')
ibd.TEST_DATA_SCRIPT = stub
ibd.BUILD_DEPS_TOOLCHAIN_HOST = [d for d in ibd.BUILD_DEPS_TOOLCHAIN_HOST if d.target_folder == 'third_party/gn.zip']
os.chdir(cache)
sys.argv = ['install-build-deps', '--no-dev-tools']
sys.exit(ibd.Main())
