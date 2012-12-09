#!/bin/bash
# Bash script that creates a Debian rootfs or even a complete SD memory card for the Hackberry board
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
fn_my_echo()
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


# Description: See if the needed packages are installed and if the versions are sufficient
check_n_install_prerequisites()
{
fn_my_echo "Installing some packages, if needed."
if [ "${host_os}" = "Debian" ]
then
	apt_prerequisites=${apt_prerequisites_debian}
elif [ "${host_os}" = "Ubuntu" ]
then
	apt_prerequisites=${apt_prerequisites_ubuntu}
else
	fn_my_echo "OS-Type '${host_os}' not correct.
Please run 'build_debian_system.sh --help' for more information"
	exit 12
fi

fn_my_echo "Running 'apt-get update' to get the latest package dependencies."
if [ "$?" = "0" ]
then
	fn_my_echo "'apt-get update' ran successfully! Continuing..."
else
	fn_my_echo "ERROR while trying to run 'apt-get update'. Exiting now."
	exit 13
fi

set -- ${apt_prerequisites}

while [ $# -gt 0 ]
do
	dpkg -l |grep "ii  ${1}" >/dev/null
	if [ "$?" = "0" ]
	then
		fn_my_echo "Package '${1}' is already installed. Nothing to be done."
	else
		fn_my_echo "Package '${1}' is not installed yet.
Trying to install it now!"
		if [ ! "${apt_get_update_done}" = "true" ]
		then
			apt-get update
			apt_get_update_done="true"
		fi
		apt-get install -y ${1}
		if [ "$?" = "0" ]
		then
			fn_my_echo "'${1}' installed successfully!"
		else
			fn_my_echo "ERROR while trying to install '${1}'."
			if [ "${host_os}" = "Ubuntu" ] && [ "${1}" = "qemu-system" ]
			then
				fn_my_echo "Assuming that you are running this on Ubuntu 10.XX, where the package 'qemu-system' doesn't exist.
If your host system is not Ubuntu 10.XX based, this could lead to errors. Please check!"
			else
				fn_my_echo "Exiting now!"
				exit 14
			fi
		fi
	fi

	if [ $1 = "qemu-user-static" ]
	then
		sh -c "dpkg -l|grep "qemu-user-static"|grep "1."" >/dev/null
		if [ $? = "0" ]
		then
			fn_my_echo "Sufficient version of package '${1}' found. Continueing..."
		else
			fn_my_echo "The installed version of package '${1}' is too old.
You need to install a package with a version of at least 1.0.
For example from the debian-testing ('http://packages.debian.org/search?keywords=qemu&searchon=names&suite=testing&section=all')
respectively the Ubuntu precise ('http://packages.ubuntu.com/search?keywords=qemu&searchon=names&suite=precise&section=all') repositiories.
Exiting now!"
			exit 15
		fi
	fi
	shift
done

fn_my_echo "Function 'check_n_install_prerequisites' DONE."
}


# Description: Create a image file as root-device for the installation process
create_n_mount_temp_image_file()
{
fn_my_echo "Creating the temporary image file for the debootstrap process."
dd if=/dev/zero of=${output_dir}/${output_filename}.img bs=1M count=${work_image_size_MB}
if [ "$?" = "0" ]
then
	fn_my_echo "File '${output_dir}/${output_filename}.img' successfully created with a size of ${work_image_size_MB}MB."
else
	fn_my_echo "ERROR while trying to create the file '${output_dir}/${output_filename}.img'. Exiting now!"
	exit 16
fi

fn_my_echo "Formatting the image file with the ext4 filesystem."
mkfs.ext4 -F ${output_dir}/${output_filename}.img
if [ "$?" = "0" ]
then
	fn_my_echo "ext4 filesystem successfully created on '${output_dir}/${output_filename}.img'."
else
	fn_my_echo "ERROR while trying to create the ext4 filesystem on  '${output_dir}/${output_filename}.img'. Exiting now!"
	exit 17
fi

fn_my_echo "Creating the directory to mount the temporary filesystem."
mkdir -p ${output_dir}/mnt_debootstrap
if [ "$?" = "0" ]
then
	fn_my_echo "Directory '${output_dir}/mnt_debootstrap' successfully created."
else
	fn_my_echo "ERROR while trying to create the directory '${output_dir}/mnt_debootstrap'. Exiting now!"
	exit 18
fi

fn_my_echo "Now mounting the temporary filesystem."
mount ${output_dir}/${output_filename}.img ${output_dir}/mnt_debootstrap -o loop
if [ "$?" = "0" ]
then
	fn_my_echo "Filesystem correctly mounted on '${output_dir}/mnt_debootstrap'."
else
	fn_my_echo "ERROR while trying to mount the filesystem on '${output_dir}/mnt_debootstrap'. Exiting now!"
	exit 19
fi

fn_my_echo "Function 'create_n_mount_temp_image_file' DONE."
}


# Description: Run the debootstrap steps, like initial download, extraction plus configuration and setup
do_debootstrap()
{
fn_my_echo "Running first stage of debootstrap now."

if [ "${use_cache}" = "yes" ]
then
	if [ -d "${output_dir_base}/cache/" ]
	then
		if [ -e "${output_dir_base}/cache/${base_sys_cache_tarball}" ]
		then
			fn_my_echo "Using debian debootstrap tarball '${output_dir_base}/cache/${base_sys_cache_tarball}' from cache."
			debootstrap --foreign --unpack-tarball="${output_dir_base}/cache/${base_sys_cache_tarball}" --include=${deb_add_packages} --verbose --arch=armhf --variant=minbase "${debian_target_version}" "${output_dir}/mnt_debootstrap/" "http://ftp.de.debian.org/debian/"
		else
			fn_my_echo "No debian debootstrap tarball found in cache. Creating one now!"
			debootstrap --foreign --make-tarball="${output_dir_base}/cache/${base_sys_cache_tarball}" --include=${deb_add_packages} --verbose --arch=armhf --variant=minbase "${debian_target_version}" "${output_dir_base}/cache/tmp/" "http://ftp.de.debian.org/debian/"
			sleep 3
			debootstrap --foreign --unpack-tarball="${output_dir_base}/cache/${base_sys_cache_tarball}" --include=${deb_add_packages} --verbose --arch=armhf --variant=minbase "${debian_target_version}" "${output_dir}/mnt_debootstrap/" "http://ftp.de.debian.org/debian/"
		fi
	fi
else
	fn_my_echo "Not using cache, according to the settings. Thus running debootstrap without creating a tarball."
	debootstrap --include=${deb_add_packages} --verbose --arch armhf --variant=minbase --foreign "${debian_target_version}" "${output_dir}/mnt_debootstrap" "${debian_mirror_url}"
fi

modprobe binfmt_misc

cp /usr/bin/qemu-arm-static ${output_dir}/mnt_debootstrap/usr/bin

mkdir -p ${output_dir}/mnt_debootstrap/dev/pts

fn_my_echo "Mounting both /dev/pts and /proc on the temporary filesystem."
mount devpts ${output_dir}/mnt_debootstrap/dev/pts -t devpts
mount -t proc proc ${output_dir}/mnt_debootstrap/proc

fn_my_echo "Entering chroot environment NOW!"

apt_get_helper "write_script"

fn_my_echo "Starting the second stage of debootstrap now."
echo "#!/bin/bash
/debootstrap/debootstrap --second-stage 2>>/deboostrap_stg2_errors.txt
cd /root 2>>/deboostrap_stg2_errors.txt
cat <<END > /etc/apt/sources.list 2>>/deboostrap_stg2_errors.txt
deb http://ftp.de.debian.org/debian ${debian_target_version} main contrib non-free
deb-src http://ftp.de.debian.org/debian ${debian_target_version} main contrib non-free
deb http://ftp.debian.org/debian/ ${debian_target_version}-updates main contrib non-free
deb-src http://ftp.debian.org/debian/ ${debian_target_version}-updates main contrib non-free
deb http://security.debian.org/ ${debian_target_version}/updates main contrib non-free
deb-src http://security.debian.org/ ${debian_target_version}/updates main contrib non-free
END

apt-get update

mknod /dev/ttyS0 c 4 64	# for the serial console

cat <<END > /etc/network/interfaces
auto lo eth0
iface lo inet loopback
iface eth0 inet dhcp
END

echo A10-debian > /etc/hostname 2>>/deboostrap_stg2_errors.txt

echo \"127.0.0.1 localhost\" >> /etc/hosts 2>>/deboostrap_stg2_errors.txt
echo \"127.0.0.1 A10-debian\" >> /etc/hosts 2>>/deboostrap_stg2_errors.txt
echo \"nameserver ${nameserver_addr}\" > /etc/resolv.conf 2>>/deboostrap_stg2_errors.txt

cat <<END > /etc/rc.local 2>>/deboostrap_stg2_errors.txt
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
	/zram_setup.sh 2>>/zram_setup_log.txt && rm /zram_setup.sh
fi

/post_debootstrap_setup.sh 2>>/setup_log.txt && rm /post_debootstrap_setup.sh

exit 0
END
rm /debootstrap_pt1.sh
exit" > ${output_dir}/mnt_debootstrap/debootstrap_pt1.sh
chmod +x ${output_dir}/mnt_debootstrap/debootstrap_pt1.sh
/usr/sbin/chroot ${output_dir}/mnt_debootstrap /bin/bash /debootstrap_pt1.sh 2>${output_dir}/debootstrap_pt1_errors.txt

if [ "$?" = "0" ]
then
	fn_my_echo "First part of chroot operations done successfully!"
else
	fn_my_echo "Errors while trying to run the first part of the chroot operations."
fi


if [ "${use_cache}" = "yes" ]
then
	if [ -e ${output_dir_base}/cache/additional_packages.tar.gz ]
	then
		if [ ! "${mali_graphics_choice}" = "copy" ] && [ ! "${mali_graphics_choice}" = "build" ] 
		then
			fn_my_echo "Extracting the additional packages 'additional_packages.tar.gz' from cache. now."
			tar_all extract "${output_dir_base}/cache/additional_packages.tar.gz" "${output_dir}/mnt_debootstrap/var/cache/apt/" 
		fi
	elif [ ! -e "${output_dir}/cache/additional_packages.tar.gz" ]
	then
		add_pack_create="yes"
	fi
	
	if [ -e ${output_dir_base}/cache/additional_desktop_packages.tar.gz ] && [ "${mali_graphics_choice}" = "copy" ]
	then
		fn_my_echo "Extracting the additional desktop packages 'additional_desktop_packages.tar.gz' from cache. now."
		tar_all extract "${output_dir_base}/cache/additional_desktop_packages.tar.gz" "${output_dir}/mnt_debootstrap/var/cache/apt/"
	elif [ ! -e "${output_dir}/cache/additional_desktop_packages.tar.gz" ] && [ ! "${mali_graphics_choice}" = "copy" ]
	then
		add_desk_pack_create="yes"
	fi
	
	if [ -e ${output_dir_base}/cache/additional_dev_packages.tar.gz ] && [ "${mali_graphics_choice}" = "build" ]
	then
		fn_my_echo "Extracting the additional dev packages 'additional_dev_packages.tar.gz' from cache. now."
		tar_all extract "${output_dir_base}/cache/additional_dev_packages.tar.gz" "${output_dir}/mnt_debootstrap/var/cache/apt/"
	elif [ ! -e "${output_dir}/cache/additional_dev_packages.tar.gz" ] && [ "${mali_graphics_choice}" = "build" ]
	then
		add_dev_pack_create="yes"
	fi
fi

	
mount devpts ${output_dir}/mnt_debootstrap/dev/pts -t devpts
mount -t proc proc ${output_dir}/mnt_debootstrap/proc

echo "#!/bin/bash
source apt_helper.sh
export LANG=C 2>>/deboostrap_stg2_errors.txt
#apt_get_helper \"install\" \"${base_packages_1}\" upd

sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen 2>>/deboostrap_stg2_errors.txt	# enable locale
#sed -i 's/# en_US.ISO-8859-1/en_US.ISO-8859-1/g' /etc/locale.gen 2>>/deboostrap_stg2_errors.txt	# enable locale
#sed -i 's/# en_US.ISO-8859-1 ISO-8859-1/en_US.ISO-8859-1 ISO-8859-1/g' /etc/locale.gen 2>>/deboostrap_stg2_errors.txt	# enable locale
#sed -i 's/# de_DE.ISO-8859-1/de_DE.ISO-8859-1/g' /etc/locale.gen 2>>/deboostrap_stg2_errors.txt	# enable locale
sed -i 's/# de_DE.UTF-8/de_DE.UTF-8/g' /etc/locale.gen 2>>/deboostrap_stg2_errors.txt	# enable locale
#sed -i 's/# de_DE@euro ISO-8859-1/# de_DE@euro ISO-8859-1/g' /etc/locale.gen 2>>/deboostrap_stg2_errors.txt	# enable locale

locale-gen 2>>/deboostrap_stg2_errors.txt

export LANG=${std_locale} 2>>/deboostrap_stg2_errors.txt	# language settings
export LC_ALL=${std_locale} 2>>/deboostrap_stg2_errors.txt
export LANGUAGE=${std_locale} 2>>/deboostrap_stg2_errors.txt

#apt_get_helper \"install\" \"${base_packages_2}\"

apt_get_helper \"download\" \"${additional_packages}\"

if [ \"${mali_graphics_choice}\" = \"copy\" ]
then
	apt_get_helper \"download\" \"${additional_desktop_packages}\"
elif [ \"${mali_graphics_choice}\" = \"build\" ]
then
	apt_get_helper \"download\" \"${additional_desktop_packages}\"
	apt_get_helper \"download\" \"${additional_dev_packages}\"
fi

cat <<END > /etc/fstab 2>>/deboostrap_stg2_errors.txt
# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/root	/	ext4	noatime,errors=remount-ro	0	1
/dev/mmcblk0p3	none	swap	defaults	0	0
END

echo 'T0:2345:respawn:/sbin/getty ttyS0 115200 vt102' >> /etc/inittab 2>>/deboostrap_stg2_errors.txt	# enable serial consoles
rm /debootstrap_pt2.sh
exit" > ${output_dir}/mnt_debootstrap/debootstrap_pt2.sh
chmod +x ${output_dir}/mnt_debootstrap/debootstrap_pt2.sh
/usr/sbin/chroot ${output_dir}/mnt_debootstrap /bin/bash /debootstrap_pt2.sh 2>${output_dir}/debootstrap_pt2_errors.txt

if [ "$?" = "0" ]
then
	fn_my_echo "Second part of chroot operations done successfully!"
else
	fn_my_echo "Errors while trying to run the second part of the chroot operations."
fi


fn_my_echo "Debug: add_pack_create='${add_pack_create}' ."
fn_my_echo "Debug: add_desk_pack_create='${add_desk_pack_create}' ."
fn_my_echo "Debug: add_dev_pack_create='${add_dev_pack_create}' ."
fn_my_echo "Debug: mali_graphics_choice='${mali_graphics_choice}' ."

if [ "${add_pack_create}" = "yes" ]
then
	if  [ ! "${mali_graphics_choice}" = "copy" ] && [ ! "${mali_graphics_choice}" = "build" ]   
	then
		fn_my_echo "Compress choice 1."
		cd ${output_dir}/mnt_debootstrap/var/cache/apt/
		tar_all compress "${output_dir_base}/cache/additional_packages.tar.gz" .
		cd ${output_dir}
	fi
fi

if [ "${add_dev_pack_create}" = "yes" ] && [ "${mali_graphics_choice}" = "build" ] # case of both desk- and dev-packages already downloaded into the /var/cache dir
then
	fn_my_echo "Compress choice 2."
	fn_my_echo "Trying to create cache archive for dev-packages (includes desktop-packages!)."
	cd ${output_dir}/mnt_debootstrap/var/cache/apt/
	tar_all compress "${output_dir_base}/cache/additional_dev_packages.tar.gz" .
	cd ${output_dir}
fi

if [ "${add_desk_pack_create}" = "yes" ] && [ "${mali_graphics_choice}" = "copy" ] # case of only desk-packages already downloaded into the /var/cache dir
then
	fn_my_echo "Compress choice 3."
	fn_my_echo "Trying to create cache archive for desktop-packages."
	cd ${output_dir}/mnt_debootstrap/var/cache/apt/
	tar_all compress "${output_dir_base}/cache/additional_desktop_packages.tar.gz" .
	cd ${output_dir}
#else
#	fn_my_echo "Can't create cache archive for this scenario."
fi

sleep 5
umount_img sys
fn_my_echo "Just exited chroot environment."
fn_my_echo "Base debootstrap steps 1&2 are DONE!"
}



# Description: Do some further configuration of the system, after debootstrap has finished
do_post_debootstrap_config()
{

fn_my_echo "Now starting the post-debootstrap configuration steps."

mkdir -p ${output_dir}/qemu-kernel

get_n_check_file "${std_kernel_pkg}" "standard_kernel" "${output_dir}/tmp"

get_n_check_file "${qemu_kernel_pkg}" "qemu_kernel" "${output_dir}/tmp"

tar_all extract "${output_dir}/tmp/${qemu_kernel_pkg##*/}" "${output_dir}/qemu-kernel"
sleep 3
tar_all extract "${output_dir}/tmp/${std_kernel_pkg##*/}" "${output_dir}/mnt_debootstrap"

if [ -d ${output_dir}/qemu-kernel/lib/ ]
then
	cp -ar ${output_dir}/qemu-kernel/lib/ ${output_dir}/mnt_debootstrap  # copy the qemu kernel modules intot the rootfs
fi

if [ "${use_zram}" = "yes" ]
then
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

modprobe ${zram_kernel_module_name} zram_num_devices=1
sleep 2
echo ${zram_size_B} > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0
exit 0
END

exit 0" > ${output_dir}/mnt_debootstrap/zram_setup.sh
chmod +x ${output_dir}/mnt_debootstrap/zram_setup.sh
fi

git_branch_name="${mali_xserver_2d_git##*.git -b }"
if [ ! -z "${git_branch_name}" ]
then
	xf86_version="${git_branch_name:0:4}"
	fn_my_echo "DEBUG: xf86_version='${xf86_version}' ."
else
	xf86_version="r3p0" # default value
	fn_my_echo "DEBUG: xf86_version='${xf86_version}' ."
fi

date_cur=`date` # needed further down as a very important part to circumvent the PAM Day0 change password problem

echo "#!/bin/bash
source apt_helper.sh
date -s \"${date_cur}\" 2>>/post_debootstrap_errors.txt	# set the system date to prevent PAM from exhibiting its nasty DAY0 forced password change

apt_get_helper \"install\" \"${additional_packages}\"
if [ \"${mali_graphics_choice}\" = \"copy\" ]
then
	apt_get_helper \"install\" \"${additional_desktop_packages}\"
elif [ \"${mali_graphics_choice}\" = \"build\" ]
then
	apt_get_helper \"install\" \"${additional_desktop_packages}\"
	apt_get_helper \"install\" \"${additional_dev_packages}\"
fi

#apt-get autoremove
apt-get clean
dpkg -l > /installed_packages.txt
ldconfig -v

if [ \"${i2c_hwclock}\" = \"yes\" ]; then update-rc.d -f i2c_hwclock.sh start 02 S . stop 07 0 6 . 2>>/post_debootstrap_errors.txt;fi;

if [ \"${use_zram}\" = \"yes\" ]; then echo vm.swappiness=${vm_swappiness} >> /etc/sysctl.conf; fi;

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
	cat << END > /etc/X11/xorg.conf
# X.Org X server configuration file for xfree86-video-mali
Section \"Device\"
        Identifier \"Mali FBDEV\"
        Driver  \"mali\"
        Option  \"fbdev\"            \"/dev/fb0\"
        Option  \"DRI\"             \"false\"
        Option  \"DRI2\"             \"false\"
        Option  \"DRI2\"             \"false\"
        Option  \"DRI2_PAGE_FLIP\"   \"false\"
        Option  \"DRI2_WAIT_VSYNC\"  \"false\"
	Option \"Debug\" \"true\"
EndSection
Section \"Module\"
	Disable \"dri\"
	Disable \"glx\"
EndSection
Section \"Monitor\"
	Identifier \"Monitor0\"
EndSection
Section \"Screen\"
        Identifier      \"Mali Screen\"
        Device          \"Mali FBDEV\"
        Monitor		\"Monitor0\"
		SubSection \"Display\"
			Viewport 0 0
			Depth	24
			# Modes	\"1920x1200\"
		EndSubSection
EndSection
Section \"DRI\"
        Mode 0666
EndSection
END
	if [ \"${mali_graphics_choice}\" = \"copy\" ]
	then
		echo \"Downloaded mali graphics driver. Driver should already work. Please check!\"
	elif [ \"${mali_graphics_choice}\" = \"build\" ]
	then
		echo \"Downloaded sources for mali graphics. Trying to compile the driver, now.\"
		cd /root/mali_2d_build 2>>/mali_drv_compile.txt
		if [ \"\${?}\" = \"0\" ]
		then
			echo \"Successfully changed into directory '/root/mali_2d_build'.\"
			cd /root/mali_2d_build/mali-libs 2>>/mali_drv_compile.txt
			if [ \"\${?}\" = \"0\" ]
			then
				echo \"Successfully changed into directory '/root/mali_2d_build/mali-libs/'.\"
				make VERSION=${xf86_version} ABI=armhf x11 2>>/mali_drv_compile.txt && xserver_build_log=\"1\" && echo \"Successfully ran the command 'make VERSION=${xf86_version} ABI=armhf x11'.\"
				make headers 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 2\" && echo \"Successfully ran 'make headers'.\"
				cp -rf ./lib/${xf86_version}/armhf/x11/*.so /usr/lib/ 2>>/mali_drv_compile.txt && echo \"Successfully copied the libraries from './lib/${xf86_version}/armhf/x11/' to '/usr/lib/'.\"
			fi
			cd /root/mali_2d_build/libdri2 2>>/mali_drv_compile.txt
			if [ \"\${?}\" = \"0\" ]
			then
				echo \"Successfully changed into directory '/root/mali_2d_build/libdri2/'.\"
				./autogen.sh 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 3\" && echo \"Successfully ran the 'autogen.sh' (libdri2) command.\"
				./configure --prefix=/usr --x-includes=/usr/include --x-libraries=/usr/lib 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 4\" && echo \"Successfully ran the configuration for libdri2.\"
				make 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 5\" && echo \"Successfully ran the 'make' (libdri2) command.\"
				make install 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 6\" && echo \"Successfully ran the 'make install' (libdri2) command.\"
			fi
			cd /root/mali_2d_build/libump 2>>/mali_drv_compile.txt
			if [ \"\${?}\" = \"0\" ]
			then
				echo \"Successfully changed into directory '/root/mali_2d_build/libump/'.\"
				mkdir /usr/include/ump 2>>/mali_drv_compile.txt && echo \"Successfully created the '/usr/include/ump' directory.\"
				cp -rf ./include/ump/* /usr/include/ump/ 2>>/mali_drv_compile.txt && echo \"Successfully copied all ump files to '/usr/include/ump/'.\"
				make 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 7\" && echo \"Successfully ran the 'make' (ump) command.\"
				cp -f ./libUMP.so /lib/libUMP.so 2>>/mali_drv_compile.txt && echo \"Successfully copied the created 'libUMP.so' to '/lib'.\"
			fi
			cd /root/mali_2d_build/xf86-video-mali 2>>/mali_drv_compile.txt
			if [ \"\${?}\" = \"0\" ]
			then
				echo \"Changed directory to 'xf86-video-mali'.\"
				autoreconf -vi 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 8\" && echo \"Successfully ran autoreconf.\"
				./configure --prefix=/usr --x-includes=/usr/include --x-libraries=/usr/lib 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 9\" && echo \"Successfully ran the configuration for the xf86 driver.\"
				make 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 10\" && echo \"Successfully ran the 'make' (xf86-video-mali) command.\"
				make install 2>>/mali_drv_compile.txt && xserver_build_log=\"$xserver_build_log 11\" && echo \"Successfully ran the 'make install' (xf86-video-mali) command.\"
			fi
		else
			echo \"ERROR: Couldn't change into directory '/root/mali_2d_build/'!\" >>/post_debootstrap_errors.txt
		fi
		
		if [ \"xserver_build_log\" = \"1 2 3 4 5 6 7 8 9 10 11\" ]
		then
			echo \"Xserver mali400 driver build process completed successfully!\"
			echo \"Xserver mali400 driver build process completed successfully!\" >> /mali_drv_compile.txt
		fi
		#cp ./xorg.conf /usr/share/X11/xorg.conf.d/99-mali400.conf && echo \"Successfully copied the 'xorg.conf' for the xf86 driver.\"
		# dont forget to 'chmod 777 /dev/ump' and 'chmod 777 /dev/mali' on each boot, or create a rule for udev for this.
		
		cat <<END > /etc/rc.local 2>>/deboostrap_stg2_errors.txt
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
	/zram_setup.sh 2>>/zram_setup_log.txt && rm /zram_setup.sh
fi

/setup.sh 2>>/setup_log.txt && rm /setup.sh

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

exit 0
END
	fi
elif [ \"${mali_graphics_choice}\" = \"none\" ]
then
	echo \"No graphics driver and no graphical user interface wanted.\"
else
	echo \"No valid option. Only copy|build|none are accepted. Doing nothing.\"
fi

ldconfig -v

if [ -e /apt_helper.sh ]
then
	rm /apt_helper.sh
fi

reboot 2>>/post_debootstrap_errors.txt
exit 0" > ${output_dir}/mnt_debootstrap/post_debootstrap_setup.sh
chmod +x ${output_dir}/mnt_debootstrap/post_debootstrap_setup.sh

if [ "${mali_graphics_opengl}" = "yes" ]
then
	get_n_check_file "${mali_opengl_bin}" "mali_opengl_driver" "${output_dir}/tmp"
	tar_all extract "${output_dir}/tmp/${mali_opengl_bin##*/}" "${output_dir}/mnt_debootstrap"
fi

if [ "${mali_graphics_choice}" = "copy" ]
then
	get_n_check_file "${mali_2d_bin}" "mali_2d_driver" "${output_dir}/tmp"
	tar_all extract "${output_dir}/tmp/${mali_2d_bin##*/}" "${output_dir}/mnt_debootstrap"
elif [ "${mali_graphics_choice}" = "build" ]
then
	mkdir -p ${output_dir}/mnt_debootstrap/root/mali_2d_build && fn_my_echo "Directory for graphics driver build successfully created."
	get_n_check_file "${mali_xserver_2d_git}" "xf86-video-mali" "${output_dir}/mnt_debootstrap/root/mali_2d_build"
	get_n_check_file "${mali_2d_libdri2_git}" "libdri2" "${output_dir}/mnt_debootstrap/root/mali_2d_build"
	get_n_check_file "${mali_2d_libump_git}" "libump" "${output_dir}/mnt_debootstrap/root/mali_2d_build"
	get_n_check_file "${mali_2d_misc_libs_git}" "mali-libs" "${output_dir}/mnt_debootstrap/root/mali_2d_build"
	if [ -d ${output_dir}/mnt_debootstrap/root/mali_2d_build/xf86-video-mali/src ] && [ "${xf86_version}" = "r3p1" ]
	then
		fn_my_echo "Adding fix for 'xf86-video-mali' release 'r3p1' to sources downloaded via git."
		cd ${output_dir}/mnt_debootstrap/root/mali_2d_build/xf86-video-mali/src
		mkdir ${output_dir}/mnt_debootstrap/root/mali_2d_build/xf86-video-mali/src/umplock
		cat<<END>${output_dir}/mnt_debootstrap/root/mali_2d_build/xf86-video-mali/src/umplock/umplock_ioctl.h
/*
* Copyright (C) 2012 ARM Limited. All rights reserved.
*
* This program is free software and is provided to you under the terms of the GNU General Public License version 2
* as published by the Free Software Foundation, and any use by you of this program is subject to the terms of such GNU licence.
*
* A copy of the licence is included with the program, and can also be obtained from Free Software
* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

#ifndef __UMPLOCK_IOCTL_H__
#define __UMPLOCK_IOCTL_H__

#ifdef __cplusplus
extern "C" {
#endif

/*#include 
#include 
*/
#ifndef __user
#define __user
#endif


/**
* @file umplock_ioctl.h
* This file describes the interface needed to use the Linux device driver.
* The interface is used by the userpace Mali DDK.
*/

typedef enum
{
    _LOCK_ACCESS_RENDERABLE = 1,
    _LOCK_ACCESS_TEXTURE,
    _LOCK_ACCESS_CPU_WRITE,
    _LOCK_ACCESS_CPU_READ,
} _lock_access_usage;

typedef struct _lock_item_s

{
    unsigned int secure_id;
    _lock_access_usage usage;
} _lock_item_s;


#define LOCK_IOCTL_GROUP 0x91

#define _LOCK_IOCTL_CREATE_CMD  0   /* create kernel lock item        */
#define _LOCK_IOCTL_PROCESS_CMD 1   /* process kernel lock item       */
#define _LOCK_IOCTL_RELEASE_CMD 2   /* release kernel lock item       */
#define _LOCK_IOCTL_ZAP_CMD     3   /* clean up all kernel lock items */

#define LOCK_IOCTL_MAX_CMDS    4

#define LOCK_IOCTL_CREATE  _IOW( LOCK_IOCTL_GROUP, _LOCK_IOCTL_CREATE_CMD,  _lock_item_s )
#define LOCK_IOCTL_PROCESS _IOW( LOCK_IOCTL_GROUP, _LOCK_IOCTL_PROCESS_CMD, _lock_item_s )
#define LOCK_IOCTL_RELEASE _IOW( LOCK_IOCTL_GROUP, _LOCK_IOCTL_RELEASE_CMD, _lock_item_s )
#define LOCK_IOCTL_ZAP     _IO ( LOCK_IOCTL_GROUP, _LOCK_IOCTL_ZAP_CMD )

#ifdef __cplusplus
}
#endif

#endif /* __UMPLOCK_IOCTL_H__ */
END
	fi	
fi

if [ "${i2c_hwclock}" = "yes" ]
then
	fn_my_echo "Setting up a script for being able to use the i2c-connected RTC (hardware clock)."
	echo "#!/bin/sh
### BEGIN INIT INFO
# Provides:          i2c-hwclock
# Required-Start:    checkroot
# Required-Stop:     $local_fs
# Default-Start:     S
# Default-Stop:      0 6
### END INIT INFO

case \"\$1\" in
	start)
	if [ ! -e /dev/rtc0 ]
	then
		mknod /dev/rtc0 c 254 0
	else
		if [ ! -e /dev/rtc ]
		then
			ln -s /dev/rtc0 /dev/rtc
		fi
	fi
	modprobe i2c-pnx
	modprobe ${rtc_kernel_module_name}
	echo ${i2c_hwclock_name} ${i2c_hwclock_addr} > /sys/bus/i2c/devices/i2c-1/new_device
	/sbin/hwclock -s && echo \"Time successfully set from the RTC!\"
	;;
	stop|restart|reload|force-reload)
	#echo ${i2c_hwclock_name} ${i2c_hwclock_addr} > /sys/bus/i2c/devices/i2c-1/delete_device
	#modprobe -r rtc-ds1307
	#modprobe -r i2c-pnx
	;;
	*)
	    echo \"Usage: i2c_hwclock.sh {start|stop}\"
	    echo \"       start sets up kernel i2c-system for using the i2c-connected hardware (RTC) clock\"
	    echo \"       stop unloads the driver module for the hardware (RTC) clock\"
	    return 1
	;;
    esac
exit 0" > ${output_dir}/mnt_debootstrap/etc/init.d/i2c_hwclock.sh
	chmod +x ${output_dir}/mnt_debootstrap/etc/init.d/i2c_hwclock.sh
else
	fn_my_echo "No RTC (hardware clock) setup. Continueing..."
fi

sleep 3

umount_img all
if [ "$?" = "0" ]
then
	fn_my_echo "Filesystem image file successfully unmounted. Ready to continue."
else
	fn_my_echo "Error while trying to unmount the filesystem image. Exiting now!"
	exit 22
fi

sleep 5

mount |grep "${output_dir}/mnt_debootstrap" > /dev/null
if [ ! "$?" = "0" ]
then
	fn_my_echo "Starting the qemu environment now!"
	qemu-system-arm -M versatilepb -cpu cortex-a8 -no-reboot -kernel ${output_dir}/qemu-kernel/vmlinuz -hda ${output_dir}/${output_filename}.img -m 256 -append "root=/dev/sda rootfstype=ext4 mem=256M devtmpfs.mount=0 rw ip=dhcp" 2>qemu_error_log.txt # TODO: Image name
else
	fn_my_echo "ERROR! Filesystem is still mounted. Can't run qemu!"
	exit 23
fi

fn_my_echo "Additional chroot system configuration successfully finished!"

}


# Description: Compress the resulting rootfs
compress_debian_rootfs()
{
fn_my_echo "Compressing the rootfs now!"

mount |grep ${output_dir}/${output_filename}.img >/dev/null
if [ ! "$?" = "0" ]
then 
	fsck.ext4 -fy ${output_dir}/${output_filename}.img
	if [ "$?" = "0" ]
	then
		fn_my_echo "Temporary filesystem checked out, OK!"
	else
		fn_my_echo "ERROR: State of Temporary filesystem is NOT OK! Exiting now."
		regular_cleanup
		exit 24
	fi
else
	fn_my_echo "ERROR: Image file still mounted. Exiting now!"
	regular_cleanup
	exit 25
fi

mount ${output_dir}/${output_filename}.img ${output_dir}/mnt_debootstrap -o loop
if [ "$?" = "0" ]
then
	rm -r ${output_dir}/mnt_debootstrap/lib/modules/2.6.33-gnublin-qemu-*/
	cd ${output_dir}/mnt_debootstrap
	if [ "${tar_format}" = "bz2" ]
	then
		tar_all compress "${output_dir}/${output_filename}.tar.${tar_format}" .
	elif [ "${tar_format}" = "gz" ]
	then
		tar_all compress "${output_dir}/${output_filename}.tar.${tar_format}" .
	else
		fn_my_echo "Incorrect setting '${tar_format}' for the variable 'tar_format' in the general_settings.sh.
Please check! Only valid entries are 'bz2' or 'gz'. Could not compress the Rootfs!"
	fi

	cd ${output_dir}
	sleep 5
else
	fn_my_echo "ERROR: Image file could not be remounted correctly. Exiting now!"
	regular_cleanup
	exit 26
fi

umount ${output_dir}/mnt_debootstrap
sleep 10
mount | grep ${output_dir}/mnt_debootstrap > /dev/null
if [ ! "$?" = "0" ] && [ "${clean_tmp_files}" = "yes" ]
then
	rm -r ${output_dir}/mnt_debootstrap
	rm -r ${output_dir}/qemu-kernel
	rm ${output_dir}/${output_filename}.img
elif [ "$?" = "0" ] && [ "${clean_tmp_files}" = "yes" ]
then
	fn_my_echo "Directory '${output_dir}/mnt_debootstrap' is still mounted, so it can't be removed. Exiting now!"
	regular_cleanup
	exit 27
elif [ "$?" = "0" ] && [ "${clean_tmp_files}" = "no" ]
then
	fn_my_echo "Directory '${output_dir}/mnt_debootstrap' is still mounted, please check. Exiting now!"
	regular_cleanup
	exit 28
fi

fn_my_echo "Rootfs successfully DONE!"
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
			fn_my_echo "SD-card device set to '${device}', according to user input."
			parted -s ${device} mklabel msdos
			# first partition = boot (raw, size = ${size_boot_partition} )
			parted -s --align=opt -- ${device} unit MB mkpart primary fat16 -`expr ${size_boot_partition} + ${size_swap_partition}` -${size_swap_partition}
			# second partition = root (rest of the drive size)
			parted --align=opt -- ${device} unit MB mkpart primary ext4 1 -`expr ${size_boot_partition} + ${size_swap_partition}`
			parted -s -- ${device} set 2 boot on
			# last partition = swap (swap, size = ${size_swap_partition} )
			parted -s --align=opt -- ${device} unit MB mkpart primary linux-swap -${size_swap_partition} -0
			echo ">>> ${device} Partition table is now:"
			parted -s ${device} unit MB print
		else
			fn_my_echo "Action canceled by user. Exiting now!"
			regular_cleanup
			exit 29
		fi
	else
		fn_my_echo "ERROR! Some partition on device '${device}' is still mounted. Exiting now!"
		regular_cleanup
		exit 30
	fi
else
	if [ ! -z "${device}" ] # in case of a refresh we don't want to see the error message ;-)
	then 
		fn_my_echo "ERROR! Device '${device}' doesn't seem to be a valid device!"
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
	fn_my_echo "ERROR: There should be 3 partitions on '${device}', but one or more seem to be missing.
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
fn_my_echo "Getting the bootloader and trying to copy it to the boot partition, now!"

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
				fn_my_echo "Bootloader part 1 successfully copied to SD-card ('${device}')!"
			else
				fn_my_echo "ERROR while trying to copy the bootloader part 1 '${bootloader_bin_1}' to the device '${device}2'."
			fi
		else
			fn_my_echo "ERROR! Bootloader binary '${bootloader_bin_1##*/}' doesn't seem to exist in directory '${output_dir}/tmp/'.
			You won't be able to boot the card, without copying the file to the second partition."
		fi

		if [ -e "${output_dir}/tmp/${bootloader_bin_2##*/}" ] # u-boot.bin
		then
			dd if=${output_dir}/tmp/${bootloader_bin_2##*/} of=${device} bs=1024 seek=32
			if [ "$?" = "0" ]
			then
				fn_my_echo "Bootloader part 2 successfully copied to SD-card ('${device}')!"
			else
				fn_my_echo "ERROR while trying to copy the bootloader part 2 '${bootloader_bin_2}' to the device '${device}2'."
			fi
		else
			fn_my_echo "ERROR! Bootloader binary '${bootloader_bin_2##*/}' doesn't seem to exist in directory '${output_dir}/tmp/'.
			You won't be able to boot the card, without copying the file to the second partition."
		fi
	else
		fn_my_echo "ERROR! Some partition on device '${device}' is still mounted. Exiting now!"
	fi
else
	fn_my_echo "ERROR! Device '${device}' doesn't seem to exist!
	Exiting now"
	regular_cleanup
	exit 33
fi

# unpack the filesystem and kernel to the root partition

fn_my_echo "Now unpacking the rootfs to the SD-card's root partition!"

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
			fn_my_echo "ERROR: File '${output_dir}/${output_filename}.tar.${tar_format}' doesn't seem to exist. Exiting now!"
			regular_cleanup
			exit 34
		fi
		sleep 1
	else
		fn_my_echo "ERROR while trying to mount '${device}2' to '${output_dir}/sd-card'. Exiting now!"
		regular_cleanup
		exit 35
	fi
else
	fn_my_echo "ERROR while trying to create the temporary directory '${output_dir}/sd-card'. Exiting now!"
	regular_cleanup
	exit 36
fi

sleep 3
fn_my_echo "Unmounting the SD-card now."
umount ${output_dir}/sd-card/root
umount ${output_dir}/sd-card/boot

sleep 3
fn_my_echo "Running fsck to make sure the filesystem on the card is fine."
fsck -fy ${device}1 # final check
fsck -fy ${device}2 # final check
if [ "$?" = "0" ]
then
	fn_my_echo "SD-card successfully created!
You can remove the card now and try it in your hackberry-board.
ALL DONE!"

else
	fn_my_echo "ERROR! Filesystem check on your card returned an error status. Maybe your card is going bad, or something else went wrong."
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
		if [ "${2:(-8)}" = ".tar.bz2" ]
		then
			tar -cpjvf "${2}" "${3}"
		elif [ "${2:(-7)}" = ".tar.gz" ]
		then
			tar -cpzvf "${2}" "${3}"
		else
			fn_my_echo "ERROR! Created files can only be of type '.tar.gz', or '.tar.bz2'! Exiting now!"
			regular_cleanup
			exit 37
		fi
	else
		fn_my_echo "ERROR! Illegal arguments '$2' and/or '$3'. Exiting now!"
		regular_cleanup
		exit 38
	fi
elif [ "$1" = "extract" ]
then
	if [ -e "${2}"  ] && [ -d "${3}" ]
	then
		if [ "${2:(-8)}" = ".tar.bz2" ]
		then
			tar -xpjvf "${2}" -C "${3}"
		elif [ "${2:(-7)}" = ".tar.gz"  ]
		then
			tar -xpzvf "${2}" -C "${3}"
		else
			fn_my_echo "ERROR! Can only extract files of type '.tar.gz', or '.tar.bz2'!
'${2}' doesn't seem to fit that requirement. Exiting now!"
			regular_cleanup
			exit 39
		fi
	else
		fn_my_echo "ERROR! Illegal arguments '$2' and/or '$3'. Exiting now!"
		regular_cleanup
		exit 40
	fi
else
	fn_my_echo "ERROR! The first parameter needs to be either 'compress' or 'extract', and not '$1'. Exiting now!"
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
		fn_my_echo "Virtual Image still mounted. Trying to umount now!"
		umount ${output_dir}/mnt_debootstrap/sys > /dev/null
		umount ${output_dir}/mnt_debootstrap/dev/pts > /dev/null
		umount ${output_dir}/mnt_debootstrap/proc > /dev/null
	fi

	mount | egrep '(${output_dir}/mnt_debootstrap/sys|${output_dir}/mnt_debootstrap/proc|${output_dir}/mnt_debootstrap/dev/pts)' > /dev/null
	if [ "$?" = "0"  ]
	then
		fn_my_echo "ERROR! Something went wrong. All subdirectories of '${output_dir}' should have been unmounted, but are not."
	else
		fn_my_echo "Virtual image successfully unmounted."
	fi
elif [ "${1}" = "all" ]
then
	mount | grep "${output_dir}" > /dev/null
	if [ "$?" = "0"  ]
	then
		fn_my_echo "Virtual Image still mounted. Trying to umount now!"
		umount ${output_dir}/mnt_debootstrap/sys > /dev/null
		umount ${output_dir}/mnt_debootstrap/dev/pts > /dev/null
		umount ${output_dir}/mnt_debootstrap/proc > /dev/null
		umount ${output_dir}/mnt_debootstrap/ > /dev/null
	fi

	mount | grep "${output_dir}" > /dev/null
	if [ "$?" = "0"  ]
	then
		fn_my_echo "ERROR! Something went wrong. '${output_dir}' should have been unmounted, but isn't."
	else
		fn_my_echo "Virtual image successfully unmounted."
	fi
else
	fn_my_echo "ERROR! Wrong parameter. Only 'sys' and 'all' allowed when calling 'umount_img'."
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
	fn_my_echo "ERROR! Trying to call the function 'sed_search_n_replace' with (a) wrong parameter(s). The following was used:
'Param1='${1}'
Param2='${2}'
Param3='${3}'"
fi
sleep 1
grep -F "${replacement}" "${file}" > /dev/null

if [ "$?" = "0" ]
then
	fn_my_echo "String '${original}' was successfully replaced in file '${file}'."
else
	fn_my_echo "ERROR! String '${original}' could not be replaced in file '${file}'!"
fi

}



get_n_check_file()
{
file_path=${1%/*}
file_name=${1##*/}
short_description=${2}
output_path=${3}

if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
then
	fn_my_echo "ERROR: Function get_n_check_file needs 3 parameters.
Parameter 1 is file_path/file_name, parameter 2 is short_description and parameter 3 is output-path.
Faulty parameters passed were '${1}', '${2}' and '${3}'.
One or more of these appear to be empty. Exiting now!" 
	regular_cleanup
	exit 42
fi

if [ "${file_path:0:7}" = "http://" ] || [ "${file_path:0:8}" = "https://" ] || [ "${file_path:0:6}" = "ftp://" ] || [ "${file_path:0:6}" = "git://" ] 
then
	if [ -d ${output_path} ]
	then
		cd ${output_path}
		if [ "${file_name:(-4):4}" = ".git" ]
		then
			fn_my_echo "Trying to clone repository ${short_description} from address '${file_path}/${file_name}', now."
			git clone ${file_path}/${file_name}
			if [ "$?" = "0" ]
				then
					fn_my_echo "'${short_description}' repository successfully cloned from address '${file_path}/${file_name}'."
			else
					fn_my_echo "ERROR: Repository '${file_path}/${file_name}' could not be cloned.
		Exiting now!"
				regular_cleanup
				exit 42
			fi
		else
			echo "${file_name}" |grep ".git -b "
			if [ "$?" = "0" ]
			then
				branch_name="${file_name##*.git -b }"
				git_repo="${file_path}/${file_name% -b*}"
				git clone -b ${branch_name} ${git_repo}
				if [ "$?" = "0" ]
				then
					fn_my_echo "'${short_description}' repository, branch '${branch_name}', successfully cloned from address '${file_path}/${file_name}'."
				else
					fn_my_echo "ERROR: Repository '${file_path}/${file_name}', branch '${branch_name}' could not be cloned.
		Exiting now!"
				regular_cleanup
				exit 43
				fi
			else  
				fn_my_echo "Trying to download ${short_description} from address '${file_path}/${file_name}', now."
				wget -q --spider ${file_path}/${file_name}
				if [ "$?" = "0" ]
				then
					wget -t 3 ${file_path}/${file_name}
					if [ "$?" = "0" ]
					then
						fn_my_echo "'${short_description}' successfully downloaded from address '${file_path}/${file_name}'."
					else
						fn_my_echo "ERROR: File '${file_path}/${file_name}' could not be downloaded.
			Exiting now!"
					regular_cleanup
					exit 43
					fi
				else
					fn_my_echo "ERROR: '${file_path}/${file_name}' does not seem to be a valid internet address. Please check!
			Exiting now!"
					regular_cleanup
					exit 44
				fi
			fi
		fi
	else
		fn_my_echo "ERROR: Output directory '${output_path}' does not seem to exist. Please check!
	Exiting now!"
			regular_cleanup
			exit 45
	fi
else
	fn_my_echo "Looking for the ${short_description} locally (offline)."	
	if [ -d ${file_path} ]
	then
		if [ -e ${file_path}/${file_name} ]
		then
			fn_my_echo "File is a local file '${file_path}/${file_name}', so it stays where it is."
			ln -s ${file_path}/${file_name} ${output_path}/${file_name}
		else
			fn_my_echo "ERROR: File '${file_name}' does not seem to be a valid file in existing directory '${file_path}'.Exiting now!"
			regular_cleanup
			exit 47
		fi
	else
		fn_my_echo "ERROR: Folder '${file_path}' does not seem to exist as a local directory. Exiting now!"
		regular_cleanup
		exit 48
	fi
fi
cd ${output_dir}
}


int_cleanup() # special treatment for script abort through interrupt ('ctrl-c'  keypress, etc.)
{
	fn_my_echo "Build process interrrupted. Now trying to clean up!"
	umount_img all 2>/dev/null
	rm -r ${output_dir}/mnt_debootstrap 2>/dev/null
	rm -r ${output_dir}/tmp 2>/dev/null
	rm -r ${output_dir}/sd-card 2>/dev/null
	exit 99
}

regular_cleanup() # cleanup for all other error situations
{
	umount_img all 2>/dev/null
	rm -r ${output_dir}/mnt_debootstrap 2>/dev/null
	rm -r ${output_dir}/tmp 2>/dev/null
	rm -r ${output_dir}/sd-card 2>/dev/null
}


apt_get_helper()
{
apt_choice=${1}
if [ "${apt_choice}" = "write_script" ]
then
	fn_my_echo "Writing the 'apt_helper.sh' helper script for the apt install processes."
	cat<<END>${output_dir}/mnt_debootstrap/apt_helper.sh
#!/bin/bash
# helper script to install a list of packages, even if one or more errors occur

apt_get_helper()
{
apt_choice=\${1}
package_list=\${2}
update_choice=\${3}

set -- \${package_list}

while [ \$# -gt 0 ]
do
	if [ "\${update_choice}" = "upd" ] && [ ! "\${apt_get_update_done}" = "true" ]
	then
		/usr/bin/apt-get update
		apt_get_update_done="true"
	fi
	if [ "\${apt_choice}" = "download" ]
	then
		/usr/bin/apt-get install -y -d \${1}
	elif [ "\${apt_choice}" = "install" ]
	then
		/usr/bin/apt-get install -y \${1}
	else
		echo "ERROR: Parameter 1 should either be 'download' or 'install'.
Invalid parameter '\${apt_choice}' passed to function. Exiting now!"
		exit 91
	fi
	if [ "\$?" = "0" ]
	then
		echo "'\${1}' \${apt_choice}ed successfully!"
	else
		echo "ERROR while trying to \${apt_choice} package '\${1}'."
		echo "ERROR while trying to \${apt_choice} package '\${1}'." >> /apt_helper_error.txt
	fi
	shift
done
}
END
	#chmod +x ${output_dir}/mnt_debootstrap/apt_helper.sh
elif [ "${apt_choice}" = "download" ] || [ "${apt_choice}" = "install" ]
then
	package_list=${2}
	update_choice=${3}

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
			apt-get install -y -d ${1}
		elif [ "${apt_choice}" = "install" ]
		then
			apt-get install -y ${1}
		fi
		if [ "$?" = "0" ]
		then
			echo "'${1}' \${apt_choice}ed successfully!"
		else
			echo "ERROR while trying to \${apt_choice} '${1}'."
		fi

		shift
	done
else
	echo "ERROR: Parameter 1 should either be 'write_script' or 'download' or 'install'.
	Invalid parameter '${apt_choice}' passed to function. Exiting now!"
	exit 91
fi
}

