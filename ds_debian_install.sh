#!/bin/bash

server=acps.stellarcyber.ai
release=
os_version=
path=
dsmode=
dsrole=
force_local=

show_netinfo() {
    echo -e "\n######## Kernel Information ########"
    uname -a
    echo -e "\n######## OS Information ########"
    cat /etc/os-release
    echo -e "\n######## CPU Information ########"
    cat /proc/cpuinfo | grep processor | wc -l
    echo -e "\n######## Memory Information ########"
    free -h
    echo -e "\n######## Link Information ########"
    ip link show
}

download_file() {
    curl -k -u user310:HMTe3dJ3cmAPK $1 -o $2 --fail
    if [ $? -ne 0 ]; then
        echo "Fail to download file $1"
        echo "Please check output in $2"
        exit 1
    fi
}

usage() {
    echo "$1 (1.8.1) --version 4.3.7 [--cm <ip address>] [--dev]"
    echo 'version            : Target software version to be installed'
    echo 'cm                 : cm ip'
    echo 'dev                : Development environment support'
    echo 'check              : Show system information'
    echo 'package            : Local package path'
    echo 'mode               : Internal use, agent or container'
    echo 'role               : Internal use, ds or dds'
    exit 1
}

install_libicu57() {
    wget http://launchpadlibrarian.net/317614660/libicu57_57.1-6_amd64.deb
    dpkg -i libicu57_57.1-6_amd64.deb; rm -f libicu57_57.1-6_amd64.deb
}

install_libjsonc2_ubt_20_04() {
    wget http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/multiarch-support_2.27-3ubuntu1_amd64.deb
    dpkg -i multiarch-support_2.27-3ubuntu1_amd64.deb
    rm -rfv multiarch-support_2.27-3ubuntu1_amd64.deb

    wget http://de.archive.ubuntu.com/ubuntu/pool/main/j/json-c/libjson-c2_0.11-4ubuntu2_amd64.deb
    dpkg -i  libjson-c2_0.11-4ubuntu2_amd64.deb
    rm -rfv libjson-c2_0.11-4ubuntu2_amd64.deb
}

if [[ $(id -u) -ne 0 ]] ; then
    echo "Please run the tool as superuser"
    exit 1
fi

if [ -f "/etc/os-release" ]; then
    source /etc/os-release
    if [ "${ID}" != "ubuntu" ] && [ "${ID}" != "debian" ]; then
        echo "Ubuntu and Debian are supported!"
        exit 1
    fi
else
    echo "The Software can be installed on Ubuntu and Debian!"
    exit 1
fi

supported_versions="
14.04
16.04
18.04
19.04
20.04
8
9
10
11
"
supported=0

for ver in $supported_versions; do
    if [ "$ver""x" == "$VERSION_ID""x" ]; then
        supported=1
        break
    fi
done

if [ $supported -eq 0 ]; then
    echo "${ID} ${VERSION_ID} isn't supported"
    exit 0
fi

os_version=${VERSION_ID}
# Debian Stretch share the same package with Ubuntu Bionic
if [ "${VERSION_ID}" == "8" ]; then
    os_version="16.04"
elif [ "${VERSION_ID}" == "9" ]; then
    os_version="18.04"
elif [ "${VERSION_ID}" == "19.04" ]; then
    os_version="18.04"
fi

if [ $# -lt 1 ]; then
    usage $0
fi

OPTS=`getopt -o v:dcp:m:r: --long version:,dev,check,force_local:,package:,mode:,role:,cm: -n "$0" -- "$@"`
eval set -- "$OPTS"

while true ; do
    case "$1" in
        -v | --version )
            release="$2"; shift ;;
        -d | --dev )
            server=apsdev.stellarcyber.ai ;;
        -c | --check )
            show_netinfo; exit 0 ;;
        -p | --package )
            path="$2"; shift ;;
        -m | --mode)
            dsmode="$2"; shift ;;
        -r | --role)
            dsrole="$2"; shift ;;
        -f | --force_local)
            force_local="$2"; shift ;;
        --cm)
            cm_ip=$2 ; shift ;;
        -- ) shift ; break ;;
        * ) break ;;
    esac
    shift
done

if [ -z "${release}" ] && [ -z "${path}" ]; then
    echo "Invalid version!"
    exit 1
fi

if [ -z "${dsmode}" ]; then
    dsmode=agent
fi
if [ -z "${dsrole}" ]; then
    dsrole=ds
fi

if [ "${dsmode}" != "agent" -a "${dsmode}" != "container" ]; then
    echo "Invalid dsmode, only support dsmode: agent or container!"
    exit 1
fi

echo "######## Installing dependencies for DataSensor ########"

if [ "$ID" == "debian" -a "$VERSION_ID" == "11" ]; then
    echo "Special hanlding for $ID $VERSION_ID"
    apt install -y software-properties-common
    add-apt-repository 'deb http://ftp.de.debian.org/debian bullseye main'
    apt-get update
    apt install -y curl ethtool wget lsof zip sshpass
    apt install -y python2
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
    python2 get-pip.py
else
    apt-get update
    apt install -y curl ethtool wget lsof zip sshpass
    apt-get install -y python python-openssl python-psutil
    apt-get install -y python-pip
fi
apt-get install -y libatomic1 libxslt1.1 libxml2 libssh-4 pciutils \
    libcap-ng0 libpcap0.8 libyaml-0-2 net-tools
if [ "$VERSION_ID" == "16.04" ] || [ "$VERSION_ID" == "8" ]; then
    apt install -y libprotobuf-c1 libjson-c2
    if [ "$VERSION_ID" == "8" ]; then
         apt install -y libicu52
    else
         apt install -y libicu55
    fi
elif [ "$VERSION_ID" == "14.04" ]; then
    apt install -y libicu52 libprotobuf-c0 libjson-c2
elif [ "$VERSION_ID" == "18.04" ] || [ "$VERSION_ID" == "19.04" ] || [ "$VERSION_ID" == "9" ] || [ "$VERSION_ID" == "10" ] || [ "$VERSION_ID" == "11" ]; then
    if [ "$VERSION_ID" == "11" ]; then
        apt install -y libjson-c5
    else
        apt install -y libjson-c3
        apt install -y libjson-c-dev
    fi
    apt install -y libcurl3-gnutls libprotobuf-c1
    #XXX libicu57 is not officially released with Bionic
    # which needs to installed from PPA repository
    if [ "$VERSION_ID" == "18.04" ]; then
        install_libicu57
        apt install -y ruamel.yaml
    elif [ "$VERSION_ID" == "19.04" ]; then
        apt install -y libicu63
    elif [ "$VERSION_ID" == "10" ]; then
        apt install -y libicu63
        pip install --ignore-installed pyOpenSSL --upgrade
    elif [ "$VERSION_ID" == "11" ]; then
        apt install -y libicu67
        pip2 install --ignore-installed pyOpenSSL --upgrade
        pip2 install --ignore-installed psutil --upgrade
    else
        apt install -y libicu57
    fi
elif [ "$VERSION_ID" == "20.04" ]; then
    apt install -y libcurl3-gnutls
    apt install -y libprotobuf-c1
    install_libicu57
    install_libjsonc2_ubt_20_04
else
    echo "This tool works with Ubuntu 14.04 16.04 18.04 19.04 and Debian 8, 9, 10, 11"
    exit 0
fi

if [ "$VERSION_ID" == "14.04" ] || [ "$VERSION_ID" == "16.04" ] || [ "$VERSION_ID" == "8" ] || [ "$VERSION_ID" == "9" ]; then
    apt install -y libcurl3
elif [ "$VERSION_ID" == "18.04" ] || [ "$VERSION_ID" == "10" ] || [ "$VERSION_ID" == "11" ] || [ "$VERSION_ID" == "20.04" ]; then
    apt install -y libcurl4
fi

if [ -n "${path}" ]; then
    echo "Install for ${ID} ${VERSION_ID} from $path, force $force_local"

    if [ "$force_local""x" != "yes""x" ]; then
        if [ "${VERSION_ID}" != "16.04" ] && [ "${VERSION_ID}" != "20.04" ]; then
            echo "Only Ubuntu 16.04/20.04 is supported, exit..."
            exit
        fi
    fi

    target=${path}
else
    if [ "${VERSION_ID}" == "8" -o "${VERSION_ID}" == "9"  -o "${VERSION_ID}" == "10"  -o "${VERSION_ID}" == "11" ]; then
         target_package=aellads_${release}debian1-${VERSION_ID}_amd64.deb
    else
         target_package=aellads_${release}ubuntu1-${os_version}_amd64.deb
    fi

    url=https://${server}/release/${release}/datasensor/${target_package}
    target=/tmp/${target_package}
    download_file ${url} ${target}
echo "######## Download package ${target_package} done ########"
fi

dpkg --purge aellade > /dev/null 2>&1
dpkg --purge aellads > /dev/null 2>&1

export DSMODE=${dsmode} DSFEATURE=${dsrole}
dpkg -i --force-overwrite ${target}
echo "######## Install package ${target_package} done ########"

if [ -z "${path}" ]; then
    rm -rf ${target}
    echo "######## Clean package ${target} done ########"
fi

if [ -n "${cm_ip}" ]; then
    sed -i -e "s:cm_ip = 0.0.0.0:cm_ip = ${cm_ip}:g" /etc/aella/aos.yaml
    service aella_conf restart &> /dev/null
fi
