#!/usr/bin/env bash

export LLVM_NAME="kucing"
export INSTALL="${PWD}/install"
export CHAT_ID="-1001180467256"
export BUILD_DATE="$(date +%Y%m%d)"
export BUILD_DAY="$(date "+%d %B %Y")"
export BUILD_TAG="$(date +%Y%m%d-%H%M-%Z)"
export NPROC="$(nproc --all)"
export CUSTOM_FLAGS="
  LLVM_PARALLEL_COMPILE_JOBS=${NPROC} 
  LLVM_PARALLEL_LINK_JOBS=${NPROC}
  CMAKE_C_FLAGS='-O3 -ffunction-sections -fdata-sections -fno-plt -fmerge-all-constants -fomit-frame-pointer -funroll-loops -falign-functions=64 -march=haswell -mtune=haswell -mllvm -polly -mllvm -polly-position=early -mllvm -polly-vectorizer=stripmine -mllvm -polly-run-dce'
  CMAKE_CXX_FLAGS='-O3 -ffunction-sections -fdata-sections -fno-plt -fmerge-all-constants -fomit-frame-pointer -funroll-loops -falign-functions=64 -march=haswell -mtune=haswell -mllvm -polly -mllvm -polly-position=early -mllvm -polly-vectorizer=stripmine -mllvm -polly-run-dce'
  CMAKE_ASM_FLAGS='-O3 -ffunction-sections -fdata-sections -fno-plt -fmerge-all-constants -fomit-frame-pointer -funroll-loops -falign-functions=64 -march=haswell -mtune=haswell -mllvm -polly -mllvm -polly-position=early -mllvm -polly-vectorizer=stripmine -mllvm -polly-run-dce'
  CMAKE_ASM_FLAGS='-O3 -ffunction-sections -fdata-sections -fno-plt -fmerge-all-constants -fomit-frame-pointer -funroll-loops -falign-functions=64 -march=haswell -mtune=haswell -mllvm -polly -mllvm -polly-position=early -mllvm -polly-vectorizer=stripmine -mllvm -polly-run-dce'
  CMAKE_EXE_LINKER_FLAGS='-Wl,-O3,--lto-O3,--gc-sections,--strip-debug'
  CMAKE_MODULE_LINKER_FLAGS='-Wl,-O3,--lto-O3,--gc-sections,--strip-debug'
  CMAKE_SHARED_LINKER_FLAGS='-Wl,-O3,--lto-O3,--gc-sections,--strip-debug'
  CMAKE_STATIC_LINKER_FLAGS='-Wl,-O3,--lto-O3,--gc-sections,--strip-debug'
  "

for ARGS in $@; do
  case $ARGS in
    final)
      export FINAL=true
      ;;
    release)
      export RELEASE=true
      ;;
  esac
done

send_info(){
  curl -s -X POST https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage \
    -d chat_id="${CHAT_ID}" \
    -d "parse_mode=html" \
    -d text="<b>${1}</b><code>${2}</code>" > /dev/null 2>&1
}

send_file(){
  curl -s -X POST https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument \
    -F document=@"${2}" \
    -F chat_id="${CHAT_ID}" \
    -F "parse_mode=html" \
    -F caption="${1}" > /dev/null 2>&1
}

build_llvm(){
  send_info "GitHub Action : " "Building LLVM . . ."
  BUILD_START=$(date +"%s")
  if [ "$FINAL" == "true" ]; then
    ADD="--final"
  fi
  if [ "$RELEASE" == "true" ]; then
    ADD="${ADD} --ref llvmorg-18.1.7"
  fi
  ./build-llvm.py ${ADD} \
    --build-type "Release" \
    --build-stage1-only \
    --defines "${CUSTOM_FLAGS}" \
    --install-folder "${INSTALL}" \
    --lto thin \
    --pgo llvm \
    --bolt \
    --assertions \
    --projects clang lld polly \
    --shallow-clone \
    --targets AArch64 X86 \
    --no-update \
    --vendor-string "${LLVM_NAME}" |& tee -a build.log
  BUILD_END=$(date +"%s")
  DIFF=$((BUILD_END - BUILD_START))

  # Check LLVM files
  if [ -f ${INSTALL}/bin/clang ] || [ -f ${PWD}/build/llvm/instrumented/profdata.prof ]; then
    send_info "GitHub Action : " "LLVM compilation finished ! ! !"
    send_info "Time taken : " "$((DIFF / 60))m $((DIFF % 60))s"
  else
    send_info "GitHub Action : " "LLVM compilation failed ! ! !"
    send_file "LLVM build.log" ./build.log
    exit 1
  fi
}

build_binutils(){
  send_info "GitHub Action : " "Building Binutils. . ."
  BUILD_START=$(date +"%s")
  ./build-binutils.py \
    -t aarch64 x86_64 \
    -i "${INSTALL}" | tee -a build.log
  BUILD_END=$(date +"%s")
  DIFF=$((BUILD_END - BUILD_START))

  # Check Binutils files
  if [ -f ${INSTALL}/bin/ld ]; then
    send_info "GitHub Action : " "Binutils compilation finished ! ! !"
    send_info "Time taken : " "$((DIFF / 60))m $((DIFF % 60))s"
  else
    send_info "GitHub Action : " "Binutils compilation failed ! ! !"
    send_file "Binutils build.log" ./build.log
    exit 1
  fi
}

build_zstd(){
  git clone https://github.com/facebook/zstd -b v1.5.6 --depth=1; cd zstd
  make -j${NPROC} zstd
  cd ..
}

strip_binaries(){
  find ${INSTALL} -type f -exec file {} \; > .file-idx
  cp ${INSTALL}/bin/llvm-objcopy ./strip
  grep "not strip" .file-idx |
    tr ':' ' ' | awk '{print $1}' |
    while read -r file; do ./strip --strip-all-gnu "${file}"; done

  # clean unused files
  rm -rf strip .file-idx \
    ${INSTALL}/include \
    ${INSTALL}/lib/cmake
  find ${INSTALL} -type f -name *.a -delete
  find ${INSTALL} -type f -name *.la -delete
}

git_release(){
  build_zstd
  CLANG_VERSION="$(${INSTALL}/bin/clang --version | head -n1 | cut -d ' ' -f4)"
  MESSAGE="Clang: ${CLANG_VERSION}-${BUILD_DATE}"
  send_info "GitHub Action : " "Release into GitHub . . ."
  send_info "Clang Version : " "${CLANG_VERSION}"
  cd ${INSTALL}
  tar -I'../zstd/zstd -8 -T8' -cf clang.tar.zst *
  cd ..
  git config --global user.name github-actions[bot]
  git config --global user.email github-actions[bot]@users.noreply.github.com
  if [ "${RELEASE}" == "true" ]; then
    git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Diaz1401/clang-stable.git clang -b main
  else
    git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Mengkernel/clang.git clang -b main
  fi
  cd clang
  cat README |
    sed s/LLVM_VERSION/${CLANG_VERSION}-${BUILD_DATE}/g |
    sed s/SIZE/$(du -m ${INSTALL}/clang.tar.zst | cut -f1)/g > README.md
  git commit --allow-empty -as -m "${MESSAGE}"
  git push origin main
  cp ${INSTALL}/clang.tar.zst .
  hub release create -a clang.tar.zst -m "${MESSAGE}" ${BUILD_TAG}
  send_info "GitHub Action : " "Toolchain released ! ! !"
  cd ..
}

TOTAL_START=$(date +"%s")
send_info "Date : " "${BUILD_DAY}"
send_info "GitHub Action : " "Toolchain compilation started . . ."
build_llvm
if [ "$FINAL" == "true" ]; then
  strip_binaries
  git_release
fi
TOTAL_END=$(date +"%s")
DIFF=$((TOTAL_END - TOTAL_START))
send_info "Total CI operation : " "$((DIFF / 60))m $((DIFF % 60))"
