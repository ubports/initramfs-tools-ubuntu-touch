#!/bin/sh

set -e


if [ -z "$FAKEROOTKEY" ]; then
	exec fakeroot "$0" "$@"
fi

[ "$(dpkg --print-architecture)" != "armhf" ] && exit 0

export FLASH_KERNEL_SKIP=1
export DEBIAN_FRONTEND=noninteractive

# list all packages needed for a generic ubuntu touch initrd here
INCHROOTPKGS="initramfs-tools dctrl-tools lxc-android-config abootimg android-tools-adbd"

MIRROR=$(grep "^deb " /etc/apt/sources.list|head -1|cut -d' ' -f2)
RELEASE=$(lsb_release -cs)
ROOT=./build

# create a plain chroot to work in
rm -rf $ROOT
fakechroot debootstrap --variant=fakechroot $RELEASE $ROOT $MIRROR

# TODO this can be dropped once all packages are in main
sed -i 's/main$/main universe/' $ROOT/etc/apt/sources.list
sed -i 's/raring/saucy/' $ROOT/etc/apt/sources.list

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

mv $ROOT/sbin/initctl $ROOT/sbin/initctl.REAL
cat > $ROOT/sbin/initctl <<EOF
#!/bin/sh
echo 1>&2
echo 'Warning: Fake initctl called, doing nothing.' 1>&2
exit 0
EOF
chmod a+rx $ROOT/sbin/initctl

# install all packages we need to roll the generic initrd
fakechroot chroot $ROOT apt-get -y update
fakechroot -c fakechroot-config chroot $ROOT apt-get -y install $INCHROOTPKGS

cp -a conf/touch ${ROOT}/usr/share/initramfs-tools/conf.d
cp -a scripts/* ${ROOT}/usr/share/initramfs-tools/scripts
cp -a hooks/touch ${ROOT}/usr/share/initramfs-tools/hooks

VER="$(head -1 debian/changelog |sed -e 's/^.*(//' -e 's/).*$//')"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/lib/arm-linux-gnueabihf"

## Temporary HACK to work around FTBFS
mkdir -p $ROOT/usr/lib/arm-linux-gnueabihf/fakechroot
mkdir -p $ROOT/usr/lib/arm-linux-gnueabihf/libfakeroot

touch $ROOT/usr/lib/arm-linux-gnueabihf/fakechroot/libfakechroot.so
touch $ROOT/usr/lib/arm-linux-gnueabihf/libfakeroot/libfakeroot-sysv.so

fakechroot chroot $ROOT update-initramfs -c -ktouch-$VER -v

# make a more generically named link so external scripts can use the file without parsing the version
cd $ROOT/boot
ln -s initrd.img-touch-$VER initrd.img-touch
cd - >/dev/null 2>&1

# put a fake sha1sum file in place so update-initramfs -u works OOTB for developers
fakechroot chroot $ROOT sha1sum /boot/initrd.img-touch >$ROOT/var/lib/initramfs-tools/touch
