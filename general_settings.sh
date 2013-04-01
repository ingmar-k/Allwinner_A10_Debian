#!/bin/bash
# Author: Ingmar Klein (ingmar.klein@hs-augsburg.de)
# Additional part of the main script 'build_debian_system.sh', that contains all the general settings
# Created in scope of the Master project, winter semester 2012/2013 under the direction of Professor Nik Klever, at the University of Applied Sciences Augsburg.

# This program (including documentation) is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License version 3 (GPLv3; http://www.gnu.org/licenses/gpl-3.0.html )
# for more details.

###################################
##### GENERAL BUILD SETTINGS: #####
###################################

### These settings MUST be checked ###

host_os="Ubuntu" # Debian or Ubuntu (YOU NEED TO EDIT THIS!)
nameserver_addr="192.168.2.1" # "141.82.48.1" (YOU NEED TO EDIT THIS!)
output_dir_base="/home/tester/Allwinner_A10_debian_build" # where to put the files in general (YOU NEED TO EDIT THIS!) 
root_password="root"
username="tester"  # Name of user for the graphical login
user_password="tester"


### These settings are for experienced users ###

base_sys_cache_tarball="debian_sid_minbase.tgz"

std_locale="en_US.UTF-8" # initial language setting for console (alternatively for example 'en_US.UTF-8')'

locale_list="en_US.UTF-8 de_DE.UTF-8" # list of locales to enable during configuration

debian_mirror_url="http://ftp.de.debian.org/debian/" # mirror for debian

debian_repositories="main contrib non-free"

debian_target_version="sid" # The version of debian that you want to build (ATM, 'wheezy' and 'sid' are supported)

bootloader_bin_1="http://www.hs-augsburg.de/~ingmar_k/Allwinner_A10/bootloader/sunxi-spl.bin" # bootloader binary
bootloader_bin_2="http://www.hs-augsburg.de/~ingmar_k/Allwinner_A10/bootloader/u-boot.bin" # bootloader binary
bootloader_script="http://www.hs-augsburg.de/~ingmar_k/Allwinner_A10/bootloader/script.bin" # Name of the bootscript for automatically booting from sd-card

qemu_kernel_pkg="http://www.hs-augsburg.de/~ingmar_k/Allwinner_A10/kernels/vmlinuz_Ubuntu_natty_armversatile.tar.bz2" # qemu kernel file name

std_kernel_pkg="http://www.hs-augsburg.de/~ingmar_k/Allwinner_A10/kernels/3.0.62/3.0.62-hsa-1.0_1364762093.tar.bz2" # standard kernel file name
 
tar_format="bz2" # bz2(=bzip2) or gz(=gzip)

if [ "${output_dir_base:(-1):1}" = "/" ]
then
	output_dir="${output_dir_base}build_`date +%s`" # Subdirectory for each build-run, ending with the unified Unix-Timestamp (seconds passed since Jan 01 1970)
else
	output_dir="${output_dir_base}/build_`date +%s`" # Subdirectory for each build-run, ending with the unified Unix-Timestamp (seconds passed since Jan 01 1970)
fi

work_image_size_MB="4096" # size of the temporary image file, in which the installation process is carried out

output_filename="debian_rootfs_Allwinner_A10_`date +%s`" # base name of the output file (compressed rootfs)

apt_prerequisites_debian="git debootstrap binfmt-support qemu-user-static qemu qemu-kvm qemu-system parted" # packages needed for the build process on debian
apt_prerequisites_ubuntu="git debootstrap binfmt-support qemu qemu-system qemu-kvm qemu-kvm-extras-static parted" # packages needed for the build process on ubuntu

deb_add_packages="apt-utils,dialog,locales,udev,dictionaries-common,aspell" # extra packages to install via debotstrap

clean_tmp_files="yes" # delete the temporary files, when the build process is done?

create_disk="no" # create a bootable SD-card after building the rootfs?

use_cache="yes" # use or don't use caching for the apt and debootstrap processes (caching can speed things up, but it can also lead to problems)


####################################
##### SPECIFIC BUILD SETTINGS: #####
####################################


### Additional Software ###

additional_packages="rsyslog uboot-envtools uboot-mkimage file manpages man-db module-init-tools dhcp3-client netbase ifupdown iproute iputils-ping net-tools wget vim nano hdparm rsync bzip2 p7zip unrar unzip zip p7zip-full screen less usbutils psmisc strace info ethtool wireless-tools iw wpasupplicant python whois time ruby procps perl parted ftp gettext firmware-linux-free firmware-linux-nonfree firmware-realtek firmware-ralink firmware-linux firmware-brcm80211 firmware-atheros rcconf lrzsz libpam-modules util-linux" # IMPORTANT NOTE: All package names need to be seperated by a single space
additional_desktop_packages="task-lxde-desktop thunar-archive-plugin filezilla geany geany-plugins libreoffice-l10n-de iceweasel-l10n-de icedove icedove-l10n-de iceowl iceowl-l10n-de atool ark xar xarchiver e17 eterm python-edje esound wmdiskmon wmcpuload vlc vlc-plugin-esd gstreamer0.10-esd enna wmmemmon"
additional_dev_packages="git subversion build-essential autoconf automake make libtool xorg-dev xutils-dev libdrm-dev"


### ARM Mali400 graphics driver settings ###
mali_module_version="r3p0"

mali_graphics_choice="build" # copy|build|none (copy=use a precompiled, downloaded driver | build= install dev-packages and sources and try to compile the driver | none= no driver and no graphical desktop)
mali_graphics_opengl="no" # Use or do not use binary/precompiled OpenGL libraries

mali_2d_bin="http://www.hs-augsburg.de/~ingmar_k/Allwinner_A10/xserver_mali/xserver_mali.tar.bz2" # precompiled xserver driver
mali_opengl_bin="http://dl.linux-sunxi.org/mali/lib-r3p0-04rel0.tar.gz" # precompiled opengl libraries for mali

mali_xserver_2d_git="https://github.com/linux-sunxi/xf86-video-mali.git -b r3p0-04rel0" # the "-b r3p1-01rel1" specifies the branch to get
mali_2d_libdri2_git="git://github.com/robclark/libdri2.git"
mali_2d_mali_git="https://github.com/linux-sunxi/sunxi-mali.git"
mali_2d_proprietary_git="https://github.com/linux-sunxi/sunxi-mali-proprietary.git"

### Settings for compressed SWAP space in RAM ### 

use_zram="yes" # Kernel 3.x.x only!!! set if you want to use a compressed SWAP space in RAM and your Kernel version is 3.x.x (can potentionally improve performance)
zram_kernel_module_name="zram" # name of the ramzswap kernel module (could have a different name on newer kernel versions)
zram_size_B="536870912" # size of the ramzswap device in Byte (!!!)


vm_swappiness="100" # Setting for general kernel RAM swappiness: With RAMzswap and low RAM, a high number (like 100) could be good. Default in Linux mostly is 60.


### Settings for a RTC ###

i2c_hwclock="no" # say "yes" here, if you connected a RTC to your Allwinner A10 board, otherwise say "no"
i2c_hwclock_name="ds1307" # name of the hardware RTC (if one is connected)
i2c_hwclock_addr="0x68" # hardware address of the RTC (if one is connected)
rtc_kernel_module_name="rtc-ds1307" # kernel module name of the hardware RTC (if one is connected)


### Partition setting ###
# Comment: size of the rooot partition doesn't get set directly, but is computed through the following formula:
# root partition = size_of_sd_card - (size_boot_partition + size_swap_partition)
size_boot_partition="16"   # size of the boot partition, in MB (MegaByte)
size_swap_partition="512"   # size of the swap partition, in MB (MegaByte)


####################################
##### "INSTALL ONLY" SETTINGS: #####
####################################

default_rootfs_package="" # filename of the rootfs-archive
