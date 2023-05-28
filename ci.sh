#!/usr/bin/env bash

LLVM_NAME="kucing"
DIR="$(dirname "$(readlink -f "$0")")"
INSTALL="${DIR}/install"
BOT_MSG_URL="https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"
TG_CHAT_ID="-1001180467256"
BUILD_DATE="$(date +%Y%m%d)"
BUILD_DAY="$(date "+%d %B %Y")"
BUILD_TAG="$(date +%Y%m%d-%H%M-%Z)"
THREADS="$(nproc --all)"
CUSTOM_FLAGS="LLVM_PARALLEL_COMPILE_JOBS=${THREADS} \
LLVM_PARALLEL_LINK_JOBS=${THREADS} \
CMAKE_C_FLAGS='-O3' \
CMAKE_CXX_FLAGS='-O3'"

# Send message
tg_post_msg(){
  curl -s -X POST "${BOT_MSG_URL}" \
    -d chat_id="${TG_CHAT_ID}" \
    -d "parse_mode=html" \
    -d text="${1}" > /dev/null 2>&1
}

# Send file & message
tg_post_build(){
  curl -s -X POST "${BOT_MSG_URL}" \
    -F document=@"${1}" \
    -F chat_id="${TG_CHAT_ID}" \
    -F "parse_mode=html" \
    -F caption="${2}" > /dev/null 2>&1
}

# Build LLVM
tg_post_msg "<pre>                Date: ${BUILD_DAY}</pre><pre>       GitHub Action: Toolchain compilation started . . .</pre>"
tg_post_msg "<pre>       GitHub Action: Building LLVM . . .</pre>"
BUILD_START=$(date +"%s")
TOTAL_START=$(date +"%s")
./build-llvm.py -s \
  -i "${INSTALL}" \
  -p clang lld polly \
  -r main \
  -D "${CUSTOM_FLAGS}" \
  -t AArch64 X86 \
  --lto thin \
  --build-stage1-only \
  --build-type "Release" \
  --vendor-string "${LLVM_NAME}" | tee build.log
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))

# Check LLVM files
if [ -f install/bin/clang ]; then
  tg_post_msg "<pre>       GitHub Action: LLVM compilation finished ! ! !</pre><pre>          Time taken: $((DIFF / 60))m $((DIFF % 60))s</pre>"
else
  tg_post_msg "<pre>       GitHub Action: LLVM compilation failed ! ! !</pre>"
  tg_post_build build.log "<pre>       GitHub Action: LLVM build.log</pre>"
  exit 1
fi

# Build binutils
tg_post_msg "<pre>       GitHub Action: Building Binutils. . .</pre>"
BUILD_START=$(date +"%s")
./build-binutils.py \
  -t aarch64 x86_64 \
  -i "${INSTALL}"
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))

# Check Binutils files
if [ -f install/bin/ld ]; then
  tg_post_msg "<pre>       GitHub Action: Binutils compilation finished ! ! !</pre><pre>          Time taken: $((DIFF / 60))m $((DIFF % 60))s</pre>"
else
  tg_post_msg "<pre>       GitHub Action: Binutils compilation failed ! ! !</pre>"
  tg_post_build build.log "<pre>       GitHub Action: Binutils build.log</pre>"
  exit 1
fi

# Clean unused files
rm -rf install/include install/lib/*.a install/lib/*.la install/.gitignore

# Strip binaries & set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
find install -type f -exec file {} \; > .file-idx

cp install/bin/llvm-objcopy strip
grep "not strip" .file-idx |
  tr ':' ' ' | awk '{print $1}' |
  while read -r file; do ./strip --strip-all-gnu "${file}"; done
rm strip

grep 'ELF .* interpreter' .file-idx |
  tr ':' ' ' | awk '{print $1}' |
  while read -r file; do patchelf --set-rpath "${DIR}/install/lib" "${file}"; done
rm .file-idx

# Clone GitHub repository
tg_post_msg "<pre>       GitHub Action: Toolchain compilation Finished</pre><pre>Clang Version       : ${CLANG_VERSION}</pre><pre>Binutils Version    : ${BINUTILS_VERSION}</pre>"
git config --global user.name Diaz1401
git config --global user.email reagor8161@outlook.com
tg_post_msg "<pre>       GitHub Action: Cloning repository. . .</pre>"
git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Diaz1401/clang.git -b main --single-branch
cd clang; rm -rf *; cp -rf ../install/* .

# Generate archive
tg_post_msg "<pre>       GitHub Action: Generate release archive. . .</pre>"
cp ../zstd .; tar --use-compress-program='./zstd -12' -cf clang.tar.zst aarch64-linux-gnu bin lib share

# Push to GitHub repository
CLANG_VERSION="$(install/bin/clang --version | head -n1 | cut -d ' ' -f4)"
BINUTILS_VERSION="$(install/bin/ld --version | head -n1 | cut -d ' ' -f5)"
git checkout README
cat README |
  sed s/LLVM_VERSION/$(echo ${CLANG_VERSION}-${BUILD_DATE})/g |
  sed s/BINUTILS_VERSION/${BINUTILS_VERSION}/g |
  sed s/SIZE/$(du -m clang.tar.zst)/g > README.md
git commit --allow-empty -as \
  -m "Clang: ${CLANG_VERSION}-${BUILD_DATE}, Binutils: ${BINUTILS_VERSION}" --
tg_post_msg "<pre>       GitHub Action: Starting release to repository. . .</pre>"
git push origin main
hub release create -a clang.tar.zst -m "Clang-${CLANG_VERSION}-${BUILD_DATE}" ${BUILD_TAG}
tg_post_msg "<pre>       GitHub Action: Toolchain released to https://github.com/Diaz1401/clang/releases/latest</pre>"
TOTAL_END=$(date +"%s")
DIFF=$((TOTAL_END - TOTAL_START))
tg_post_msg "<pre>  Total CI operation: $((DIFF / 60))m $((DIFF % 60))</pre>"
