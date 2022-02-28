#!/usr/bin/env bash

LLVM_NAME="kucing"
DIR="$(pwd ...)"
BOT_MSG_URL="https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage"
TG_CHAT_ID="-1001180467256"
BUILD_DATE="$(date +%Y%m%d)"
BUILD_DAY="$(date "+%B %-d, %Y")"
THREADS="$(nproc --all)"
CUSTOM_FLAGS="LLVM_PARALLEL_COMPILE_JOBS=$THREADS LLVM_PARALLEL_LINK_JOBS=$THREADS CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3 LLVM_INCLUDE_BENCHMARKS=OFF LLVM_INCLUDE_EXAMPLES=OFF LLVM_INCLUDE_TESTS=OFF LLVM_INCLUDE_TOOLS=OFF LLVM_INCLUDE_RUNTIMES=OFF LLVM_INCLUDE_DOCS=OFF LLVM_BUILD_TOOLS=OFF LLVM_BUILD_RUNTIME=OFF LLVM_BUILD_UTILS=OFF LLVM_BUILD_TESTS=OFF LLVM_BUILD_EXAMPLES=OFF LLVM_ENABLE_BACKTRACES=OFF LLVM_ENABLE_OCAMLDOC=OFF LLVM_OPTIMIZED_TABLEGEN=ON CLANG_ENABLE_ARCMT=OFF CLANG_ENABLE_STATIC_ANALYZER=OFF CLANG_BUILD_TOOLS=OFF CLANG_INCLUDE_TESTS=OFF CLANG_INCLUDE_DOCS=OFF CLANG_BUILD_EXAMPLES=OFF"
tg_post_msg(){ curl -q -s -X POST "$BOT_MSG_URL" -d chat_id="$TG_CHAT_ID" -d "disable_web_page_preview=true" -d "parse_mode=html" -d text="$1" &> /dev/null; }
tg_post_build(){ curl --progress-bar -F document=@"$1" "$BOT_MSG_URL" -F chat_id="$TG_CHAT_ID" -F "disable_web_page_preview=true" -F "parse_mode=html" -F caption="$3" &> /dev/null; }
# Build LLVM
tg_post_msg "<b>$LLVM_NAME: Toolchain Compilation Started</b>%0A<b>Date : </b><code>$BUILD_DAY</code>"
tg_post_msg "<b>$LLVM_NAME: Building LLVM. . .</b>"
BUILD_START=$(date +"%s")
TOTAL_START=$(date +"%s")
./build-llvm.py --build-stage1-only --install-stage1-only --clang-vendor "$LLVM_NAME" --branch release/14.x --defines "$CUSTOM_FLAGS" --projects "clang;lld" --targets "AArch64;X86" --shallow-clone --build-type "MinSizeRel" | tee build.log
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
[ ! -f install/bin/clang-1* ] && { tg_post_build "build.log" "$TG_CHAT_ID" "Error Log"; exit 1; }
tg_post_msg "<b>$LLVM_NAME: LLVM Compilation Finished</b>"
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
# Build binutils
tg_post_msg "<b>$LLVM_NAME: Building Binutils. . .</b>"
BUILD_START=$(date +"%s")
./build-binutils.py --targets aarch64 x86_64
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
tg_post_msg "<b>$LLVM_NAME: Binutils Compilation Finished</b>"
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
rm -rf install/include install/lib/*.a install/lib/*.la install/.gitignore
# Strip binaries
cp install/bin/llvm-objcopy strip
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do ./strip --strip-all-gnu "${f: : -1}"; done
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do bin="${bin: : -1}"; echo "$bin"; patchelf --set-rpath "$DIR/install/lib" "$bin"; done
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"
binutils_ver="$(ls | grep "^binutils-" | sed "s/binutils-//g")"
tg_post_msg "<b>$LLVM_NAME: Building ZSTD. . .</b>"
BUILD_START=$(date +"%s")
git clone https://github.com/facebook/zstd.git -b v1.5.2 --depth 1 --single-branch
cd zstd; CC=gcc-11 make -j$(nproc); cd ..
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
tg_post_msg "<b>$LLVM_NAME: ZSTD Compilation Finished</b>"
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
tg_post_msg "<b>$LLVM_NAME: Toolchain compilation Finished</b>%0A<b>Clang Version : </b><code>$clang_version</code>%0A<b>Binutils Version : </b><code>$binutils_ver</code>"
# Push to GitHub repository
git config --global user.name Diaz1401
git config --global user.email reagor8161@outlook.com
tg_post_msg "<b>$LLVM_NAME: Cloning repository. . .</b>"
git clone https://Diaz1401:$GITHUB_TOKEN@github.com/Diaz1401/clang.git -b main --single-branch
cd clang; rm -rf *; cp -rf ../install/* .
# Generate archive
tg_post_msg "<b>$LLVM_NAME: Generate release archive. . .</b>"
cp ../zstd/programs/zstd .; time tar --use-compress-program='./zstd --ultra -22 -T0' -cf clang.tar.zst aarch64-linux-gnu bin lib share
tar --use-compress-program='./zstd --ultra -22 -T0' -cf zstd-v1.5.2.tar.zst zstd
md5sum clang.tar.zst > md5sum.txt
echo "$BUILD_DATE build, Clang: $clang_version, Binutils: $binutils_ver" > version.txt
git checkout README.md
git add md5sum.txt version.txt
git commit -asm "Clang: $clang_version-$BUILD_DATE, Binutils: $binutils_ver"
tg_post_msg "<b>$LLVM_NAME: Starting release to repository. . .</b>"
git push origin main
hub release create -a zstd-v1.5.2.tar.zst -a clang.tar.zst -m "Clang-$clang_version-$BUILD_DATE" $BUILD_DATE
tg_post_msg "<b>$LLVM_NAME: Toolchain released to <code>https://github.com/Diaz1401/clang/releases/latest</code></b>"
TOTAL_END=$(date +"%s")
DIFF=$((TOTAL_END - TOTAL_START))
tg_post_msg "<b>Total CI operation: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
