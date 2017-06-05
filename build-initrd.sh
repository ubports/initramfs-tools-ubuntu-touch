#!/bin/sh

set -ex


if [ -z "$FAKEROOTKEY" ]; then
	exec fakeroot "$0" "$@"
fi

export FLASH_KERNEL_SKIP=1
export DEBIAN_FRONTEND=noninteractive

DEB_HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)

# list all packages needed for a generic ubuntu touch initrd here
INCHROOTPKGS="initramfs-tools dctrl-tools lxc-android-config abootimg android-tools-adbd e2fsprogs"

MIRROR=$(grep "^deb " /etc/apt/sources.list|grep -v "ppa.launchpad.net"|head -1|cut -d' ' -f2)
RELEASE=$(lsb_release -cs)
ROOT=./build

# create a plain chroot to work in
rm -rf $ROOT
fakechroot -c fakechroot-config debootstrap --variant=fakechroot $RELEASE $ROOT $MIRROR || cat $ROOT/debootstrap/debootstrap.log

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

# after teh switch to systemd we now need to install upstart explicitly
fakechroot chroot $ROOT apt-get -y update
fakechroot -c fakechroot-config chroot $ROOT apt-get -y install upstart

mv $ROOT/sbin/initctl $ROOT/sbin/initctl.REAL
cat > $ROOT/sbin/initctl <<EOF
#!/bin/sh
echo 1>&2
echo 'Warning: Fake initctl called, doing nothing.' 1>&2
exit 0
EOF
chmod a+rx $ROOT/sbin/initctl

# install all packages we need to roll the generic initrd
fakechroot -c fakechroot-config chroot $ROOT apt-get -y install $INCHROOTPKGS

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

fakechroot chroot $ROOT update-initramfs -c -ktouch-$VER -v

# make a more generically named link so external scripts can use the file without parsing the version
cd $ROOT/boot
ln -s initrd.img-touch-$VER initrd.img-touch
cd - >/dev/null 2>&1

# put a fake sha1sum file in place so update-initramfs -u works OOTB for developers
fakechroot chroot $ROOT sha1sum /boot/initrd.img-touch >$ROOT/var/lib/initramfs-tools/touch
