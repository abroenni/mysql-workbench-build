# mysql-workbench

Build script for compiling MySql-Workbench 8 from source on Debian Testing

## Background and info
The package mysql-workbench version 6 was removed from the Debian testing repos because of a build dependency issue with gdal in late 2018. In the meantime, mysql-workbench 8 has been released and upon reading messages on oracle forums, the build issues have been solved. A new build with mysql-workbench version 8 on debian testing (2019.6) worked.

The workbench sources don't make it easy to compile into a DEB package and some seem outdate. This is why I created this build script. The final DEB probably does not conform with the strict Debian rules as it includes the oracle mysql-c++ connector and mysql-client libs.

The build runs successfully in a chroot and fully installs on a debian testing netinstall with lightdm and mate-desktop-environment. It also connects fine to a running mysql server instance.

While I am not the official Debian maintainer for the mysql-workbench packages, the build script includes many steps used in the official buildd environments to create an ok quality package.

## Building the DEB package
Create a build folder for development in your root home folder. Change into the directory, get the build script and run it.

```
# mkdir ~/build && cd ~/build
# git clone [this repo]
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
Now you can install the DEB package.
