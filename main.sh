#!/usr/bin/env sh

set -e

# Changable Data
# ------------------------------------------------------------
FULL_BUILD="true"

# Kernel
KERNEL_NAME="cazkernel"
KERNEL_GIT="https://github.com/PixelOS-Devices/kernel_xiaomi_sm6150.git"
KERNEL_BRANCH="fifteen"
KERNEL_TYPE="vantom"

# KernelSU-Next
KERNELSU_REPO="rifsxd/KernelSU-Next"
KERNELSU_BRANCH="next-susfs"
KSU_ENABLED="true"
KSU_TARGET="next-susfs"

# SUSFS
SUSFS_GIT="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_BRANCH="kernel-4.14"
SUSFS_ENABLED="true"

# Anykernel3
ANYKERNEL3_GIT="https://github.com/SchweGELBin/AnyKernel3_davinci.git"
ANYKERNEL3_BRANCH="master"

# Build
DEVICE_CODE="davinci"
DEVICE_ARCH="arch/arm64"

# Clang
CLANG_REPO="ZyCromerZ/Clang"

# ------------------------------------------------------------

# Highlight
msg() {
	echo
	echo -e "\e[1;33m$*\e[0m"
	echo
}

# Check if there is any whitespace in the PATH variable
if echo "$PATH" | grep -q '[[:space:]]'; then
    echo "Error: The PATH environment variable contains whitespace."
    exit 1
fi

# Input Variables
if [[ $1 == "KSU" ]]; then
    KSU_ENABLED="true"
elif [[ $1 == "NonKSU" ]]; then
    KSU_ENABLED="false"
fi

if [[ $2 == *.git ]]; then
    KERNEL_GIT=$2
fi

if [[ $3 ]]; then
    KERNEL_BRANCH=$3
fi

if [[ $4 ]]; then
    KERNEL_TYPE=$4
fi


if [[ $KERNEL_TYPE == "vantom" ]]; then
    DEVICE_DEFCONFIG="davinci_defconfig"
    COMMON_DEFCONFIG=""
elif [[ $KERNEL_TYPE == "perf" ]]; then
    DEVICE_DEFCONFIG="vendor/davinci.config"
    COMMON_DEFCONFIG="vendor/sdmsteppe-perf_defconfig"
else
    DEVICE_DEFCONFIG="davinci_defconfig"
    COMMON_DEFCONFIG=""
fi

msg "Variables"
echo "KSU_ENABLED: $KSU_ENABLED"
echo "SUSFS_ENABLED: $SUSFS_ENABLED"
echo "KERNEL_GIT: $KERNEL_GIT"
echo "KERNEL_BRANCH: $KERNEL_BRANCH"
echo "DEVICE_DEFCONFIG: $DEVICE_DEFCONFIG"
echo "COMMON_DEFCONFIG: $COMMON_DEFCONFIG"
echo "FULL_BUILD: $FULL_BUILD"

# Set variables
WORKDIR="$(pwd)"

if [[ $FULL_BUILD == "true" ]]; then
    rm -rf $WORKDIR/$KERNEL_NAME
    rm -rf $WORKDIR/Clang
    rm -rf $WORKDIR/Anykernel3
    rm -rf $WORKDIR/out   
fi

CLANG_DLINK="$(curl -s https://api.github.com/repos/$CLANG_REPO/releases/latest\
| grep -wo "https.*" | grep Clang-.*.tar.gz | sed 's/.$//')"
CLANG_DIR="$WORKDIR/Clang/bin"

KERNEL_REPO="${KERNEL_GIT::-4}/"
KERNEL_SOURCE="${KERNEL_REPO::-1}/tree/$KERNEL_BRANCH"
KERNEL_DIR="$WORKDIR/$KERNEL_NAME"

KERNELSU_SOURCE="https://github.com/$KERNELSU_REPO"
CLANG_SOURCE="https://github.com/$CLANG_REPO"
README="https://github.com/SchweGELBin/kernel_milk_davinci/blob/master/README.md"

DEVICE_DEFCONFIG_FILE="$KERNEL_DIR/$DEVICE_ARCH/configs/$DEVICE_DEFCONFIG"
IMAGE="$KERNEL_DIR/out/$DEVICE_ARCH/boot/Image.gz"
DTB="$KERNEL_DIR/out/$DEVICE_ARCH/boot/dtb.img"
DTBO="$KERNEL_DIR/out/$DEVICE_ARCH/boot/dtbo.img"

export KBUILD_BUILD_USER=SchweGELBin
export KBUILD_BUILD_HOST=GitHubCI

cd $WORKDIR

# Setup
msg "Setup"

if [ ! -d "Clang" ]; then
    msg "Clang"
    mkdir -p Clang
    aria2c -s16 -x16 -k1M $CLANG_DLINK -o Clang.tar.gz
    tar -C Clang/ -zxvf Clang.tar.gz
    rm -rf Clang.tar.gz
fi

CLANG_VERSION="$($CLANG_DIR/clang --version | head -n 1 | cut -f1 -d "(" | sed 's/.$//')"
CLANG_VERSION=${CLANG_VERSION::-3} # May get removed later
LLD_VERSION="$($CLANG_DIR/ld.lld --version | head -n 1 | cut -f1 -d "(" | sed 's/.$//')"

if [ ! -d "$KERNEL_DIR" ]; then
    msg "Kernel"
    git clone --depth=1 $KERNEL_GIT -b $KERNEL_BRANCH $KERNEL_DIR

    msg "Applying Patches"
    cd $KERNEL_DIR
    git apply $WORKDIR/kernel.patch
    cd $WORKDIR
fi

KERNEL_VERSION=$(cat $KERNEL_DIR/Makefile | grep -w "VERSION =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "PATCHLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "SUBLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "EXTRAVERSION =" | cut -d '=' -f 2 | cut -b 2-)

[ ${KERNEL_VERSION: -1} = "." ] && KERNEL_VERSION=${KERNEL_VERSION::-1}
msg "Kernel Version: $KERNEL_VERSION"

TITLE=$KERNEL_NAME-$KERNEL_VERSION

cd $KERNEL_DIR

if [[ $KSU_ENABLED == "true" ]]; then
    msg "KernelSU-Next"

    if [ ! -d "$KERNEL_DIR/KernelSU-Next" ]; then
        curl -LSs "https://raw.githubusercontent.com/$KERNELSU_REPO/$KERNELSU_BRANCH/kernel/setup.sh" | bash -s $KSU_TARGET

        echo "CONFIG_KPROBES=y" >> $DEVICE_DEFCONFIG_FILE
        echo "CONFIG_HAVE_KPROBES=y" >> $DEVICE_DEFCONFIG_FILE
        echo "CONFIG_KPROBE_EVENTS=y" >> $DEVICE_DEFCONFIG_FILE
    fi

    KSU_GIT_VERSION=$(cd KernelSU-Next && git rev-list --count HEAD)
    KERNELSU_VERSION=$(($KSU_GIT_VERSION + 10200))
    msg "KernelSU Version: $KERNELSU_VERSION"

    TITLE=$TITLE-$KERNELSU_VERSION
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNELSU_VERSION-$KERNEL_NAME\"/" $DEVICE_DEFCONFIG_FILE
else
    echo "KernelSU Disabled"
    KERNELSU_VERSION="Disabled"
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNEL_NAME\"/" $DEVICE_DEFCONFIG_FILE
fi


if [[ $SUSFS_ENABLED == "true" ]]; then
    msg "SUSFS"

    if [ ! -d "$KERNEL_DIR/susfs4ksu" ]; then
        git clone --depth=1 $SUSFS_GIT -b $SUSFS_BRANCH
        
        cp $KERNEL_DIR/susfs4ksu/kernel_patches/fs/* $KERNEL_DIR/fs/
        cp $KERNEL_DIR/susfs4ksu/kernel_patches/include/linux/* $KERNEL_DIR/include/linux/

        cd $KERNEL_DIR
        git apply $WORKDIR/susfs.patch

    fi    
fi

# Build
msg "Build"

args="PATH=$CLANG_DIR:$PATH \
ARCH=arm64 \
SUBARCH=arm64 \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
CC=clang \
NM=llvm-nm \
CXX=clang++ \
AR=llvm-ar \
LD=ld.lld \
STRIP=llvm-strip \
OBJDUMP=llvm-objdump \
OBJSIZE=llvm-size \
READELF=llvm-readelf \
HOSTAR=llvm-ar \
HOSTLD=ld.lld \
HOSTCC=clang \
HOSTCXX=clang++ \
LLVM=1 \
LLVM_IAS=1"

if [[ $FULL_BUILD == "true" ]]; then
    rm -rf out
fi

if [[ ! $COMMON_DEFCONFIG == "" ]]; then
    make O=out $args "$COMMON_DEFCONFIG"
fi    
make O=out $args "$DEVICE_DEFCONFIG"

make O=out $args kernelversion
make O=out $args -j"$(nproc --all)"
msg "Kernel version: $KERNEL_VERSION"

# Package
msg "Package"
cd $WORKDIR
if [ ! -d "$WORKDIR/Anykernel3" ]; then
    git clone --depth=1 $ANYKERNEL3_GIT -b $ANYKERNEL3_BRANCH $WORKDIR/Anykernel3
fi
cd $WORKDIR/Anykernel3
cp $IMAGE .
cp $DTB $WORKDIR/Anykernel3/dtb
cp $DTBO .

# Archive
mkdir -p $WORKDIR/out
if [[ $KSU_ENABLED == "true" ]]; then
  ZIP_NAME="$KERNEL_NAME-KSU.zip"
else
  ZIP_NAME="$KERNEL_NAME-NonKSU.zip"
fi
TIME=$(TZ='Europe/Berlin' date +"%Y-%m-%d %H:%M:%S")
find ./ * -exec touch -m -d "$TIME" {} \;
zip -r9 $ZIP_NAME *
cp *.zip $WORKDIR/out

# Release Files
cd $WORKDIR/out
msg "Release Files"
echo "
## [$KERNEL_NAME]($README)
- **Time**: $TIME # CET

- **Codename**: $DEVICE_CODE
- **Kernel Type**: $KERNEL_TYPE

<br>

- **[Kernel]($KERNEL_SOURCE) Version**: $KERNEL_VERSION
- **[KernelSU-Next]($KERNELSU_SOURCE) Version**: $KERNELSU_VERSION

<br>

- **[CLANG]($CLANG_SOURCE) Version**: $CLANG_VERSION
- **LLD Version**: $LLD_VERSION
" > bodyFile.md
echo "$TITLE" > name.txt
#echo "$KERNEL_NAME" > name.txt

# Finish
msg "Done"
