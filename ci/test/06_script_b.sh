#!/usr/bin/env bash
#
# Copyright (c) 2018-2022 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

export LC_ALL=C.UTF-8

set -ex

if [[ $HOST = *-mingw32 ]]; then
  # Generate all binaries, so that they can be wrapped
  make "$MAKEJOBS" -C src/secp256k1 VERBOSE=1
  make "$MAKEJOBS" -C src minisketch/test.exe VERBOSE=1
  "${BASE_ROOT_DIR}/ci/test/wrap-wine.sh"
fi

if [ -n "$QEMU_USER_CMD" ]; then
  # Generate all binaries, so that they can be wrapped
  make "$MAKEJOBS" -C src/secp256k1 VERBOSE=1
  make "$MAKEJOBS" -C src minisketch/test VERBOSE=1
  "${BASE_ROOT_DIR}/ci/test/wrap-qemu.sh"
fi

if [ -n "$USE_VALGRIND" ]; then
  "${BASE_ROOT_DIR}/ci/test/wrap-valgrind.sh"
fi

if [ "$RUN_UNIT_TESTS" = "true" ]; then
  bash -c "${TEST_RUNNER_ENV} DIR_UNIT_TEST_DATA=${DIR_UNIT_TEST_DATA} LD_LIBRARY_PATH=${DEPENDS_DIR}/${HOST}/lib make $MAKEJOBS check VERBOSE=1"
fi

if [ "$RUN_UNIT_TESTS_SEQUENTIAL" = "true" ]; then
  bash -c "${TEST_RUNNER_ENV} DIR_UNIT_TEST_DATA=${DIR_UNIT_TEST_DATA} LD_LIBRARY_PATH=${DEPENDS_DIR}/${HOST}/lib ${BASE_OUTDIR}/bin/test_bitcoin --catch_system_errors=no -l test_suite"
fi

if [ "$RUN_FUNCTIONAL_TESTS" = "true" ]; then
  bash -c "LD_LIBRARY_PATH=${DEPENDS_DIR}/${HOST}/lib ${TEST_RUNNER_ENV} test/functional/test_runner.py --ci $MAKEJOBS --tmpdirprefix ${BASE_SCRATCH_DIR}/test_runner/ --ansi --combinedlogslen=99999999 --timeout-factor=${TEST_RUNNER_TIMEOUT_FACTOR} ${TEST_RUNNER_EXTRA} --quiet --failfast"
fi

if [ "${RUN_TIDY}" = "true" ]; then
  set -eo pipefail
  cd "${BASE_BUILD_DIR}/bitcoin-$HOST/src/"
  ( run-clang-tidy-16 -quiet "${MAKEJOBS}" ) | grep -C5 "error"
  cd "${BASE_BUILD_DIR}/bitcoin-$HOST/"
  python3 "${DIR_IWYU}/include-what-you-use/iwyu_tool.py" \
           src/common/args.cpp \
           src/common/config.cpp \
           src/common/init.cpp \
           src/common/url.cpp \
           src/compat \
           src/dbwrapper.cpp \
           src/init \
           src/kernel \
           src/node/chainstate.cpp \
           src/node/chainstatemanager_args.cpp \
           src/node/mempool_args.cpp \
           src/node/minisketchwrapper.cpp \
           src/node/utxo_snapshot.cpp \
           src/node/validation_cache_args.cpp \
           src/policy/feerate.cpp \
           src/policy/packages.cpp \
           src/policy/settings.cpp \
           src/primitives/transaction.cpp \
           src/random.cpp \
           src/rpc/fees.cpp \
           src/rpc/signmessage.cpp \
           src/test/fuzz/string.cpp \
           src/test/fuzz/txorphan.cpp \
           src/test/fuzz/util \
           src/test/util/coins.cpp \
           src/uint256.cpp \
           src/util/bip32.cpp \
           src/util/bytevectorhash.cpp \
           src/util/check.cpp \
           src/util/error.cpp \
           src/util/exception.cpp \
           src/util/getuniquepath.cpp \
           src/util/hasher.cpp \
           src/util/message.cpp \
           src/util/moneystr.cpp \
           src/util/serfloat.cpp \
           src/util/spanparsing.cpp \
           src/util/strencodings.cpp \
           src/util/string.cpp \
           src/util/syserror.cpp \
           src/util/threadinterrupt.cpp \
           src/zmq \
           -p . "${MAKEJOBS}" \
           -- -Xiwyu --cxx17ns -Xiwyu --mapping_file="${BASE_BUILD_DIR}/bitcoin-$HOST/contrib/devtools/iwyu/bitcoin.core.imp" \
           2>&1 | tee /tmp/iwyu_ci.out
  cd "${BASE_ROOT_DIR}/src"
  python3 "${DIR_IWYU}/include-what-you-use/fix_includes.py" --nosafe_headers < /tmp/iwyu_ci.out
  git --no-pager diff
fi

if [ "$RUN_SECURITY_TESTS" = "true" ]; then
  make test-security-check
fi

if [ "$RUN_FUZZ_TESTS" = "true" ]; then
  bash -c "LD_LIBRARY_PATH=${DEPENDS_DIR}/${HOST}/lib test/fuzz/test_runner.py ${FUZZ_TESTS_CONFIG} $MAKEJOBS -l DEBUG ${DIR_FUZZ_IN}"
fi
