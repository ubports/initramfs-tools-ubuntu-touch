#!/bin/sh

set -ex

export FLASH_KERNEL_SKIP=1
export DEBIAN_FRONTEND=noninteractive

DEB_HOST_MULTIARCH="arm-linux-gnueabihf"
BOOTSTRAP_BIN="qemu-debootstrap --arch armhf --variant=minbase"

# list all packages needed for halium's initrd here
INCHROOTPKGS="initramfs-tools dctrl-tools lxc-android-config abootimg android-tools-adbd e2fsprogs"

MIRROR="http://ports.ubuntu.com/ubuntu-ports"
RELEASE="xenial"
ROOT=./build
OUT=./out

# create a plain chroot to work in
rm -rf $ROOT || true
$BOOTSTRAP_BIN $RELEASE $ROOT $MIRROR || cat $ROOT/debootstrap/debootstrap.log

sed -i 's/main$/main universe/' $ROOT/etc/apt/sources.list

# make sure we do not start daemons at install time
mv $ROOT/sbin/start-stop-daemon $ROOT/sbin/start-stop-daemon.REAL
cat > $ROOT/sbin/start-stop-daemon <<EOF
#!/bin/sh
echo 1>&2
echo 'Warning: Fake start-stop-daemon called, doing nothing.' 1>&2
exit 0
EOF
chmod a+rx $ROOT/sbin/start-stop-daemon

cat > $ROOT/usr/sbin/policy-rc.d <<EOF
#!/bin/sh
exit 101
EOF
chmod a+rx $ROOT/usr/sbin/policy-rc.d

do_chroot()
{
	ROOT="$1"
	CMD="$2"
	chroot $ROOT mount -t proc proc /proc
	chroot $ROOT mount -t sysfs sys /sys
	chroot $ROOT $CMD
	chroot $ROOT umount /sys
	chroot $ROOT umount /proc
}

# after the switch to systemd we now need to install upstart explicitly
echo "nameserver 8.8.8.8" >$ROOT/etc/resolv.conf
do_chroot $ROOT "apt-get -y update"
do_chroot $ROOT "apt-get -y install upstart"

mv $ROOT/sbin/initctl $ROOT/sbin/initctl.REAL
cat > $ROOT/sbin/initctl <<EOF
#!/bin/sh
echo 1>&2
echo 'Warning: Fake initctl called, doing nothing.' 1>&2
exit 0
EOF
chmod a+rx $ROOT/sbin/initctl

# install all packages we need to roll the generic initrd
do_chroot $ROOT "apt-get -y install $INCHROOTPKGS"

cp -a conf/touch ${ROOT}/usr/share/initramfs-tools/conf.d
cp -a scripts/* ${ROOT}/usr/share/initramfs-tools/scripts
cp -a hooks/touch ${ROOT}/usr/share/initramfs-tools/hooks
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

