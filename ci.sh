#!/usr/bin/env bash

export LLVM_NAME="kucing"
export INSTALL="${PWD}/install"
export CHAT_ID="-1001180467256"
export BUILD_DATE="$(date +%Y%m%d)"
export BUILD_DAY="$(date "+%d %B %Y")"
export BUILD_TAG="$(date +%Y%m%d-%H%M-%Z)"
export NPROC="$(nproc --all)"
export CUSTOM_FLAGS="LLVM_PARALLEL_COMPILE_JOBS=${NPROC} LLVM_PARALLEL_LINK_JOBS=${NPROC} CMAKE_C_FLAGS='-O3' CMAKE_CXX_FLAGS='-O3'"

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
  ./build-llvm.py -s \
    --build-type "Release" \
    --build-stage1-only \
    --defines "${CUSTOM_FLAGS}" \
    --install-folder "${INSTALL}" \
    --lto thin \
    --projects clang lld polly \
    --targets AArch64 X86 \
    --vendor-string "${LLVM_NAME}" |& tee -a build.log
  BUILD_END=$(date +"%s")
  DIFF=$((BUILD_END - BUILD_START))

  # Check LLVM files
  if [ -f ${INSTALL}/bin/clang ]; then
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

strip_binaries(){
  find ${INSTALL} -type f -exec file {} \; > .file-idx
  cp ${INSTALL}/bin/llvm-objcopy ./strip
  grep "not strip" .file-idx |
    tr ':' ' ' | awk '{print $1}' |
    while read -r file; do ./strip --strip-all-gnu "${file}"; done

  # clean unused files
  rm -rf strip .file-idx \
    ${INSTALL}/include \
    ${INSTALL}/lib/cmake \
    ${INSTALL}/lib/*.a \
    ${INSTALL}/lib/*.la
}

git_release(){
  CLANG_VERSION="$(${INSTALL}/bin/clang --version | head -n1 | cut -d ' ' -f4)"
  MESSAGE="Clang: ${CLANG_VERSION}-${BUILD_DATE}"
  send_info "GitHub Action : " "Release into GitHub . . ."
  send_info "Clang Version : " "${CLANG_VERSION}"
  git config --global user.name Diaz1401
  git config --global user.email reagor8161@outlook.com
  git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Diaz1401/clang.git -b main
  pushd ${INSTALL}
  tar -I'../zstd --ultra -22 -T0' -cf clang.tar.zst *
  popd
  pushd clang
  cat README |
    sed s/LLVM_VERSION/${CLANG_VERSION}-${BUILD_DATE}/g |
    sed s/SIZE/$(du -m ${INSTALL}/clang.tar.zst | cut -f1)/g > README.md
  git commit --allow-empty -as -m "${MESSAGE}"
  git push origin main
  cp ${INSTALL}/clang.tar.zst .
  hub release create -a clang.tar.zst -m "${MESSAGE}" ${BUILD_TAG}
  send_info "GitHub Action : " "Toolchain released ! ! !"
  popd
}

TOTAL_START=$(date +"%s")
send_info "Date : " "${BUILD_DAY}"
send_info "GitHub Action : " "Toolchain compilation started . . ."
build_llvm
strip_binaries
git_release
TOTAL_END=$(date +"%s")
DIFF=$((TOTAL_END - TOTAL_START))
send_info "Total CI operation : " "$((DIFF / 60))m $((DIFF % 60))"
