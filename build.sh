#!/usr/bin/env bash

#define colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
clear_color='\033[0m'

SECONDS=0
topdir="$(pwd)"
tc_dir="$topdir/toolchain"
tc_url="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/10032024/neutron-clang-10032024.tar.zst"
mkdtimg_url="https://github.com/akabul0us/mkdtimg/raw/refs/heads/static/mkdtimg"
ak3_dir="$topdir/AnyKernel3"

export KBUILD_BUILD_USER="Ikteach"
export KBUILD_BUILD_HOST="linux"

# device config

model="ginkgo"
nh_config="nethunter_defconfig"
ak3_branch="gingko"
zipname="ginkgo-nethunter-$(date '+%Y%m%d-%H%M').zip"
tarball="ginkgo-modules-$(date '+%Y%m%d-%H%M').tar"
dtbo="arch/arm64/boot/dts/xiaomi/ginkgo-trinket-overlay.dtbo"

make_options="ARCH=arm64 CC=clang AS=llvm-as CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1 DTC_EXT=$tc_dir/bin/dtc"

# detect command

if [ "$1" == "menu" ]; then
config_command="nconfig"
else
config_command="$nh_config"
fi

# safe cpu threads

threads=$(( $(nproc) / 2 ))
[ $threads -lt 1 ] && threads=1

confirm(){ printf "${green}yes${clear_color}\n"; }
deny(){ printf "${red}no${clear_color}\n"; }

printf "Checking that operating system is ${yellow}Linux${clear_color}... "
[ "$(uname -s)" == "Linux" ] && confirm || { deny; exit 1; }

printf "Checking that architecture is ${yellow}x86_64${clear_color}... "
[ "$(uname -m)" == "x86_64" ] && confirm || { deny; exit 1; }

check_installation(){
printf "Checking for ${yellow}$program${clear_color}... "
command -v $program >/dev/null 2>&1 && confirm || { deny; echo "Install $program"; exit 1; }
}

programs="git curl grep bash bison flex python3 gzip tar xz make gcc perl awk swig pkg-config zstd dtc"
for p in $programs; do
program=$p
check_installation
done

printf "${green}Updating kernel source${clear_color}\n"
git pull

printf "${green}Updating submodules${clear_color}\n"
git submodule init
git submodule update --remote

# toolchain

if [ ! -d "$tc_dir" ]; then
printf "${yellow}Downloading toolchain...${clear_color}\n"
mkdir -p $tc_dir
cd $tc_dir
curl -fsSL $tc_url | tar --zstd -xf -
fi

# mkdtimg

if ! command -v mkdtimg >/dev/null 2>&1; then
if [ ! -e "$tc_dir/bin/mkdtimg" ]; then
printf "Downloading mkdtimg...\n"
curl -o $tc_dir/bin/mkdtimg -fsSL $mkdtimg_url
chmod +x $tc_dir/bin/mkdtimg
fi
fi

# dtc wrapper

if [ ! -e "$tc_dir/bin/dtc" ]; then
cp $topdir/dtc $tc_dir/bin/dtc
chmod +x $tc_dir/bin/dtc
fi

# AnyKernel3

if [ ! -d "$ak3_dir" ]; then
printf "Cloning AnyKernel3...\n"
git clone https://github.com/akabul0us/AnyKernel3 -b $ak3_branch $ak3_dir
fi

export PATH="$tc_dir/bin:$PATH"
cd $topdir

printf "Checking for ${yellow}build artifacts${clear_color}...\n"

if (find . -name "*.o" > /dev/null); then
printf "${yellow}Artifacts found. Clean build? (y/n) "
read clean
[ "$clean" == "y" ] && make ${make_options} clean
fi

printf "Running ${green}configuration${clear_color}...\n"

if [ "$1" == "menu" ]; then
cp arch/arm64/configs/$nh_config .config
make ${make_options} nconfig
exit 0
else
make ${make_options} $nh_config
fi

printf "\nStarting ${green}compilation${clear_color} using $threads threads...\n"

make ${make_options} -j$threads

# kernel outputs

kernel_gz="$topdir/arch/arm64/boot/Image.gz"
kernel_raw="$topdir/arch/arm64/boot/Image"

if [ ! -f "$kernel_gz" ]; then
printf "${red}Build failed: Image.gz not found${clear_color}\n"
exit 1
fi

if [ ! -f "$kernel_raw" ]; then
printf "${red}Build failed: Image not found${clear_color}\n"
exit 1
fi

cd $ak3_dir

printf "Copying kernel images...\n"

cp $kernel_gz $ak3_dir
cp $kernel_raw $ak3_dir

# also keep copies in root

cp $kernel_raw $topdir/Image
cp $kernel_gz $topdir/Image.gz

if [ -f "$topdir/$dtbo" ]; then
printf "Packing dtbo.img...\n"
mkdtimg create dtbo.img $topdir/$dtbo
fi

zip -r9 ../$zipname * -x .git README.md *placeholder
printf "Kernel zip ${green}$zipname${clear_color} created\n"

# modules

moduledir="modules-$(date '+%Y%m%d-%H%M')"
cd $topdir

printf "Looking for modules... "
if (find . -name *.ko > /dev/null); then
printf "${green}found${clear_color}\n"

```
module_paths="$(find . -name *.ko)"
mkdir -p $moduledir

for m in $module_paths; do
	cp $m $moduledir
done

cd $moduledir
tar cf ../$tarball *
gzip -9 ../$tarball
cd ..

rm -rf $moduledir

printf "Modules tarball ${green}$topdir/$tarball.gz${clear_color} created\n"
```

else
printf "None found\n"
fi

printf "\nCompleted in ${green}$((SECONDS / 60)) min $((SECONDS % 60)) sec${clear_color}\n"
