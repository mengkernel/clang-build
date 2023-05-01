#!/usr/bin/env bash

LLVM_NAME="kucing"
DIR="$(dirname "$(readlink -f "$0")")"
INSTALL="${DIR}/install"
BOT_MSG_URL="https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"
TG_CHAT_ID="-1001180467256"
BUILD_DATE="$(date +%Y%m%d)"
BUILD_DAY="$(date "+%B %-d, %Y")"
THREADS="$(nproc --all)"
CUSTOM_FLAGS="LLVM_PARALLEL_COMPILE_JOBS=${THREADS} \
LLVM_PARALLEL_LINK_JOBS=${THREADS} \
CMAKE_C_FLAGS='-O3' \
CMAKE_CXX_FLAGS='-O3'"

# Send message
tg_post_msg(){
    curl "${BOT_MSG_URL}" \
        -d chat_id="${TG_CHAT_ID}" \
        -d "parse_mode=html" \
        -d text="${1}" > /dev/null 2>&1
}

# Send file & message
tg_post_build(){
    curl "${BOT_MSG_URL}" \
        -F document=@"${1}" \
        -F chat_id="${TG_CHAT_ID}" \
        -F "parse_mode=html" \
        -F caption="${2}" > /dev/null 2>&1
}

# Build LLVM
tg_post_msg "<b>${LLVM_NAME}: Toolchain Compilation Started</b>%0A<b>Date : </b><code>${BUILD_DAY}</code>"
tg_post_msg "<b>${LLVM_NAME}: Building LLVM. . .</b>"
BUILD_START=$(date +"%s")
TOTAL_START=$(date +"%s")
./build-llvm.py -s \
    -i "${INSTALL}" \
    -p clang lld polly \
    -r llvmorg-16.0.2 \
    -D "${CUSTOM_FLAGS}" \
    -t AArch64 X86 \
    --build-stage1-only \
    --build-type "Release" \
    --vendor-string "${LLVM_NAME}" | tee build.log
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
tg_post_msg "<b>${LLVM_NAME}: LLVM Compilation Finished</b>"
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"

# Check files
[ ! -f install/bin/clang-* ] && { tg_post_build "build.log" "Error Log"; exit 1; }

# Build binutils
tg_post_msg "<b>${LLVM_NAME}: Building Binutils. . .</b>"
BUILD_START=$(date +"%s")
./build-binutils.py \
    -t aarch64 x86_64 \
    -i "${INSTALL}"
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
tg_post_msg "<b>${LLVM_NAME}: Binutils Compilation Finished</b>"
tg_post_msg "<b>Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"

# Clean unused files
rm -rf install/include install/lib/*.a install/lib/*.la install/.gitignore

# Strip binaries
cp install/bin/llvm-objcopy strip
for f in $(find install -type f -exec file {} \; \
    | grep 'not stripped' \
    | awk '{print $1}'); do
        ./strip --strip-all-gnu "${f: : -1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; \
    | grep 'ELF .* interpreter' \
    | awk '{print $1}'); do
        # Remove last character from file output (':')
        bin="${bin: : -1}"
        echo "${bin}"
        patchelf --set-rpath "${DIR}/install/lib" "${bin}"
done

# Clone GitHub repository
CLANG_VERSION="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"
BINUTILS_VERSION="$(ls | grep "^binutils-" | sed "s/binutils-//g")"
tg_post_msg "<b>${LLVM_NAME}: Toolchain compilation Finished</b>%0A<b>Clang Version : </b><code>${CLANG_VERSION}</code>%0A<b>Binutils Version : </b><code>${BINUTILS_VERSION}</code>"
git config --global user.name Diaz1401
git config --global user.email reagor8161@outlook.com
tg_post_msg "<b>${LLVM_NAME}: Cloning repository. . .</b>"
git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Diaz1401/clang.git -b main --single-branch
cd clang; rm -rf *; cp -rf ../install/* .

# Generate archive
tg_post_msg "<b>${LLVM_NAME}: Generate release archive. . .</b>"
cp ../zstd .; time tar --use-compress-program='./zstd --ultra -22 -T0' -cf clang.tar.zst aarch64-linux-gnu bin lib share

# Push to GitHub repository
md5sum clang.tar.zst > md5sum.txt
echo "${BUILD_DATE} build, Clang: ${CLANG_VERSION}, Binutils: ${BINUTILS_VERSION}" > version.txt
git checkout README.md
git add md5sum.txt version.txt
git commit -asm "Clang: ${CLANG_VERSION}-${BUILD_DATE}, Binutils: ${BINUTILS_VERSION}"
tg_post_msg "<b>${LLVM_NAME}: Starting release to repository. . .</b>"
git push origin main
hub release create -a clang.tar.zst -m "Clang-${CLANG_VERSION}-${BUILD_DATE}" ${BUILD_DATE}
tg_post_msg "<b>${LLVM_NAME}: Toolchain released to <code>https://github.com/Diaz1401/clang/releases/latest</code></b>"
TOTAL_END=$(date +"%s")
DIFF=$((TOTAL_END - TOTAL_START))
tg_post_msg "<b>Total CI operation: <code>$((DIFF / 60))m $((DIFF % 60))s</code></b>"
