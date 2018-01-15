#!/bin/sh

set -e

export FLASH_KERNEL_SKIP=1
export DEBIAN_FRONTEND=noninteractive

usage() {
	echo "Hi"
}

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage
			;;
		-a|--arch)
			[ -n "$2" ] && ARCH=$2 shift || usage
			;;
	esac
	shift
done

if [ -z $ARCH ]; then
	echo "Error: No architecture specified."
	usage
	exit 1
fi

MIRROR="http://ports.ubuntu.com/ubuntu-ports"
RELEASE="xenial"
ROOT=./build/$ARCH
OUT=./out

# list all packages needed for halium's initrd here
INCHROOTPKGS="initramfs-tools dctrl-tools lxc-android-config abootimg android-tools-adbd e2fsprogs"


BOOTSTRAP_BIN="qemu-debootstrap --arch $ARCH --variant=minbase"

do_chroot()
{
	STOP=false
	ROOT="$1"
	CMD="$2"
	echo "+ Executing \"$2\" in chroot"
	chroot $ROOT mount -t proc proc /proc
	chroot $ROOT mount -t sysfs sys /sys
	chroot $ROOT $CMD || STOP=true
	chroot $ROOT umount /sys
	chroot $ROOT umount /proc
	if [ "$STOP" = true ]; then
		exit 1
	fi
}

START_STOP_DAEMON=`cat <<EOF
#!/bin/sh
echo 1>&2
echo 'Warning: Fake start-stop-daemon called, doing nothing.' 1>&2
exit 0
EOF
`

POLICY_RC_D=`cat <<EOF
#!/bin/sh
exit 101
EOF
`

INITCTL=`cat <<EOF
#!/bin/sh
echo 1>&2
echo 'Warning: Fake initctl called, doing nothing.' 1>&2
exit 0
EOF
`

if [ ! -e $ROOT/.min-done ]; then

	# create a plain chroot to work in
	echo "Creating chroot with arch $ARCH in $ROOT"
	mkdir $ROOT -p
	$BOOTSTRAP_BIN $RELEASE $ROOT $MIRROR || cat $ROOT/debootstrap/debootstrap.log

	sed -i 's/main$/main universe/' $ROOT/etc/apt/sources.list

	# make sure we do not start daemons at install time
	mv $ROOT/sbin/start-stop-daemon $ROOT/sbin/start-stop-daemon.REAL
	echo $START_STOP_DAEMON > $ROOT/sbin/start-stop-daemon 
	chmod a+rx $ROOT/sbin/start-stop-daemon

	echo $POLICY_RC_D > $ROOT/usr/sbin/policy-rc.d

	# after the switch to systemd we now need to install upstart explicitly
	echo "nameserver 8.8.8.8" >$ROOT/etc/resolv.conf
	do_chroot $ROOT "apt-get -y update"
	do_chroot $ROOT "apt-get -y install upstart --no-install-recommends"

	# We also need to install dpkg-dev in order to use dpkg-architecture.
	do_chroot $ROOT "apt-get -y install dpkg-dev --no-install-recommends"

	mv $ROOT/sbin/initctl $ROOT/sbin/initctl.REAL
	echo $INITCTL > $ROOT/sbin/initctl
	chmod a+rx $ROOT/sbin/initctl

	touch $ROOT/.min-done

fi

# install all packages we need to roll the generic initrd
do_chroot $ROOT "apt-get -y update"
do_chroot $ROOT "apt-get -y dist-upgrade"
do_chroot $ROOT "apt-get -y install $INCHROOTPKGS --no-install-recommends"
DEB_HOST_MULTIARCH=`chroot $ROOT dpkg-architecture -q DEB_HOST_MULTIARCH`

cp -a conf/touch ${ROOT}/usr/share/initramfs-tools/conf.d
cp -a scripts/* ${ROOT}/usr/share/initramfs-tools/scripts
cp -a hooks/* ${ROOT}/usr/share/initramfs-tools/hooks
sed -i -e "s/#DEB_HOST_MULTIARCH#/$DEB_HOST_MULTIARCH/g" ${ROOT}/usr/share/initramfs-tools/hooks/touch

VER="$(head -1 debian/changelog |sed -e 's/^.*(//' -e 's/).*$//')"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/lib/$DEB_HOST_MULTIARCH"

## Temporary HACK to work around FTBFS
mkdir -p $ROOT/usr/lib/$DEB_HOST_MULTIARCH/fakechroot
mkdir -p $ROOT/usr/lib/$DEB_HOST_MULTIARCH/libfakeroot

touch $ROOT/usr/lib/$DEB_HOST_MULTIARCH/fakechroot/libfakechroot.so
touch $ROOT/usr/lib/$DEB_HOST_MULTIARCH/libfakeroot/libfakeroot-sysv.so

do_chroot $ROOT "update-initramfs -c -ktouch-$VER -v"

rm -r $OUT || true
mkdir $OUT
cp $ROOT/boot/initrd.img-touch-$VER $OUT
cd $OUT
ln -s initrd.img-touch-$VER initrd.img-touch
cd - >/dev/null 2>&1
