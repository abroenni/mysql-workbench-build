# mysql-workbench

Build script for compiling MySql-Workbench 8 from source on Debian Testing

## Building the DEB package
Create a build folder for development in your root home folder. Change into the directory, get the build script and run it.

```
# mkdir ~/build && cd ~/build
# git clone X
# cd mysql-workbench
# ./build
```

## Optional: Setting up a chroot for the build
You could do this in /tmp if you have enough RAM. But here we use the root home folder. We build the chroot as the buildd variant, which installs the build essentials package plus we add some more required packages. 

```
# apt install debootstrap
# cd ~
# mkdir chroot_testing
# debootstrap --arch amd64 --variant=buildd --include=git,locales,locales-all,apt-utils testing chroot_testing/ 
# mount -t proc /proc chroot_testing/proc/
# mount -t sysfs /sys chroot_testing/sys/
# mount -o bind /dev chroot_testing/dev/
# chroot chroot_testing/ /bin/bash
```
Now you can build the DEB package with the steps given above. When done, you need to exit out of the chroot to grab the DEB from inside it. Only then you can destroy your chroot.

```
# cd ~
# umount chroot_testing/proc/ chroot_testing/sys/ chroot_testing/dev/
# rm -rf ./chroot_testing/
```
Now you can install you DEB package.