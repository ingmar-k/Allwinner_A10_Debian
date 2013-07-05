#!/bin/bash
# Bash script that creates a Debian rootfs or even a complete SD memory card for a Allwinner A10 board
# Should run on current Debian or Ubuntu versions
# Author: Ingmar Klein (ingmar.klein@hs-augsburg.de)
# Created in scope of the Master project, winter semester 2012/2013 under the direction of Professor Nik Klever, at the University of Applied Sciences Augsburg.


# This program (including documentation) is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License version 3 (GPLv3; http://www.gnu.org/licenses/gpl-3.0.html ) for more details.


#####################################
##### MAIN Highlevel Functions: #####
#####################################


### Preparation ###

prep_output()
{
	
if [ ! -d ${output_dir_base}/cache ]
then
	mkdir -p ${output_dir_base}/cache
fi

mkdir -p ${output_dir} # main directory for the build process
if [ "$?" = "0" ]
then
	echo "Output directory '${output_dir}' successfully created."
else
	echo "ERROR while trying to create the output directory '${output_dir}'. Exiting now!"
	exit 5
fi


mkdir ${output_dir}/tmp # subdirectory for all downloaded or local temporary files
if [ "$?" = "0" ]
then
	echo "Subfolder 'tmp' of output directory '${output_dir}' successfully created."
else
	echo "ERROR while trying to create the 'tmp' subfolder '${output_dir}/tmp'. Exiting now!"
	exit 6
fi
}

### Rootfs Creation ###
build_rootfs()
{
	check_n_install_prerequisites # see if all needed packages are installed and if the versions are sufficient

	create_n_mount_temp_image_file # create the image file that is then used for the rootfs

	do_debootstrap # run debootstrap (first and second stage)

	# disable_mnt_tmpfs # disable all entries in /etc/init.d trying to mount temporary filesystems (tmpfs), in order to save precious RAM

	do_post_debootstrap_config # do some further system configuration

	compress_debian_rootfs # compress the resulting rootfs
}


### SD-Card Creation ###
create_sd_card()
{
	partition_n_format_disk # SD-card: make partitions and format
	finalize_disk # copy the bootloader, rootfs and kernel to the SD-card
}




#######################################
##### MAIN lower level functions: #####
#######################################

# Description: Check if the user calling the script has the necessary priviliges
check_priviliges()
{
if [[ $UID -ne 0 ]]
then
	echo "$0 must be run as root/superuser (su, sudo etc.)!
Please try again with the necessary priviliges."
	exit 10
fi
}


# Description: Function to log and echo messages in terminal at the same time
fn_log_echo()
{
	if [ -d ${output_dir} ]
	then
		echo "`date`:   ${1}" >> ${output_dir}/log.txt
		echo "${1}"
	else
		echo "Output directory '${output_dir}' doesn't exist. Exiting now!"
		exit 11
	fi
}


# Description: Function that checks if the needed internet connectivity is there.
check_connectivity()
{
fn_log_echo "Checking internet connectivity, which is mandatory for the next step."
for i in {1..3}
do
	for i in debian.org google.com kernel.org
	do
		ping -c 5 ${i}
		if [ "$?" = "0" ]
		then 
			fn_log_echo "Pinging '${i}' worked. Internet connectivity seems fine."
			done=1
			break
		else
			fn_log_echo "ERROR! Pinging '${i}' did NOT work. Internet connectivity seems bad or you are not connected.
	Please check, if in doubt!"
			if [ "${i}" = "kernel.org" ]
			then
				fn_log_echo "ERROR! All 3 ping attempts failed! You do not appear to be connected to the internet.
	Exiting now!"
				exit 97
			else	
				continue
			fi
		fi
	done
if [ "${done}" = "1" ]
then
	break
fi
done
}


# Description: See if the needed packages are installed and if the versions are sufficient
check_n_install_prerequisites()
{
	
check_connectivity

fn_log_echo "Installing some packages, if needed."
if [ "${host_os}" = "Debian" ]
then
	apt_prerequisites=${apt_prerequisites_debian}
elif [ "${host_os}" = "Ubuntu" ]
then
	apt_prerequisites=${apt_prerequisites_ubuntu}
else
	fn_log_echo "OS-Type '${host_os}' not correct.
Please run 'build_debian_system.sh --help' for more information"
	exit 12
fi

set -- ${apt_prerequisites}

while [ $# -gt 0 ]
do
	dpkg -l |grep "ii  ${1}" >/dev/null
	if [ "$?" = "0" ]
	then
		fn_log_echo "Package '${1}' is already installed. Nothing to be done."
	else
		fn_log_echo "Package '${1}' is not installed yet.
Trying to install it now!"
		if [ ! "${apt_get_update_done}" = "true" ]
		then
			fn_log_echo "Running 'apt-get update' to get the latest package dependencies."
			apt-get update
			if [ "$?" = "0" ]
			then
				fn_log_echo "'apt-get update' ran successfully! Continuing..."
				apt_get_update_done="true"
			else
				fn_log_echo "ERROR while trying to run 'apt-get update'. Exiting now."
				exit 13
			fi
		fi
		apt-get install -y ${1}
		if [ "$?" = "0" ]
		then
			fn_log_echo "'${1}' installed successfully!"
		else
			fn_log_echo "ERROR while trying to install '${1}'."
			if [ "${host_os}" = "Ubuntu" ] && [ "${1}" = "qemu-system" ]
			then
				fn_log_echo "Assuming that you are running this on Ubuntu 10.XX, where the package 'qemu-system' doesn't exist.
If your host system is not Ubuntu 10.XX based, this could lead to errors. Please check!"
			else
				fn_log_echo "Exiting now!"
				exit 14
			fi
		fi
	fi

	if [ $1 = "qemu-user-static" ]
	then
		sh -c "dpkg -l|grep \"qemu-user-static\"|grep \"1.\"" >/dev/null
		if [ $? = "0" ]
		then
			fn_log_echo "Sufficient version of package '${1}' found. Continueing..."
		else
			fn_log_echo "The installed version of package '${1}' is too old.
You need to install a package with a version of at least 1.0.
For example from the debian-testing ('http://packages.debian.org/search?keywords=qemu&searchon=names&suite=testing&section=all')
respectively the Ubuntu precise ('http://packages.ubuntu.com/search?keywords=qemu&searchon=names&suite=precise&section=all') repositiories.
Exiting now!"
			exit 15
		fi
	fi
	shift
done

fn_log_echo "Function 'check_n_install_prerequisites' DONE."
}


# Description: Create a image file as root-device for the installation process
create_n_mount_temp_image_file()
{
fn_log_echo "Creating the temporary image file for the debootstrap process."
dd if=/dev/zero of=${output_dir}/${output_filename}.img bs=1M count=${work_image_size_MB}
if [ "$?" = "0" ]
then
	fn_log_echo "File '${output_dir}/${output_filename}.img' successfully created with a size of ${work_image_size_MB}MB."
else
	fn_log_echo "ERROR while trying to create the file '${output_dir}/${output_filename}.img'. Exiting now!"
	exit 16
fi

fn_log_echo "Formatting the image file with the ext4 filesystem."
mkfs.ext4 -F ${output_dir}/${output_filename}.img
if [ "$?" = "0" ]
then
	fn_log_echo "ext4 filesystem successfully created on '${output_dir}/${output_filename}.img'."
else
	fn_log_echo "ERROR while trying to create the ext4 filesystem on  '${output_dir}/${output_filename}.img'. Exiting now!"
	exit 17
fi

fn_log_echo "Creating the directory to mount the temporary filesystem."
mkdir -p ${qemu_mnt_dir}
if [ "$?" = "0" ]
then
	fn_log_echo "Directory '${qemu_mnt_dir}' successfully created."
else
	fn_log_echo "ERROR while trying to create the directory '${qemu_mnt_dir}'. Exiting now!"
	exit 18
fi

fn_log_echo "Now mounting the temporary filesystem."
mount ${output_dir}/${output_filename}.img ${qemu_mnt_dir} -o loop
if [ "$?" = "0" ]
then
	fn_log_echo "Filesystem correctly mounted on '${qemu_mnt_dir}'."
else
	fn_log_echo "ERROR while trying to mount the filesystem on '${qemu_mnt_dir}'. Exiting now!"
	exit 19
fi

fn_log_echo "Function 'create_n_mount_temp_image_file' DONE."
}


# Description: Run the debootstrap steps, like initial download, extraction plus configuration and setup
do_debootstrap()
{
	
check_connectivity
	
fn_log_echo "Running first stage of debootstrap now."

if [ "${use_cache}" = "yes" ]
then
	if [ -d "${output_dir_base}/cache/" ]
	then
		if [ -e "${output_dir_base}/cache/${base_sys_cache_tarball}" ]
		then
			fn_log_echo "Using debian debootstrap tarball '${output_dir_base}/cache/${base_sys_cache_tarball}' from cache."
			debootstrap --foreign --unpack-tarball="${output_dir_base}/cache/${base_sys_cache_tarball}" --include=${deb_add_packages} --verbose --arch=armhf --variant=minbase "${debian_target_version}" "${qemu_mnt_dir}/" "${debian_mirror_url}"
		else
			fn_log_echo "No debian debootstrap tarball found in cache. Creating one now!"
			debootstrap --foreign --make-tarball="${output_dir_base}/cache/${base_sys_cache_tarball}" --include=${deb_add_packages} --verbose --arch=armhf --variant=minbase "${debian_target_version}" "${output_dir_base}/cache/tmp/" "${debian_mirror_url}"
			sleep 3
			debootstrap --foreign --unpack-tarball="${output_dir_base}/cache/${base_sys_cache_tarball}" --include=${deb_add_packages} --verbose --arch=armhf --variant=minbase "${debian_target_version}" "${qemu_mnt_dir}/" "${debian_mirror_url}"
		fi
	fi
else
	fn_log_echo "Not using cache, according to the settings. Thus running debootstrap without creating a tarball."
	debootstrap --include=${deb_add_packages} --verbose --arch armhf --variant=minbase --foreign "${debian_target_version}" "${qemu_mnt_dir}" "${debian_mirror_url}"
fi

modprobe binfmt_misc

cp /usr/bin/qemu-arm-static ${qemu_mnt_dir}/usr/bin

mkdir -p ${qemu_mnt_dir}/dev/pts

fn_log_echo "Mounting both /dev/pts and /proc on the temporary filesystem."
mount devpts ${qemu_mnt_dir}/dev/pts -t devpts
mount -t proc proc ${qemu_mnt_dir}/proc

fn_log_echo "Entering chroot environment NOW!"

apt_get_helper "write_script"

fn_log_echo "Starting the second stage of debootstrap now."
echo "#!/bin/bash
/debootstrap/debootstrap --second-stage 2>>/debootstrap_stg2_errors.txt
cd /root 2>>/debootstrap_stg2_errors.txt

cat <<END > /etc/apt/sources.list 2>>/debootstrap_stg2_errors.txt
deb ${debian_mirror_url} ${debian_target_version} ${debian_repositories}
deb-src ${debian_mirror_url} ${debian_target_version} ${debian_repositories}
END

if [ \"${debian_target_version}\" = \"stable\" ] || [ \"${debian_target_version}\" = \"wheezy\" ] || [ \"${debian_target_version}\" = \"testing\" ] || [ \"${debian_target_version}\" = \"jessie\" ]
then
	cat <<END >>/etc/apt/sources.list 2>>/debootstrap_stg2_errors.txt
deb ${debian_mirror_url} ${debian_target_version}-updates ${debian_repositories}
deb-src ${debian_mirror_url} ${debian_target_version}-updates ${debian_repositories}
deb http://security.debian.org/ ${debian_target_version}/updates ${debian_repositories}
deb-src http://security.debian.org/ ${debian_target_version}/updates ${debian_repositories}
END
fi

apt-get update 2>>/debootstrap_stg2_errors.txt

mknod /dev/ttyS0 c 4 64	# for the serial console 2>>/debootstrap_stg2_errors.txt
mknod /dev/mmcblk0 b 179 0 2>>/debootstrap_stg2_errors.txt
#mknod /dev/mmcblk0p1 b 179 1 2>>/debootstrap_stg2_errors.txt

cat <<END > /etc/network/interfaces 2>>/debootstrap_stg2_errors.txt
#auto lo eth0
auto lo
iface lo inet loopback
iface eth0 inet dhcp
END

echo A10-debian > /etc/hostname 2>>/debootstrap_stg2_errors.txt

echo \"127.0.0.1 localhost\" >> /etc/hosts 2>>/debootstrap_stg2_errors.txt
echo \"127.0.0.1 A10-debian\" >> /etc/hosts 2>>/debootstrap_stg2_errors.txt
echo \"nameserver ${nameserver_addr}\" > /etc/resolv.conf 2>>/debootstrap_stg2_errors.txt

cat <<END > /etc/rc.local 2>>/debootstrap_stg2_errors.txt
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will exit 0 on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

/post_debootstrap_setup.sh 2>>/post_debootstrap_setup_log.txt && rm /post_debootstrap_setup.sh

if [ -e /zram_setup.sh ]
then
	/zram_setup.sh 2>>/zram_setup_log.txt && rm /zram_setup.sh
fi

exit 0
END
rm /debootstrap_pt1.sh
exit" > ${qemu_mnt_dir}/debootstrap_pt1.sh
chmod +x ${qemu_mnt_dir}/debootstrap_pt1.sh
/usr/sbin/chroot ${qemu_mnt_dir} /bin/bash /debootstrap_pt1.sh 2>${output_dir}/debootstrap_pt1_errors.txt

if [ "$?" = "0" ]
then
	fn_log_echo "First part of chroot operations done successfully!"
else
	fn_log_echo "Errors while trying to run the first part of the chroot operations."
fi


if [ "${use_cache}" = "yes" ]
then
	if [ -e ${output_dir_base}/cache/additional_packages.tar.gz ]
	then
		if [ "${mali_graphics_choice}" = "none" ] #[ ! "${mali_graphics_choice}" = "copy" ] && [ ! "${mali_graphics_choice}" = "build" ] 
		then
			fn_log_echo "Extracting the additional packages 'additional_packages.tar.gz' from cache. now."
			tar_all extract "${output_dir_base}/cache/additional_packages.tar.gz" "${qemu_mnt_dir}/var/cache/apt/" 
		fi
	elif [ ! -e "${output_dir}/cache/additional_packages.tar.gz" ]
	then
		add_pack_create="yes"
	fi
	
	if [ -e ${output_dir_base}/cache/additional_desktop_packages.tar.gz ] && [ "${mali_graphics_choice}" = "copy" ]
	then
		fn_log_echo "Extracting the additional desktop packages 'additional_desktop_packages.tar.gz' from cache. now."
		tar_all extract "${output_dir_base}/cache/additional_desktop_packages.tar.gz" "${qemu_mnt_dir}/var/cache/apt/"
	elif [ ! -e "${output_dir}/cache/additional_desktop_packages.tar.gz" ] && [ "${mali_graphics_choice}" = "build" ] #[ ! "${mali_graphics_choice}" = "copy" ]
	then
		add_desk_pack_create="yes"
	fi
	
	if [ -e ${output_dir_base}/cache/additional_dev_packages.tar.gz ] && [ "${mali_graphics_choice}" = "build" ]
	then
		fn_log_echo "Extracting the additional dev packages 'additional_dev_packages.tar.gz' from cache. now."
		tar_all extract "${output_dir_base}/cache/additional_dev_packages.tar.gz" "${qemu_mnt_dir}/var/cache/apt/"
	elif [ ! -e "${output_dir}/cache/additional_dev_packages.tar.gz" ] && [ "${mali_graphics_choice}" = "build" ]
	then
		add_dev_pack_create="yes"
	fi
fi

	
mount devpts ${qemu_mnt_dir}/dev/pts -t devpts
mount -t proc proc ${qemu_mnt_dir}/proc

echo "#!/bin/bash
source apt_helper.sh
export LANG=C 2>>/debootstrap_stg2_errors.txt

for k in ${locale_list}
do
	sed -i 's/# '\${k}'/'\${k}'/g' /etc/locale.gen # enable locale
done

locale-gen 2>>/debootstrap_stg2_errors.txt

export LANG=${std_locale} 2>>/debootstrap_stg2_errors.txt	# language settings
export LC_ALL=${std_locale} 2>>/debootstrap_stg2_errors.txt
export LANGUAGE=${std_locale} 2>>/debootstrap_stg2_errors.txt

apt_get_helper \"download\" \"${additional_packages}\"

if [ \"${mali_graphics_choice}\" = \"copy\" ]
then
	apt_get_helper \"download\" \"${additional_desktop_packages}\"
elif [ \"${mali_graphics_choice}\" = \"build\" ]
then
	apt_get_helper \"download\" \"${additional_desktop_packages}\"
	apt_get_helper \"download\" \"${additional_dev_packages}\"
fi

if [ \"${prepare_accel_vlc}\" = \"yes\" ]
then
	apt_get_helper \"dep_download\" \"vlc\"
fi

if [ \"${prepare_accel_xbmc}\" = \"yes\" ]
then
	apt_get_helper \"dep_download\" \"xbmc\"
	apt_get_helper \"download\" \"${xbmc_prereq}\"
fi


dd if=/dev/zero of=/swapfile bs=1024 count=1048576   ### 1024 MB swapfile
mkswap /swapfile
chown root:root /swapfile
chmod 0600 /swapfile

cat <<END > /etc/fstab 2>>/debootstrap_stg2_errors.txt
# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/root	/	ext4	defaults,noatime	0	1
#/dev/mmcblk0p3	swap	swap	defaults,pri=0	0	0
/swapfile	swap	swap	defaults,pri=100	0	0
tmpfs	/tmp	tmpfs	defaults	0	0
tmpfs	/var/spool	tmpfs	defaults,noatime,mode=1777	0	0
tmpfs	/var/tmp	tmpfs	defaults	0	0
tmpfs	/var/log	tmpfs	defaults,noatime,mode=0755	0	0
END

cat <<END > /etc/default/rcS 2>>/debootstrap_stg2_errors.txt
#
# /etc/default/rcS
#
# Default settings for the scripts in /etc/rcS.d/
#
# For information about these variables see the rcS(5) manual page.
#
# This file belongs to the \"initscripts\" package.

# delete files in /tmp during boot older than x days.
# '0' means always, -1 or 'infinite' disables the feature
#TMPTIME=0

# spawn sulogin during boot, continue normal boot if not used in 30 seconds
#SULOGIN=no

# do not allow users to log in until the boot has completed
#DELAYLOGIN=no

# be more verbose during the boot process
#VERBOSE=no

# automatically repair filesystems with inconsistencies during boot
#FSCKFIX=noTMPTIME=0
SULOGIN=no
DELAYLOGIN=no
VERBOSE=no
FSCKFIX=yes

END

cat <<END > /etc/default/tmpfs 2>>/debootstrap_stg2_errors.txt
# Configuration for tmpfs filesystems mounted in early boot, before
# filesystems from /etc/fstab are mounted.  For information about
# these variables see the tmpfs(5) manual page.

# /run is always mounted as a tmpfs on systems which support tmpfs
# mounts.

# mount /run/lock as a tmpfs (separately from /run).  Defaults to yes;
# set to no to disable (/run/lock will then be part of the /run tmpfs,
# if available).
#RAMLOCK=yes

# mount /run/shm as a tmpfs (separately from /run).  Defaults to yes;
# set to no to disable (/run/shm will then be part of the /run tmpfs,
# if available).
#RAMSHM=yes

# mount /tmp as a tmpfs.  Defaults to no; set to yes to enable (/tmp
# will be part of the root filesystem if disabled).  /tmp may also be
# configured to be a separate mount in /etc/fstab.
#RAMTMP=no

# Size limits.  Please see tmpfs(5) for details on how to configure
# tmpfs size limits.
#TMPFS_SIZE=20%VM
#RUN_SIZE=10%
#LOCK_SIZE=5242880 # 5MiB
#SHM_SIZE=
#TMP_SIZE=

# Mount tmpfs on /tmp if there is less than the limit size (in kiB) on
# the root filesystem (overriding RAMTMP).
#TMP_OVERFLOW_LIMIT=1024

RAMTMP=yes
END

echo '#T0:2345:respawn:/sbin/mingetty ttyS0 115200 vt102' >> /etc/inittab 2>>/debootstrap_stg2_errors.txt	# enable serial consoles

rm /debootstrap_pt2.sh
exit" > ${qemu_mnt_dir}/debootstrap_pt2.sh
chmod +x ${qemu_mnt_dir}/debootstrap_pt2.sh
/usr/sbin/chroot ${qemu_mnt_dir} /bin/bash /debootstrap_pt2.sh 2>${output_dir}/debootstrap_pt2_errors.txt

if [ "$?" = "0" ]
then
	fn_log_echo "Second part of chroot operations done successfully!"
else
	fn_log_echo "Errors while trying to run the second part of the chroot operations."
fi


if [ "${add_pack_create}" = "yes" ]
then
	if  [ "${mali_graphics_choice}" = "none" ] #[ ! "${mali_graphics_choice}" = "copy" ] && [ ! "${mali_graphics_choice}" = "build" ]   
	then
		fn_log_echo "Compress choice 1. Only additional packages."
		cd ${qemu_mnt_dir}/var/cache/apt/
		tar_all compress "${output_dir_base}/cache/additional_packages.tar.gz" .
		cd ${output_dir}
	fi
fi

if [ "${add_dev_pack_create}" = "yes" ] && [ "${mali_graphics_choice}" = "build" ] # case of both desk- and dev-packages already downloaded into the /var/cache dir
then
	fn_log_echo "Compress choice 2. Desktop and dev packages together (including additional packages)."
	fn_log_echo "Trying to create cache archive for dev-packages (includes desktop-packages!)."
	cd ${qemu_mnt_dir}/var/cache/apt/
	tar_all compress "${output_dir_base}/cache/additional_dev_packages.tar.gz" .
	cd ${output_dir}
fi

if [ "${add_desk_pack_create}" = "yes" ] && [ "${mali_graphics_choice}" = "copy" ] # case of only desk-packages already downloaded into the /var/cache dir
then
	fn_log_echo "Compress choice 3. Desktop packages, including additional packages."
	fn_log_echo "Trying to create cache archive for desktop-packages."
	cd ${qemu_mnt_dir}/var/cache/apt/
	tar_all compress "${output_dir_base}/cache/additional_desktop_packages.tar.gz" .
	cd ${output_dir}
fi

sleep 5
umount_img sys
fn_log_echo "Just exited chroot environment."
fn_log_echo "Base debootstrap steps 1&2 are DONE!"
}



# Description: Do some further configuration of the system, after debootstrap has finished
do_post_debootstrap_config()
{

fn_log_echo "Now starting the post-debootstrap configuration steps."

mkdir -p ${output_dir}/qemu-kernel

get_n_check_file "${std_kernel_pkg}" "standard_kernel" "${output_dir}/tmp"

get_n_check_file "${qemu_kernel_pkg}" "qemu_kernel" "${output_dir}/tmp"

tar_all extract "${output_dir}/tmp/${qemu_kernel_pkg##*/}" "${output_dir}/qemu-kernel"
sleep 3
tar_all extract "${output_dir}/tmp/${std_kernel_pkg##*/}" "${qemu_mnt_dir}"

if [ -d ${output_dir}/qemu-kernel/lib/ ]
then
	cp -ar ${output_dir}/qemu-kernel/lib/ ${qemu_mnt_dir}  # copy the qemu kernel modules intot the rootfs
fi

if [ "${use_zram}" = "yes" ]
then
	fn_log_echo "Usage of ZRAM activated!"
	echo "#!/bin/sh
cat <<END > /etc/rc.local 2>>/zram_setup_errors.txt
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will exit 0 on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

modprobe ${zram_kernel_module_name} num_devices=1
sleep 2
echo ${zram_size_B} > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0

if [ -e /dev/ump ]
then
	chmod 777 /dev/ump
fi

if [ -e /dev/mali ]
then
	chmod 777 /dev/mali
fi

chmod 777 /dev/disp
chmod 777 /dev/cedar_dev


echo 0 > /sys/class/graphics/fb0/blank # disable framebuffer blanking
echo 0 > /sys/module/8192cu/parameters/rtw_power_mgnt # disable wlan power management
#echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor # set cpufreq governor to 'ondemand'

#echo 1 > /sys/block/sdX/queue/iosched/fifo_batch

exit 0
END
chmod +x /etc/rc.local
exit 0" > ${qemu_mnt_dir}/zram_setup.sh
#cp ${qemu_mnt_dir}/zram_setup.sh ${qemu_mnt_dir}/zram_setup.sh.bak
chmod +x ${qemu_mnt_dir}/zram_setup.sh
fi

git_branch_name="${mali_xserver_2d_git##*.git -b }"
if [ ! -z "${git_branch_name}" ]
then
	xf86_version="${git_branch_name:0:4}"
	#fn_log_echo "DEBUG: xf86_version='${xf86_version}' ."
else
	xf86_version="r3p0" # default value
	#fn_log_echo "DEBUG: xf86_version='${xf86_version}' ."
fi

#date_cur=`date` # needed further down as a very important part to circumvent the PAM Day0 change password problem

echo "#!/bin/bash
source apt_helper.sh
#date -s \"${date_cur}\" 2>>/post_debootstrap_errors.txt	# set the system date to prevent PAM from exhibiting its nasty DAY0 forced password change

apt_get_helper \"install\" \"${additional_packages}\"
if [ \"${mali_graphics_choice}\" = \"copy\" ]
then
	apt_get_helper \"install\" \"${additional_desktop_packages}\"
elif [ \"${mali_graphics_choice}\" = \"build\" ]
then
	apt_get_helper \"install\" \"${additional_desktop_packages}\"
	apt_get_helper \"install\" \"${additional_dev_packages}\"
fi

if [ \"${prepare_accel_vlc}\" = \"yes\" ]
then
	apt-get remove -y vlc vlc-data
	apt_get_helper \"dep_install\" \"vlc\"
	apt-get remove -y lua5.2
fi

if [ \"${prepare_accel_xbmc}\" = \"yes\" ]
then
	apt-get remove -y xbmc xbmc-data xbmc-bin
	apt_get_helper \"dep_install\" \"xbmc\"
	apt_get_helper \"install\" \"${xbmc_prereq}\"
	apt-get remove -y ${xbmc_nogos}
fi

#apt-get autoremove
apt-get clean
dpkg -l > /installed_packages.txt
ldconfig -v

if [ \"${i2c_hwclock}\" = \"yes\" ]; then update-rc.d -f i2c_hwclock.sh start 02 S . stop 07 0 6 . 2>>/post_debootstrap_errors.txt;fi;

if [ \"${use_zram}\" = \"yes\" ] && [ ! -z \"${vm_swappiness}\" ]; then echo vm.swappiness=${vm_swappiness} >> /etc/sysctl.conf; fi;

if [ ! -z `grep setup.sh /etc/rc.local` ]
then
	cat <<END > /etc/rc.local 2>>/post_debootstrap_errors.txt
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will exit 0 on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0
END
fi

sh -c \"echo '${root_password}
${root_password}
' | passwd root\" 2>>/post_debootstrap_errors.txt
passwd -u root 2>>/post_debootstrap_errors.txt
passwd -x -1 root 2>>/post_debootstrap_errors.txt
passwd -w -1 root 2>>/post_debootstrap_errors.txt

sh -c \"echo '${user_password}
${user_password}





' | adduser ${username}\" 2>>/post_debootstrap_errors.txt

if [ \"${mali_graphics_choice}\" = \"copy\" -o \"${mali_graphics_choice}\" = \"build\" ]
then
	echo \"Writing '/etc/modules' and '/etc/X11/xorg.conf' for mali graphics usage.\"
	cat << END >> /etc/modules
8192cu
lcd
hdmi
ump
disp
mali
mali_drm
END
	
	if [ \"${mali_graphics_choice}\" = \"copy\" ]
	then
		echo \"Downloaded mali graphics driver. Driver should already work. Please check!\"
	elif [ \"${mali_graphics_choice}\" = \"build\" ]
	then
		echo \"Downloaded sources for mali graphics. Trying to compile the driver, now.\"
		cd /root/mali_2d_build 2>>/mali_drv_compile_errors.txt
		if [ \"\${?}\" = \"0\" ]
		then
			echo \"Successfully changed into directory '/root/mali_2d_build'.\" && echo \"Successfully changed into directory '/root/mali_2d_build'.\" >> /mali_drv_compile.txt
			cd /root/mali_2d_build/libdri2 2>>/mali_drv_compile_errors.txt
			if [ \"\${?}\" = \"0\" ]
			then
				echo \"Successfully changed into directory '/root/mali_2d_build/libdri2/'.\" && echo \"Successfully changed into directory '/root/mali_2d_build/libdri2/'.\" >> /mali_drv_compile.txt 
				./autogen.sh 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'autogen.sh' (libdri2) command.\" && echo \"Successfully ran the 'autogen.sh' (libdri2) command.\" >> /mali_drv_compile.txt
				./configure --prefix=/usr --x-includes=/usr/include --x-libraries=/usr/lib 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the configuration for libdri2.\" && echo \"Successfully ran the configuration for libdri2.\" >> /mali_drv_compile.txt
				make -j`expr ${qemu_nr_cpus} + 1` 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make' (libdri2) command.\" && echo \"Successfully ran the 'make' (libdri2) command.\" >> /mali_drv_compile.txt
				make install 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make install' (libdri2) command.\" && echo \"Successfully ran the 'make install' (libdri2) command.\" >> /mali_drv_compile.txt
			fi
			cd /root/mali_2d_build/sunxi-mali 2>>/mali_drv_compile_errors.txt
			if [ \"\${?}\" = \"0\" ]
			then
				echo \"Changed directory to 'sunxi-mali'.\" && echo \"Changed directory to 'sunxi-mali'.\" >> /mali_drv_compile.txt
				make config VERSION=${mali_module_version} ABI=armhf EGL_TYPE=x11 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make config' command of 'sunxi-mali'.\" >> /mali_drv_compile.txt
				make -j`expr ${qemu_nr_cpus} + 1` 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make' (sunxi-mali) command.\" && echo \"Successfully ran the 'make' (sunxi-mali) command.\" >> /mali_drv_compile.txt
				make install 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make install' (sunxi-mali) command.\" && echo \"Successfully ran the 'make install' (sunxi-mali) command.\" >> /mali_drv_compile.txt
				#cp -f ./xorg.conf /etc/X11/ && echo \"Successfully copied the 'xorg.conf' (xf86-video-mali).\" && echo \"Successfully copied the 'xorg.conf' (xf86-video-mali).\" >> /mali_drv_compile.txt
				cd lib/sunxi-mali-proprietary && echo \"Changed directory to 'lib/sunxi-mali-proprietary'.\" && echo \"Changed directory to 'lib/sunxi-mali-proprietary'.\" >> /mali_drv_compile.txt
				make VERSION=${mali_module_version} ABI=armhf EGL_TYPE=x11 -j`expr ${qemu_nr_cpus} + 1` 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make' (sunxi-mali-proprietary) command.\" && echo \"Successfully ran the 'make' (sunxi-mali-proprietary) command.\" >> /mali_drv_compile.txt
				make install 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make install' (sunxi-mali-proprietary) command.\" && echo \"Successfully ran the 'make install' (sunxi-mali-proprietary) command.\" >> /mali_drv_compile.txt
				cd ../../test 2>>/mali_drv_compile_errors.txt && echo \"Changed directory to '../../test'.\" && echo \"Changed directory to '../../test'.\" >> /mali_drv_compile.txt
				make -j`expr ${qemu_nr_cpus} + 1` test 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make test' (sunxi-mali) command.\" && echo \"Successfully ran the 'make test' (sunxi-mali) command.\" >> /mali_drv_compile.txt
			fi
			cd /root/mali_2d_build/xf86-video-mali 2>>/mali_drv_compile_errors.txt
			if [ \"\${?}\" = \"0\" ]
			then
				echo \"Changed directory to 'xf86-video-mali'.\" && echo \"Changed directory to 'xf86-video-mali'.\" >> /mali_drv_compile.txt
				autoreconf -vi 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran autoreconf.\" && echo \"Successfully ran autoreconf.\" >> /mali_drv_compile.txt
				./configure --prefix=/usr --x-includes=/usr/include --x-libraries=/usr/lib 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the configuration for the xf86 driver.\" && echo \"Successfully ran the configuration for the xf86 driver.\" >> /mali_drv_compile.txt
				make -j`expr ${qemu_nr_cpus} + 1` 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make' (xf86-video-mali) command.\" && echo \"Successfully ran the 'make' (xf86-video-mali) command.\" >> /mali_drv_compile.txt
				make install 2>>/mali_drv_compile_errors.txt && echo \"Successfully ran the 'make install' (xf86-video-mali) command.\" && echo \"Successfully ran the 'make install' (xf86-video-mali) command.\" >> /mali_drv_compile.txt
				cp -f ./xorg.conf /etc/X11/xorg.conf && echo \"Successfully copied the 'xorg.conf' (xf86-video-mali).\" && echo \"Successfully copied the 'xorg.conf' (xf86-video-mali).\" >> /mali_drv_compile.txt
				grep 'Option \"AIGLX\" \"false\"' /etc/X11/xorg.conf
				if [ ! \"$?\" = \"0\" ]
				then
					cat << END >> /etc/X11/xorg.conf
Section \"ServerFlags\"
Option \"AIGLX\" \"false\"
EndSection
END
				fi
			fi
		else
			echo \"ERROR: Couldn't change into directory '/root/mali_2d_build/'!\" >>/post_debootstrap_errors.txt
		fi
		
		cat <<END > /etc/rc.local 2>>/debootstrap_stg2_errors.txt
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will exit 0 on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

if [ -e /zram_setup.sh ]
then
	/zram_setup.sh 2>>/zram_setup_error.txt && rm /zram_setup.sh
fi

if [ -e /dev/ump ]
then
	chmod 777 /dev/ump
fi

if [ -e /dev/mali ]
then
	chmod 777 /dev/mali
fi

echo 0 > /sys/class/graphics/fb0/blank # disable framebuffer blanking
echo 0 > /sys/module/8192cu/parameters/rtw_power_mgnt # disable wlan power management
#echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor # set cpufreq governor to 'ondemand'
#echo 1 > /sys/block/sdX/queue/iosched/fifo_batch

exit 0
END
	fi
elif [ \"${mali_graphics_choice}\" = \"none\" ]
then
	echo \"No graphics driver and no graphical user interface wanted.\"
else
	echo \"No valid option. Only copy|build|none are accepted. Doing nothing.\"
fi


if [ \"${compile_accel_vlc}\" = \"yes\" ]
then
	if [ -d /root/libcedarx ]
	then
		cd /root/libcedarx 2>>/vlc_compile_errors.txt && echo \"Successfully changed directory to '/root/libcedarx'.\" >>/vlc_compile.txt
		./autogen.sh 2>>/vlc_compile_errors.txt && echo \"Successfully ran libcedarx autogen.sh.\" && echo \"Successfully ran libcedarx autogen.sh.\" >>/vlc_compile.txt
		./configure --host=arm-linux-gnueabihf --prefix=/usr 2>>/vlc_compile_errors.txt && echo \"Successfully ran libcedarx configure.\" && echo \"Successfully ran libcedarx configure.\" >>/vlc_compile.txt
		make -j`expr ${qemu_nr_cpus} + 1` 2>>/vlc_compile_errors.txt && echo \"Successfully ran libcedarx make.\" && echo \"Successfully ran libcedarx make.\" >>/vlc_compile.txt
		make install 2>>/vlc_compile_errors.txt && echo \"Successfully ran libcedarx make install.\" && echo \"Successfully ran libcedarx make install.\" >>/vlc_compile.txt
		if [ -d /root/vlc ]
		then
			cd /root/vlc 2>>/vlc_compile_errors.txt && echo \"Successfully changed directory to '/root/vlc'.\" >>/vlc_compile.txt
			./bootstrap 2>>/vlc_compile_errors.txt && echo \"Successfully ran vlc bootstrap.\" && echo \"Successfully ran vlc bootstrap.\" >>/vlc_compile.txt
			./configure --host=arm-linux-gnueabihf --prefix=/usr --enable-cedar 2>>/vlc_compile_errors.txt && echo \"Successfully ran vlc configure.\" && echo \"Successfully ran vlc configure.\" >>/vlc_compile.txt
			make -j`expr ${qemu_nr_cpus} + 1` 2>>/vlc_compile_errors.txt && echo \"Successfully ran vlc make.\" && echo \"Successfully ran vlc make.\" >>/vlc_compile.txt
			make install 2>>/vlc_compile_errors.txt && echo \"Successfully ran vlc make install.\" && echo \"Successfully ran vlc make install.\" >>/vlc_compile.txt
		else
			echo \"ERROR! Directory '/root/vlc' not found! Please check!\" >>/vlc_compile_errors.txt
		fi
	else
		echo \"ERROR! Directory '/root/libcedarx' not found! Please check!\" >>/vlc_compile_errors.txt
	fi
fi
if [ \"${compile_accel_xbmc}\" = \"yes\" ]
then
	if [ -d /root/xbmca10/tools/a10/depends ]
	then
		cd /root/xbmca10/tools/a10/depends 2>>/xbmc_compile_errors.txt
		sed -i 's<mkdir<mkdir -p<g' /root/xbmca10/tools/a10/depends/Makefile 2>>/xbmc_compile_errors.txt
		mkdir -p /opt/a10hacking/xbmctmp/tarballs 2>>/xbmc_compile_errors.txt
		make -j`expr ${qemu_nr_cpus} + 1` 2>>/xbmc_compile_errors.txt && echo \"Successfully ran xbmc-depends make.\" >>/xbmc_compile.txt
		echo -e \"\nA10HWR=1\" >> /etc/environment 2>>/xbmc_compile_errors.txt
		echo -e \"\nexport A10HWR=1\" >> /home/${username}/.bashrc 2>>/xbmc_compile_errors.txt
		make -j`expr ${qemu_nr_cpus} + 1` -C xbmc 2>>/xbmc_compile_errors.txt && echo \"Successfully ran xbmc make.\" >>/xbmc_compile.txt
		cd /root/xbmca10/ 2>>/xbmc_compile_errors.txt
		make install 2>>/xbmc_compile_errors.txt && echo \"Successfully ran xbmc make install.\" >>/xbmc_compile.txt
	else
		echo \"ERROR! Directory '/root/xbmca10' not found! Please check!\" >>/xbmc_compile_errors.txt
	fi
fi

ldconfig -v

if [ -e /apt_helper.sh ]
then
	rm /apt_helper.sh
fi

sed -i 's<#/dev/mmcblk0p3</dev/mmcblk0p3<g' /etc/fstab
sed -i 's</swapfile<#&<g' /etc/fstab
sed -i 's<#T0:2345:respawn:/sbin/mingetty<T0:2345:respawn:/sbin/mingetty<g' /etc/inittab

echo \"export XDG_CACHE_HOME=\"/dev/shm/.cache\"\" >> /home/${username}/.bashrc

df -ah >> /disk_usage.txt

swapoff /swapfile && rm /swapfile

reboot 2>>/post_debootstrap_errors.txt
exit 0" > ${qemu_mnt_dir}/post_debootstrap_setup.sh
chmod +x ${qemu_mnt_dir}/post_debootstrap_setup.sh

if [ "${mali_graphics_opengl}" = "yes" ]
then
	get_n_check_file "${mali_opengl_bin}" "mali_opengl_driver" "${output_dir}/tmp"
	tar_all extract "${output_dir}/tmp/${mali_opengl_bin##*/}" "${qemu_mnt_dir}"
fi

if [ "${mali_graphics_choice}" = "copy" ]
then
	get_n_check_file "${mali_2d_bin}" "mali_2d_driver" "${output_dir}/tmp"
	tar_all extract "${output_dir}/tmp/${mali_2d_bin##*/}" "${qemu_mnt_dir}"
elif [ "${mali_graphics_choice}" = "build" ]
then
	#if [ "${use_cache}" = "yes" ]
	#then
		#if [ -d "${output_dir_base}/cache/" ]
		#then
			#for i in mali_xserver_2d_git mali_2d_libdri2_git mali_2d_mali_git
			#do
				#if [ -e "${output_dir_base}/cache/`eval \${${i}_tarball}`" ]
				#then
					#fn_log_echo "Using ${i} tarball '${output_dir_base}/cache/`eval \${${i}_tarball}`' from cache."
					#tar_all extract "${output_dir_base}/cache/`eval \${${i}_tarball}`_tarball}" "${qemu_mnt_dir}/root/"
					#cd ${qemu_mnt_dir}/root/`eval \${${i}_tarball}` && git pull
				#fi	
			#done
	mkdir -p ${qemu_mnt_dir}/root/mali_2d_build && fn_log_echo "Directory for graphics driver build successfully created."
	get_n_check_file "${mali_xserver_2d_git}" "xf86-video-mali" "${qemu_mnt_dir}/root/mali_2d_build"
	get_n_check_file "${mali_2d_libdri2_git}" "libdri2" "${qemu_mnt_dir}/root/mali_2d_build"
	get_n_check_file "${mali_2d_mali_git}" "mali" "${qemu_mnt_dir}/root/mali_2d_build"
	cd ${qemu_mnt_dir}/root/mali_2d_build/sunxi-mali
	git submodule init
	git submodule update
	get_n_check_file "${mali_2d_proprietary_git}" "mali-proprietary" "${qemu_mnt_dir}/root/mali_2d_build/sunxi-mali/lib/"
fi

if [ "${prepare_accel_vlc}" = "yes" ]
then
	if [ "${use_cache}" = "yes" ]
	then
		if [ -d "${output_dir_base}/cache/" ]
		then
			### libcedarx first
			if [ -e "${output_dir_base}/cache/${libcedarx_git_tarball}" ]
			then
				fn_log_echo "Using libcedarx_git tarball '${output_dir_base}/cache/${libcedarx_git_tarball}' from cache."
				tar_all extract "${output_dir_base}/cache/${libcedarx_git_tarball}" "${qemu_mnt_dir}/root/"
				cd ${qemu_mnt_dir}/root/libcedarx && git pull
			else
				fn_log_echo "No libcedarx git tarball found in cache. Creating one now!"
				get_n_check_file "${libcedarx_git}" "libcedarx" "${qemu_mnt_dir}/root/"
				if [ "$?" = "0" ]
				then
					cd ${qemu_mnt_dir}/root/ && tar_all compress "${output_dir_base}/cache/${libcedarx_git_tarball}" ./libcedarx
				else
					fn_log_echo "ERROR! Something seems to have gone wrong while trying to get 'libcedarx' via git."
				fi
			fi
			
			### then VLC
			if [ -e "${output_dir_base}/cache/${vlc_git_tarball}" ]
			then
				fn_log_echo "Using vlc_git tarball '${output_dir_base}/cache/${vlc_git_tarball}' from cache."
				tar_all extract "${output_dir_base}/cache/${vlc_git_tarball}" "${qemu_mnt_dir}/root/"
				cd ${qemu_mnt_dir}/root/vlc && git pull
			else
				fn_log_echo "No vlc_git tarball found in cache. Creating one now!"
				get_n_check_file "${vlc_git}" "vlc" "${qemu_mnt_dir}/root/"
				if [ "$?" = "0" ]
				then
					cd ${qemu_mnt_dir}/root/ && tar_all compress "${output_dir_base}/cache/${vlc_git_tarball}" ./vlc
				else
					fn_log_echo "ERROR! Something seems to have gone wrong while trying to get 'vlc' via git."
				fi
			fi
		else
			fn_log_echo "ERROR! Cache directory '${output_dir_base}/cache/' does not seem to exist. Please check
Exiting now!"
			exit 98
		fi
	else
		fn_log_echo "Not using cache, according to the settings. Thus running git clone without creating a tarball."
		get_n_check_file "${libcedarx_git}" "libcedarx" "${qemu_mnt_dir}/root/"
		get_n_check_file "${vlc_git}" "vlc" "${qemu_mnt_dir}/root/"
	fi
fi

if [ "${prepare_accel_xbmc}" = "yes" ]
then
	if [ "${use_cache}" = "yes" ]
	then
		if [ -d "${output_dir_base}/cache/" ]
		then
			### XBMC
			if [ -e "${output_dir_base}/cache/${xbmc_git_tarball}" ]
			then
				fn_log_echo "Using xbmc_git tarball '${output_dir_base}/cache/${xbmc_git_tarball}' from cache."
				tar_all extract "${output_dir_base}/cache/${xbmc_git_tarball}" "${qemu_mnt_dir}/root/"
				cd ${qemu_mnt_dir}/root/xbmca10 && git pull
			else
				fn_log_echo "No xbmc git tarball found in cache. Creating one now!"
				get_n_check_file "${xbmc_git}" "xbmc" "${qemu_mnt_dir}/root/"
				if [ "$?" = "0" ]
				then
					cd ${qemu_mnt_dir}/root/ && tar_all compress "${output_dir_base}/cache/${xbmc_git_tarball}" ./xbmca10
				else
					fn_log_echo "ERROR! Something seems to have gone wrong while trying to get 'xbmc' via git."
				fi
			fi
		else
			fn_log_echo "ERROR! Cache directory '${output_dir_base}/cache/' does not seem to exist. Please check
Exiting now!"
			exit 99
		fi
	else
		fn_log_echo "Not using cache, according to the settings. Thus running git clone without creating a tarball."
		get_n_check_file "${xbmc_git}" "xbmc" "${qemu_mnt_dir}/root/"
	fi
fi


sleep 3

umount_img all
if [ "$?" = "0" ]
then
	fn_log_echo "Filesystem image file successfully unmounted. Ready to continue."
else
	fn_log_echo "Error while trying to unmount the filesystem image. Exiting now!"
	exit 22
fi

sleep 5

mount |grep "${qemu_mnt_dir}" > /dev/null
if [ ! "$?" = "0" ]
then
	fn_log_echo "Starting the qemu environment now!"
	###qemu-system-arm -M realview-pb-a8 -cpu cortex-a8 -smp ${qemu_nr_cpus} -rtc base=localtime,clock=host -no-reboot -serial stdio -kernel ${output_dir}/qemu-kernel/zImage -drive file=${output_dir}/${output_filename}.img,if=sd,cache=writeback -m 512 -append "root=/dev/mmcblk0 rw rootfstype=ext4 mem=512M devtmpfs.mount=0 ip=dhcp" 2>qemu_error_log.txt # TODO: Image name
	qemu-system-arm -M realview-pb-a8 -cpu cortex-a8 -rtc base=localtime,clock=host -no-reboot -serial stdio -kernel ${output_dir}/qemu-kernel/zImage -drive file=${output_dir}/${output_filename}.img,if=sd,cache=writeback -m 512 -append "root=/dev/mmcblk0 rw rootfstype=ext4 mem=512M devtmpfs.mount=0 ip=dhcp" 2>qemu_error_log.txt # TODO: Image name

else
	fn_log_echo "ERROR! Filesystem is still mounted. Can't run qemu!"
	exit 23
fi

fn_log_echo "Additional chroot system configuration successfully finished!"

}


# Description: Compress the resulting rootfs
compress_debian_rootfs()
{
fn_log_echo "Compressing the rootfs now!"

mount |grep ${output_dir}/${output_filename}.img 2>/dev/null
if [ ! "$?" = "0" ]
then 
	fsck.ext4 -fy ${output_dir}/${output_filename}.img
	if [ "$?" = "0" ]
	then
		fn_log_echo "Temporary filesystem checked out, OK!"
	else
		fn_log_echo "ERROR: State of Temporary filesystem is NOT OK! Exiting now."
		regular_cleanup
		exit 24
	fi
else
	fn_log_echo "ERROR: Image file still mounted. Exiting now!"
	regular_cleanup
	exit 25
fi

mount ${output_dir}/${output_filename}.img ${qemu_mnt_dir} -o loop
if [ "$?" = "0" ]
then
	rm -r ${qemu_mnt_dir}/lib/modules/*-cortexa8-qemu-*/
	cd ${qemu_mnt_dir}
	if [ "${tar_format}" = "bz2" ]
	then
		tar_all compress "${output_dir}/${output_filename}.tar.${tar_format}" .
	elif [ "${tar_format}" = "gz" ]
	then
		tar_all compress "${output_dir}/${output_filename}.tar.${tar_format}" .
	else
		fn_log_echo "Incorrect setting '${tar_format}' for the variable 'tar_format' in the general_settings.sh.
Please check! Only valid entries are 'bz2' or 'gz'. Could not compress the Rootfs!"
	fi

	cd ${output_dir}
	sleep 5
else
	fn_log_echo "ERROR: Image file could not be remounted correctly. Exiting now!"
	regular_cleanup
	exit 26
fi

umount ${qemu_mnt_dir}
sleep 10
mount | grep ${qemu_mnt_dir} > /dev/null
if [ ! "$?" = "0" ] && [ "${clean_tmp_files}" = "yes" ]
then
	rm -r ${qemu_mnt_dir}
	rm -r ${output_dir}/qemu-kernel
	rm ${output_dir}/${output_filename}.img
elif [ "$?" = "0" ] && [ "${clean_tmp_files}" = "yes" ]
then
	fn_log_echo "Directory '${qemu_mnt_dir}' is still mounted, so it can't be removed. Exiting now!"
	regular_cleanup
	exit 27
elif [ "$?" = "0" ] && [ "${clean_tmp_files}" = "no" ]
then
	fn_log_echo "Directory '${qemu_mnt_dir}' is still mounted, please check. Exiting now!"
	regular_cleanup
	exit 28
fi

fn_log_echo "Rootfs successfully DONE!"
}


# Description: Get the SD-card device and than create the partitions and format them
partition_n_format_disk()
{
device=""
echo "Now listing all available devices:
"

while [ -z "${device}" ]
do
parted -l

echo "
Please enter the name of the SD-card device (eg. /dev/sdb) OR press ENTER to refresh the device list:"

read device
if [ -e ${device} ] &&  [ "${device:0:5}" = "/dev/" ]
then
	umount ${device}*
	mount |grep ${device}
	if [ ! "$?" = "0" ]
	then
		echo "${device} partition table:"
		parted -s ${device} unit MB print
		echo "If you are sure that you want to repartition device '${device}', then type 'yes'.
Type anything else and/or hit Enter to cancel!"
		read affirmation
		if [ "${affirmation}" = "yes" ]
		then
			if [ ! -z "${size_boot_partition}" ] && [ ! -z "${size_swap_partition}" ]
			then
				fn_log_echo "SD-card device set to '${device}', according to user input."
				parted -s ${device} mklabel msdos
				if [ ! -z "${size_wear_leveling_spare}" ]
				then
					# first partition = boot (raw, size = ${size_boot_partition} )
					parted -s --align=opt -- ${device} unit MiB mkpart primary fat16 1 ${size_boot_partition}
					# second partition = root (rest of the drive size)
					parted --align=opt -- ${device} unit MiB mkpart primary ext4 ${size_boot_partition} -`expr ${size_swap_partition} + ${size_wear_leveling_spare}`
					# last partition = swap (swap, size = ${size_swap_partition} )
					parted -s --align=opt -- ${device} unit MiB mkpart primary linux-swap -`expr ${size_swap_partition} + ${size_wear_leveling_spare}` -${size_wear_leveling_spare} 
				else
					# first partition = boot (raw, size = ${size_boot_partition} )
					parted -s --align=opt -- ${device} unit MiB mkpart primary fat16 1 ${size_boot_partition}
					# second partition = root (rest of the drive size)
					parted --align=opt -- ${device} unit MiB mkpart primary ext4 ${size_boot_partition} -${size_swap_partition}
					# last partition = swap (swap, size = ${size_swap_partition} )
					parted -s --align=opt -- ${device} unit MiB mkpart primary linux-swap -${size_swap_partition} -0 
				fi
				echo ">>> ${device} Partition table is now:"
				parted -s ${device} unit MiB print
			else
				fn_log_echo "ERROR! Either the setting for 'size_boot_partition', or for 'size_swap_partition' seems to be empty.
Exiting now!"
				regular_cleanup
				exit 29
			fi
		else
			fn_log_echo "Action canceled by user. Exiting now!"
			regular_cleanup
			exit 29
		fi
	else
		fn_log_echo "ERROR! Some partition on device '${device}' is still mounted. Exiting now!"
		regular_cleanup
		exit 30
	fi
else
	if [ ! -z "${device}" ] # in case of a refresh we don't want to see the error message ;-)
	then 
		fn_log_echo "ERROR! Device '${device}' doesn't seem to be a valid device!"
	fi
	device=""
fi

done

if [ -e ${device}1 ] && [ -e ${device}2 ] && [ -e ${device}3 ]
then
	mkfs.vfat ${device}1 # vfat on boot partition
	mkfs.ext4 ${device}2 # ext4 on root partition
	mkswap ${device}3 # swap
else
	fn_log_echo "ERROR: There should be 3 partitions on '${device}', but one or more seem to be missing.
Exiting now!"
	regular_cleanup
	exit 31
fi

sleep 1
partprobe
}



# Description: Copy bootloader, rootfs and kernel to the SD-card and then unmount it
finalize_disk()
{
# Copy bootloader to the boot partition
fn_log_echo "Getting the bootloader and trying to copy it to the boot partition, now!"

get_n_check_file "${bootloader_bin_1}" "bootloader_binary_1" "${output_dir}/tmp"
get_n_check_file "${bootloader_bin_2}" "bootloader_binary_2" "${output_dir}/tmp"
get_n_check_file "${bootloader_script}" "bootloader_script" "${output_dir}/tmp"

if [ -e ${device} ] &&  [ "${device:0:5}" = "/dev/" ]
then
	umount ${device}*
	mount |grep ${device}
	if [ ! "$?" = "0" ]
	then
		if [ -e "${output_dir}/tmp/${bootloader_bin_1##*/}" ] # sunxi-spl.bin
		then
			dd if=${output_dir}/tmp/${bootloader_bin_1##*/} of=${device} bs=1024 seek=8
			if [ "$?" = "0" ]
			then
				fn_log_echo "Bootloader part 1 successfully copied to SD-card ('${device}')!"
			else
				fn_log_echo "ERROR while trying to copy the bootloader part 1 '${bootloader_bin_1}' to the device '${device}2'."
			fi
		else
			fn_log_echo "ERROR! Bootloader binary '${bootloader_bin_1##*/}' doesn't seem to exist in directory '${output_dir}/tmp/'.
			You won't be able to boot the card, without copying the file to the second partition."
		fi

		if [ -e "${output_dir}/tmp/${bootloader_bin_2##*/}" ] # u-boot.bin
		then
			dd if=${output_dir}/tmp/${bootloader_bin_2##*/} of=${device} bs=1024 seek=32
			if [ "$?" = "0" ]
			then
				fn_log_echo "Bootloader part 2 successfully copied to SD-card ('${device}')!"
			else
				fn_log_echo "ERROR while trying to copy the bootloader part 2 '${bootloader_bin_2}' to the device '${device}2'."
			fi
		else
			fn_log_echo "ERROR! Bootloader binary '${bootloader_bin_2##*/}' doesn't seem to exist in directory '${output_dir}/tmp/'.
			You won't be able to boot the card, without copying the file to the second partition."
		fi
	else
		fn_log_echo "ERROR! Some partition on device '${device}' is still mounted. Exiting now!"
	fi
else
	fn_log_echo "ERROR! Device '${device}' doesn't seem to exist!
	Exiting now"
	regular_cleanup
	exit 33
fi

# unpack the filesystem and kernel to the root partition

fn_log_echo "Now unpacking the rootfs to the SD-card's root partition!"

mkdir ${output_dir}/sd-card
mkdir ${output_dir}/sd-card/boot
mkdir ${output_dir}/sd-card/root
if [ "$?" = "0" ]
then
	fsck -fy ${device}1 # just to be sure
	fsck -fy ${device}2 # just to be sure
	mount ${device}1 ${output_dir}/sd-card/boot # TODO: check for mount error for this one, too!
	mount ${device}2 ${output_dir}/sd-card/root
	if [ "$?" = "0" ]
	then
		if [ -e ${output_dir}/${output_filename}.tar.${tar_format} ]
		then 
			tar_all extract "${output_dir}/${output_filename}.tar.${tar_format}" "${output_dir}/sd-card/root"
			mv ${output_dir}/sd-card/root/uImage ${output_dir}/sd-card/boot/ 
			cp ${output_dir}/tmp/${bootloader_script##*/} ${output_dir}/sd-card/boot/
			cp ${output_dir}/tmp/${bootloader_script##*/} ${output_dir}/sd-card/boot/evb.bin
		else
			fn_log_echo "ERROR: File '${output_dir}/${output_filename}.tar.${tar_format}' doesn't seem to exist. Exiting now!"
			regular_cleanup
			exit 34
		fi
		sleep 1
	else
		fn_log_echo "ERROR while trying to mount '${device}2' to '${output_dir}/sd-card'. Exiting now!"
		regular_cleanup
		exit 35
	fi
else
	fn_log_echo "ERROR while trying to create the temporary directory '${output_dir}/sd-card'. Exiting now!"
	regular_cleanup
	exit 36
fi

sleep 3
fn_log_echo "Unmounting the SD-card now."
umount ${output_dir}/sd-card/root
umount ${output_dir}/sd-card/boot

sleep 3
fn_log_echo "Running fsck to make sure the filesystem on the card is fine."
fsck -fy ${device}1 # final check
fsck -fy ${device}2 # final check
if [ "$?" = "0" ]
then
	fn_log_echo "SD-card successfully created!
You can remove the card now and try it in your Allwinner A10 based board.
ALL DONE!"

else
	fn_log_echo "ERROR! Filesystem check on your card returned an error status. Maybe your card is going bad, or something else went wrong."
fi

rm -r ${output_dir}/tmp
rm -r ${output_dir}/sd-card
}



#############################
##### HELPER Functions: #####
#############################


# Description: Helper funtion for all tar-related tasks
tar_all()
{
if [ "$1" = "compress" ]
then
	if [ -d "${2%/*}"  ] && [ -e "${3}" ]
	then
		if [ "${2:(-8)}" = ".tar.bz2" ] || [ "${2:(-5)}" = ".tbz2" ]
		then
			tar -cpjvf "${2}" "${3}"
		elif [ "${2:(-7)}" = ".tar.gz" ] || [ "${2:(-4)}" = ".tgz" ]
		then
			tar -cpzvf "${2}" "${3}"
		else
			fn_log_echo "ERROR! Created files can only be of type '.tar.gz', '.tgz', '.tbz2', or '.tar.bz2'! Exiting now!"
			regular_cleanup
			exit 37
		fi
	else
		fn_log_echo "ERROR! Illegal arguments '$2' and/or '$3'. Exiting now!"
		regular_cleanup
		exit 38
	fi
elif [ "$1" = "extract" ]
then
	if [ -e "${2}"  ] && [ -d "${3}" ]
	then
		if [ "${2:(-8)}" = ".tar.bz2" ] || [ "${2:(-5)}" = ".tbz2" ]
		then
			tar -xpjvf "${2}" -C "${3}"
		elif [ "${2:(-7)}" = ".tar.gz" ] || [ "${2:(-4)}" = ".tgz" ]
		then
			tar -xpzvf "${2}" -C "${3}"
		else
			fn_log_echo "ERROR! Can only extract files of type '.tar.gz', or '.tar.bz2'!
'${2}' doesn't seem to fit that requirement. Exiting now!"
			regular_cleanup
			exit 39
		fi
	else
		fn_log_echo "ERROR! Illegal arguments '$2' and/or '$3'. Exiting now!"
		regular_cleanup
		exit 40
	fi
else
	fn_log_echo "ERROR! The first parameter needs to be either 'compress' or 'extract', and not '$1'. Exiting now!"
	regular_cleanup
	exit 41
fi
}


# Description: Helper function to completely or partially unmount the image file when and where needed
umount_img()
{
cd ${output_dir}
if [ "${1}" = "sys" ]
then
	mount | grep "${output_dir}" > /dev/null
	if [ "$?" = "0"  ]
	then
		fn_log_echo "Virtual Image still mounted. Trying to umount now!"
		umount ${qemu_mnt_dir}/proc > /dev/null
		sleep 3
		umount ${qemu_mnt_dir}/dev/pts > /dev/null
		sleep 3
		umount ${qemu_mnt_dir}/dev/ > /dev/null
		sleep 3
		umount ${qemu_mnt_dir}/sys > /dev/null
		sleep 3
	fi

	mount | egrep '(${qemu_mnt_dir}/sys|${qemu_mnt_dir}/proc|${qemu_mnt_dir}/dev/pts)' > /dev/null
	if [ "$?" = "0"  ]
	then
		fn_log_echo "ERROR! Something went wrong. All subdirectories of '${output_dir}' should have been unmounted, but are not."
	else
		fn_log_echo "Virtual image successfully unmounted."
	fi
elif [ "${1}" = "all" ]
then
	mount | grep "${output_dir}" > /dev/null
	if [ "$?" = "0"  ]
	then
		fn_log_echo "Virtual Image still mounted. Trying to umount now!"
		umount ${qemu_mnt_dir}/proc > /dev/null
		sleep 3
		umount ${qemu_mnt_dir}/dev/pts > /dev/null
		sleep 3
		umount ${qemu_mnt_dir}/dev/ > /dev/null
		sleep 3
		umount ${qemu_mnt_dir}/sys > /dev/null
		sleep 3
		umount ${qemu_mnt_dir}/ > /dev/null
		sleep 3
	fi

	mount | grep "${output_dir}" > /dev/null
	if [ "$?" = "0"  ]
	then
		fn_log_echo "ERROR! Something went wrong. '${output_dir}' should have been unmounted, but isn't."
	else
		fn_log_echo "Virtual image successfully unmounted."
	fi
else
	fn_log_echo "ERROR! Wrong parameter. Only 'sys' and 'all' allowed when calling 'umount_img'."
fi
cd ${output_dir}
}


# Description: Helper function to search and replace strings (also works on strings containing special characters!) in files
sed_search_n_replace()
{
if [ ! -z "${1}" ] && [ ! -z "${3}" ] && [ -e "${3}" ]
then
	original=${1}
	replacement=${2}
	file=${3}

	escaped_original=$(printf %s "${original}" | sed -e 's![.\[^$*/]!\\&!g')

	escaped_replacement=$(printf %s "${replacement}" | sed -e 's![\&]!\\&!g')

	sed -i -e "s~${escaped_original}~${escaped_replacement}~g" ${file}
else
	fn_log_echo "ERROR! Trying to call the function 'sed_search_n_replace' with (a) wrong parameter(s). The following was used:
'Param1='${1}'
Param2='${2}'
Param3='${3}'"
fi
sleep 1
grep -F "${replacement}" "${file}" > /dev/null

if [ "$?" = "0" ]
then
	fn_log_echo "String '${original}' was successfully replaced in file '${file}'."
else
	fn_log_echo "ERROR! String '${original}' could not be replaced in file '${file}'!"
fi

}


# Description: Helper function to get (download via wget or git, or link locally) and check any file needed for the build process
get_n_check_file()
{
file_path=${1%/*}
file_name=${1##*/}
short_description=${2}
output_path=${3}

if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
then
	fn_log_echo "ERROR: Function get_n_check_file needs 3 parameters.
Parameter 1 is file_path/file_name, parameter 2 is short_description and parameter 3 is output-path.
Faulty parameters passed were '${1}', '${2}' and '${3}'.
One or more of these appear to be empty. Exiting now!" 
	regular_cleanup
	exit 42
fi

if [ "${file_path:0:7}" = "http://" ] || [ "${file_path:0:8}" = "https://" ] || [ "${file_path:0:6}" = "ftp://" ] || [ "${file_path:0:6}" = "git://" ] || [ "${file_path:0:3}" = "-b " ] 
then
	check_connectivity
	if [ -d ${output_path} ]
	then
		cd ${output_path}
		if [ "${1:(-4):4}" = ".git" ]
		then
			fn_log_echo "Trying to clone repository ${short_description} from address '${1}', now."
			success=0
			for i in {1..10}
			do
				if [ "$i" = "1" ]
				then
					git clone ${1}
				else
					if [ -d ./${file_name%.git} ]
					then
						rm -rf ./${file_name%.git}
					fi
					git clone ${1}
				fi
				if [ "$?" = "0" ]
				then
					success=1
					break
				fi
			done
			if [ "$success" = "1" ]
			then
				fn_log_echo "'${short_description}' repository successfully cloned from address '${1}'."
			else
				fn_log_echo "ERROR: Repository '${1}' could not be cloned.
Exiting now!"
				regular_cleanup
				exit 42
			fi
		else
			fn_log_echo "Trying to download ${short_description} from address '${file_path}/${file_name}', now."
			wget -q --spider ${file_path}/${file_name}
			if [ "$?" = "0" ]
			then
				wget -t 3 ${file_path}/${file_name}
				if [ "$?" = "0" ]
				then
					fn_log_echo "'${short_description}' successfully downloaded from address '${file_path}/${file_name}'."
				else
					fn_log_echo "ERROR: File '${file_path}/${file_name}' could not be downloaded.
Exiting now!"
					regular_cleanup
					exit 43
				fi
			else
				fn_log_echo "ERROR: '${file_path}/${file_name}' does not seem to be a valid internet address. Please check!
Exiting now!"
				regular_cleanup
				exit 44
			fi
		fi
	else
		fn_log_echo "ERROR: Output directory '${output_path}' does not seem to exist. Please check!
	Exiting now!"
			regular_cleanup
			exit 45
	fi
else
	fn_log_echo "Looking for the ${short_description} locally (offline)."	
	if [ -d ${file_path} ]
	then
		if [ -e ${file_path}/${file_name} ]
		then
			fn_log_echo "File is a local file '${file_path}/${file_name}', so it stays where it is."
			ln -s ${file_path}/${file_name} ${output_path}/${file_name}
		else
			fn_log_echo "ERROR: File '${file_name}' does not seem to be a valid file in existing directory '${file_path}'.Exiting now!"
			regular_cleanup
			exit 47
		fi
	else
		fn_log_echo "ERROR: Folder '${file_path}' does not seem to exist as a local directory. Exiting now!"
		regular_cleanup
		exit 48
	fi
fi
cd ${output_dir}
}


# Description: Helper function to help with installing packages via apt. Without this, one wrong entry in the package list leads to the whole list being discarded. With it, apt gets called for each package alone, which only leads to an error if one package can't be installed.
apt_get_helper()
{
apt_choice=${1}
if [ "${apt_choice}" = "write_script" ]
then
	fn_log_echo "Writing the 'apt_helper.sh' helper script for the apt install processes."
	cat<<END>${qemu_mnt_dir}/apt_helper.sh
#!/bin/bash
# helper script to install a list of packages, even if one or more errors occur

apt_get_helper()
{
apt_choice=\${1}
package_list=\${2}
update_choice=\${3}

	if [ "\${apt_choice}" = "download" ]
	then
		apt-get install -y -d \${2} 2>>/apt_get_errors.txt
	elif [ "\${apt_choice}" = "install" ]
	then
		apt-get install -y \${2} 2>>/apt_get_errors.txt
	elif [ "\${apt_choice}" = "dep_download" ]
	then
		apt-get build-dep -y -d \${2} 2>>/apt_get_errors.txt
	elif [ "\${apt_choice}" = "dep_install" ]
	then
		apt-get build-dep -y \${2} 2>>/apt_get_errors.txt
	fi
	if [ "\$?" = "0" ]
	then
		echo "Packages '\${2}' \${apt_choice}ed successfully!"
	else
		set -- \${package_list}

		while [ \$# -gt 0 ]
		do
			if [ "\${update_choice}" = "upd" ] && [ ! "\${apt_get_update_done}" = "true" ]
			then
				apt-get update
				apt_get_update_done="true"
			fi
			if [ "\${apt_choice}" = "download" ]
			then
				apt-get install -y -d \${1} 2>>/apt_get_errors.txt
			elif [ "\${apt_choice}" = "install" ]
			then
				apt-get install -y \${1} 2>>/apt_get_errors.txt
			elif [ "\${apt_choice}" = "dep_download" ]
			then
				apt-get build-dep -y -d \${1} 2>>/apt_get_errors.txt
			elif [ "\${apt_choice}" = "dep_install" ]
			then
				apt-get build_dep -y \${1} 2>>/apt_get_errors.txt
			fi
			if [ "\$?" = "0" ]
			then
				echo "'\${1}' \${apt_choice}ed successfully!"
			else
				echo "ERROR while trying to \${apt_choice} '\${1}'."
			fi

			shift
		done
	fi
}
END
elif [ "${apt_choice}" = "download" ] || [ "${apt_choice}" = "install" ]
then
	package_list=${2}
	update_choice=${3}

	if [ "${apt_choice}" = "download" ]
	then
		apt-get install -y -d ${2} 2>>${output_dir}/apt_get_errors.txt
	elif [ "${apt_choice}" = "install" ]
	then
		apt-get install -y ${2} 2>>${output_dir}/apt_get_errors.txt
	elif [ "\${apt_choice}" = "dep_download" ]
	then
		apt-get build-dep -y -d \${2} 2>>${output_dir}/apt_get_errors.txt
	elif [ "\${apt_choice}" = "dep_install" ]
	then
		apt-get build-dep -y \${2} 2>>${output_dir}/apt_get_errors.txt
	fi
	if [ "$?" = "0" ]
	then
		fn_log_echo "List of packages '${2}' ${apt_choice}ed successfully!"
	else
		set -- ${package_list}

		while [ $# -gt 0 ]
		do
			if [ "${update_choice}" = "upd" ] && [ ! "${apt_get_update_done}" = "true" ]
			then
				apt-get update
				apt_get_update_done="true"
			fi
			if [ "${apt_choice}" = "download" ]
			then
				apt-get install -y -d ${1} 2>>${output_dir}/apt_get_errors.txt
			elif [ "${apt_choice}" = "install" ]
			then
				apt-get install -y ${1} 2>>${output_dir}/apt_get_errors.txt
			elif [ "\${apt_choice}" = "dep_download" ]
			then
				apt-get build-dep -y -d \${1} 2>>${output_dir}/apt_get_errors.txt
			elif [ "\${apt_choice}" = "dep_install" ]
			then
				apt-get build_dep -y \${1} 2>>${output_dir}/apt_get_errors.txt
			fi
			if [ "$?" = "0" ]
			then
				fn_log_echo "'${1}' ${apt_choice}ed successfully!"
			else
				fn_log_echo "ERROR while trying to ${apt_choice} '${1}'."
			fi

			shift
		done
	fi
else
	fn_log_echo "ERROR: Parameter 1 should either be 'write_script' or 'download' or 'install'.
	Invalid parameter '${apt_choice}' passed to function. Exiting now!"
	exit 91
fi
}



# Description: Helper function to clean up in case of an interrupt
int_cleanup() # special treatment for script abort through interrupt ('ctrl-c'  keypress, etc.)
{
	fn_log_echo "Build process interrupted. Now trying to clean up!"
	umount_img all 2>/dev/null
	rm -r ${qemu_mnt_dir} 2>/dev/null
	rm -r ${output_dir}/tmp 2>/dev/null
	rm -r ${output_dir}/sd-card 2>/dev/null
	exit 99
}

# Description: Helper function to clean up in case of an error
regular_cleanup() # cleanup for all other error situations
{
	umount_img all 2>/dev/null
	rm -r ${qemu_mnt_dir} 2>/dev/null
	rm -r ${output_dir}/tmp 2>/dev/null
	rm -r ${output_dir}/sd-card 2>/dev/null
}
