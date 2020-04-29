#!/bin/sh

set -e

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
fakechroot -c fakechroot-config fakeroot debootstrap --variant=fakechroot $RELEASE $ROOT $MIRROR || cat $ROOT/debootstrap/debootstrap.log

# TODO this can be dropped once all packages are in main
sed -i 's/main$/main universe/' $ROOT/etc/apt/sources.list

echo "deb $MIRROR $RELEASE-updates main restricted" >> $ROOT/etc/apt/sources.list

# for xenial/vivid builds we also need to make sure we use the overlay
cp ubports.list $ROOT/etc/apt/sources.list.d/
cp ubports.pref $ROOT/etc/apt/preferences.d/

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
fakechroot fakeroot chroot $ROOT apt-get -y update
fakechroot -c fakechroot-config fakeroot chroot $ROOT apt-get -y --allow-unauthenticated install upstart

mv $ROOT/sbin/initctl $ROOT/sbin/initctl.REAL
cat > $ROOT/sbin/initctl <<EOF
#!/bin/sh
echo 1>&2
echo 'Warning: Fake initctl called, doing nothing.' 1>&2
exit 0
EOF
chmod a+rx $ROOT/sbin/initctl

# install all packages we need to roll the generic initrd
fakechroot -c fakechroot-config fakeroot chroot $ROOT apt-get -y --allow-unauthenticated install $INCHROOTPKGS

cp -a conf/halium ${ROOT}/usr/share/initramfs-tools/conf.d
cp -a scripts/* ${ROOT}/usr/share/initramfs-tools/scripts
cp -a hooks/* ${ROOT}/usr/share/initramfs-tools/hooks

# remove the plymouth hooks from the chroot
find $ROOT/usr/share/initramfs-tools -name plymouth -exec rm -f {} \;

#VER="$(head -1 debian/changelog |sed -e 's/^.*(//' -e 's/).*$//')"
VER="1"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/lib/$DEB_HOST_MULTIARCH"

#do_chroot $ROOT "update-initramfs -tc -ktouch-$VER -v"

# hack for arm64 builds where some binaries look for the ld libs in the wrong place
cd $ROOT
ln -s lib/ lib64
cd - >/dev/null 2>&1

fakechroot fakeroot chroot $ROOT update-initramfs -c -ktouch-$VER -v

# make a more generically named link so external scripts can use the file without parsing the version
cd $ROOT/boot
ln -s initrd.img-touch-$VER initrd.img-touch
cd - >/dev/null 2>&1
