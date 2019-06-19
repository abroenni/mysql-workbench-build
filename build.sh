#!/bin/bash

build_dir=mysql-bench
pkgname=mysql-workbench
pkgver=8.0.16
_mysql_version=${pkgver}
_connector_version=${pkgver}
_gdal_version=2.4.1
_boost_version=1.69.0
_antlr_version=4.7.2

src_dir=`pwd`
debianin_dir=${src_dir}/debian.orig
debian_dir=${src_dir}/debian
build_root=${src_dir}/${build_dir}
srcdir=${build_root}
pkgdir=${debian_dir}/${pkgname}
build_root_backup=${src_dir}/${build_dir}_backup

# Finding number if cores on system
NB_CORES=$(grep -c '^processor' /proc/cpuinfo)
DEFAULT_CHROOT_CORES=2


# BUILD DEPS
builddeps=("build-essential" "debhelper" "autoconf" "wget" "autogen" "cmake" "unzip" "uuid-dev" "swig" "libaio-dev"
	"libssl-dev" "libncurses5-dev" "libboost-dev" "antlr4" "pkg-config" "libx11-dev" "libpcre3-dev"
	"libantlr4-runtime-dev" "libgtk-3-dev" "libgtkmm-3.0-dev" "libsecret-1-dev" "python-dev" "libxml2-dev"
        "libvsqlitepp-dev" "libssh-dev" "unixodbc-dev" "libzip-dev" "imagemagick" "libgdal-dev"
        "bison" "doxygen" "libtirpc-dev" "libsasl2-dev" "libproj-dev" "libxml2-utils")

source_urls=("https://dev.mysql.com/get/Downloads/MySQLGUITools/mysql-workbench-community-${pkgver}-src.tar.gz"
	     "https://cdn.mysql.com/Downloads/MySQL-${_mysql_version%.*}/mysql-${_mysql_version}.tar.gz"
	     "https://cdn.mysql.com/Downloads/Connector-C++/mysql-connector-c++-${_connector_version}-src.tar.gz"
	     "https://www.antlr.org/download/antlr-${_antlr_version}-complete.jar"
	     "https://downloads.sourceforge.net/project/boost/boost/${_boost_version}/boost_${_boost_version//./_}.tar.bz2")

root_check(){
	if ! [ $(id -u) = 0 ]; then
  		 echo "This build script must be run as root!"
   		exit 1
	fi
}

chroot_check(){
	rootinode=`stat -c %i /`
	localegen=en_US.UTF-8
	if [[ "${rootinode}" != "2" ]]; then
		echo "Chroot environment detected. Configuring Chroot for build.."
		export LANGUAGE=${localegen}
		export LANG=${localegen}
		export LC_ALL=${localegen}
		locale-gen ${localegen}

		if [[ "${NB_CORES}" = "" ]]; then
			echo "Hard setting build cpu cores to ${DEFAULT_CHROOT_CORES}"
			echo "You propably forgot to mount your host system's /proc /sys and /dev folders"
			NB_CORES=${DEFAULT_CHROOT_CORES}
		fi

	fi
}

install_builddep(){
	instdebs=()

	for deb in "${builddeps[@]}"; do
        	dpkg -s ${deb} > /dev/null 2>&1
        	err=$?
        	# 1 not installed, 0 is installed
        	if [ ${err} -eq 1 ]; then
                	echo "[ ] Package ${deb} NOT installed"
                	instdebs=("${instdebs[@]}" "${deb}")
        	else
                	echo "[ii] Package ${deb} found"
        	fi
	done
	# install the build dependencies
	apt install ${instdebs[@]}
}

get(){
	if [ ! -d ${debian_dir} ]; then
		cp -r ${debianin_dir} ${debian_dir}
	fi


	if [ ! -d ${build_root} ]; then
		if [ ! -d ${build_root_backup} ]; then

			mkdir ${build_root};
			echo "Getting sources";
			for url in "${source_urls[@]}"; do
				wget -q --show-progress "${url}" -P ${build_root};
			done;

			echo "Creating build dir backup ...";
			cp -r ${build_root} ${build_root_backup};
		else
			echo "Found build dir backup. Restoring build dir..";
			cp -r ${build_root_backup} ${build_root};
		fi;
	fi;
}

unpack(){
	cd ${build_root};
	files=${build_root}/*;
	for file in $files; do
		if [ "${file##*.}" = "gz" ] || [ "${file##*.}" = "bz2" ] || [ "${file##*.}" = "xz" ]; then
			echo "Extracting ${file}"
			tar xf $file -C ${build_root};
		fi;
	done
}

prepare(){

	cd "${build_root}/mysql-workbench-community-${pkgver}-src/"

	# Disable 'Help' -> 'Check for Updates'
	# Updates are provided via Debian Linux packages
	patch -Np1 < "${debian_dir}"/patches/0001-mysql-workbench-no-check-for-updates.patch

	# disable unsupported operating system warning
	patch -Np1 < "${debian_dir}"/patches/0002-disable-unsupported-operating-system-warning.patch

	# patch taken from debian salsa repo to fix ldconfig bug when starting wb as non-root user. updated.
	patch -Np1 < "${debian_dir}"/patches/projloc.patch

	# GCC 7.x introduced some new warnings, remove '-Werror' for the build to complete
	sed -i '/^set/s|-Werror -Wall|-Wall|' CMakeLists.txt

	# GCC 7.x complains about unsupported flag
	sed -i 's|-Wno-deprecated-register||' ext/scintilla/gtk/CMakeLists.txt

	# disable stringop-truncation for GCC 8.x
	sed -i '/^set/s|-Wall|-Wall -Wno-stringop-truncation|' CMakeLists.txt

	# make sure to link against bundled libraries
	sed -i "/target_link_libraries/s|\\$|-L${srcdir}/install-bundle/usr/lib/ \\$|" backend/wbpublic/CMakeLists.txt

	# change the ANTLR Version to Debian Testings current version
	sed -i "s/antlr-4.7.1-complete.jar/antlr-${_antlr_version}-complete.jar/g" CMakeLists.txt

}

build_mysql(){
	# Build mysql
	mkdir "${srcdir}/mysql-${_mysql_version}-build"
	cd "${srcdir}/mysql-${_mysql_version}-build"
	echo "Configure mysql..."
	cmake "${srcdir}/mysql-${_mysql_version}" \
		-DWITHOUT_SERVER=ON \
		-DBUILD_CONFIG=mysql_release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DSYSCONFDIR=/etc/mysql \
		-DMYSQL_DATADIR=/var/lib/mysql \
		-DWITH_BOOST="${srcdir}/boost_${_boost_version//./_}"
	echo "Build mysql..."
	make -j$((NB_CORES+1)) -l${NB_CORES}
	echo "Install mysql..."
	make DESTDIR="${srcdir}/install-bundle/" install
}

build_connector(){
	# Build mysql-connector-c++
	mkdir "${srcdir}/mysql-connector-c++-${_connector_version}-src-build"
	cd "${srcdir}/mysql-connector-c++-${_connector_version}-src-build"
	echo "Configure mysql-connector-c++..."
	cmake "${srcdir}/mysql-connector-c++-${_connector_version}-src" \
		-Wno-dev \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DINSTALL_LIB_DIR=lib \
		-DWITH_MYSQL="${srcdir}/install-bundle/" \
		-DMYSQL_CONFIG_EXECUTABLE="${srcdir}/install-bundle/usr/bin/mysql_config" \
		-DWITH_BOOST="${srcdir}/boost_${_boost_version//./_}" \
		-DWITH_JDBC=ON
	echo "Build mysql-connector-c++..."
	make -j$((NB_CORES+1)) -l${NB_CORES}
	echo "Install mysql-connector-c++..."
	make DESTDIR="${srcdir}/install-bundle/" install
}

build_workbench(){
	# Build MySQL Workbench itself with bundled libs
	mkdir "${srcdir}/mysql-workbench-community-${pkgver}-src-build"
	cd "${srcdir}/mysql-workbench-community-${pkgver}-src-build"
	echo "Configure mysql-workbench..."
	cmake "${srcdir}/mysql-workbench-community-${pkgver}-src" \
		-Wno-dev \
		-DCMAKE_INSTALL_PREFIX:PATH=/usr \
		-DCMAKE_CXX_FLAGS="-std=c++14" \
		-DCMAKE_BUILD_TYPE=Release \
		-DMySQL_CONFIG_PATH="${srcdir}/install-bundle/usr/bin/mysql_config" \
		-DMySQLCppConn_LIBRARY="${srcdir}/install-bundle/usr/lib/libmysqlcppconn.so" \
		-DMySQLCppConn_INCLUDE_DIR="${srcdir}/install-bundle/usr/include/jdbc" \
		-DWITH_ANTLR_JAR="${srcdir}/antlr-${_antlr_version}-complete.jar" \
		-DUSE_UNIXODBC=True \
		-DBoost_INCLUDE_DIR="${srcdir}/boost_${_boost_version//./_}" \
		-DUSE_BUNDLED_MYSQLDUMP=1
	echo "Build mysql-workbench..."
	make -j$((NB_CORES+1)) -l${NB_CORES}
}

build_all(){
	build_mysql;
	build_connector;
	build_workbench;

}

prepare_deb(){
	# install bundled libraries
	for LIBRARY in $(find "${srcdir}/install-bundle/usr/lib/" -type f -regex '.*/lib\(gdal\|mysql\(client\|cppconn\)\)\.so\..*'); do
		BASENAME="$(basename "${LIBRARY}")"
		SONAME="$(readelf -d "${LIBRARY}" | grep -Po '(?<=(Library soname: \[)).*(?=\])')"
		install -D -m0755 "${LIBRARY}" "${pkgdir}"/usr/lib/mysql-workbench/"${BASENAME}"
		ln -s "${BASENAME}" "${pkgdir}"/usr/lib/mysql-workbench/"${SONAME}"
	done

	# install bundled mysql and mysqldump
	install -m0755 "${srcdir}/install-bundle/usr/bin/mysql"{,dump} "${pkgdir}"/usr/lib/mysql-workbench/

	# install MySQL Workbench itself
	cd "${srcdir}/mysql-workbench-community-${pkgver}-src-build"

	make DESTDIR="${pkgdir}" install

	# icons
	for SIZE in 16 24 32 48 64 96 128; do
		# set modify/create for reproducible builds
		convert -scale ${SIZE} +set date:create +set date:modify \
			"${srcdir}/mysql-workbench-community-${pkgver}-src/images/icons/MySQLWorkbench-128.png" \
			"${srcdir}/mysql-workbench.png"
		install -D -m0644 "${srcdir}/mysql-workbench.png" "${pkgdir}/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps/mysql-workbench.png"
	done
}

create_deb(){
	# changing the user to root on all files
	chown -R root:root ${pkgdir}

	cd ${src_dir}
	dh_testdir
	dh_testroot
	dh_lintian
	dh_installman
	dh_installchangelogs
	dh_installdocs
	dh_strip
	dh_compress --exclude=.mwb
	dh_fixperms -X*.sh
	dh_makeshlibs
	dh_shlibdeps --dpkg-shlibdeps-params=--ignore-missing-info \
		-lusr/lib/mysql-workbench/:usr/lib/mysql-workbench/plugins:usr/lib/mysql-workbench/modules
	dh_gencontrol
	dh_md5sums
	dh_builddeb

	echo "All done."
}

clean(){

	if [ -d ${build_root} ]; then
		echo "Cleaning up build dir..."
		rm -r ${build_root};
	fi

	if [ -d ${debian_dir} ]; then
                echo "Cleaning up old debian dir..."
                rm -r ${debian_dir};
        fi


	if [ -d ${pkgdir} ]; then
		echo "Removing old packaging dir.."
		rm -r ${pkgdir};
	fi
}

clear
root_check
chroot_check
clean
install_builddep
get
unpack
prepare
build_all
prepare_deb
create_deb
exit
