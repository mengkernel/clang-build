#!/usr/bin/env bash

REPO_BRANCH="$1"
LLVM_NAME="CAT"
DIR="$(pwd ...)"
BOT_MSG_URL="https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage"
TG_CHAT_ID="-1001180467256"
BUILD_DATE="$(date +%Y%m%d)"
BUILD_DAY="$(date "+%B %-d, %Y")"
THREADS="$(nproc --all)"
CUSTOM_FLAGS="LLVM_PARALLEL_COMPILE_JOBS=$THREADS LLVM_PARALLEL_LINK_JOBS=$THREADS CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3"
# Select clang repository for build
case "${REPO_BRANCH}" in "clang-12") BRANCH="release/12.x" ;; "clang-13") BRANCH="release/13.x" ;; "main") BRANCH="main" ;; esac
tg_post_msg(){ curl -q -s -X POST "$BOT_MSG_URL" -d chat_id="$TG_CHAT_ID" -d "disable_web_page_preview=true" -d "parse_mode=html" -d text="$1" &> /dev/null; }
tg_post_build(){ curl --progress-bar -F document=@"$1" "$BOT_MSG_URL" -F chat_id="$TG_CHAT_ID" -F "disable_web_page_preview=true" -F "parse_mode=html" -F caption="$3" &> /dev/null; }
# Build LLVM
tg_post_msg "<b>$LLVM_NAME: Toolchain Compilation Started</b>%0A<b>Date : </b><code>$BUILD_DAY</code>"
tg_post_msg "<b>$LLVM_NAME: Building LLVM. . .</b>"
BUILD_START=$(date +"%s")
./build-llvm.py --build-stage1-only --install-stage1-only --clang-vendor "$LLVM_NAME" --branch "$BRANCH" --defines "$CUSTOM_FLAGS" --projects "clang;lld;polly;openmp" --targets "ARM;AArch64;X86" --shallow-clone | tee build.log
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
[ ! -f install/bin/clang-1* ] && { tg_post_build "build.log" "$TG_CHAT_ID" "Error Log"; exit 1; }
tg_post_msg "<b>$LLVM_NAME: LLVM Compilation Finished</b>"
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
# Build binutils
tg_post_msg "<b>$LLVM_NAME: Building Binutils. . .</b>"
BUILD_START=$(date +"%s")
./build-binutils.py --targets arm aarch64 x86_64
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
tg_post_msg "<b>$LLVM_NAME: Binutils Compilation Finished</b>"
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
rm -rf install/include install/lib/*.a install/lib/*.la
wget -q https://github.com/Diaz1401/clang/raw/main/bin/strip && chmod +x strip
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do ./strip -s "${f: : -1}"; done
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do bin="${bin: : -1}"; echo "$bin"; patchelf --set-rpath "$DIR/install/lib" "$bin"; done
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"
binutils_ver="$(ls | grep "^binutils-" | sed "s/binutils-//g")"
tg_post_msg "<b>$LLVM_NAME: Toolchain compilation Finished</b>%0A<b>Clang Version : </b><code>$clang_version</code>%0A<b>Binutils Version : </b><code>$binutils_ver</code>"
# Finishing
tg_post_msg "<b>$LLVM_NAME: Cloning clang repository. . .</b>"
./lfs.sh
git config --global user.name Diaz1401
git config --global user.email reagor8161@outlook.com
git clone "https://Diaz1401:$GH_TOKEN@github.com/Diaz1401/clang.git" --branch "$REPO_BRANCH" --single-branch
pushd clang || exit
git lfs install
rm -rf ./*
cp -rf ../install/* .
git checkout README.md .gitattributes
git add .
git commit -asm "$LLVM_NAME: Bump to $BUILD_DATE build, Clang: $clang_version, Binutils: $binutils_ver"
tg_post_msg "<b>$LLVM_NAME: Starting push to clang repository. . .</b>"
BUILD_START=$(date +"%s")
git push -f
popd || exit
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
tg_post_msg "<b>$LLVM_NAME: Toolchain pushed to <code>https://github.com/Diaz1401/clang.git</code></b>"
