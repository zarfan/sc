#!/bin/bash

# This script is the install script for self-contain linux images

server=acps.stellarcyber.ai
release=
path=
dsmode=
dsrole=
OS_DISTRIBUTOR="Unknown"
OS_VERSION="Unknown"

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

discover_os()
{
    if [ -f /etc/fedora-release ]; then
        if grep Fedora /etc/fedora-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=fedora
            return
        fi
    fi

    if [ -f /etc/centos-release ]; then
        if grep CentOS /etc/centos-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=centos
            return
        fi
    fi

    if [ -f /etc/os-release ]; then
        # e.g. Ubuntu container
        if grep Ubuntu /etc/os-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=ubuntu
            return
        fi
        # Debian
        if grep Debian /etc/os-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=debian
            return
        fi

        if grep SUSE /etc/os-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=suse
            return
        fi

        if grep Oracle /etc/os-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=oracle
            return
        fi

        if grep AlmaLinux /etc/os-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=almalinux
            return
        fi
    fi

    if [ -f /etc/redhat-release ]; then
        OS_DISTRIBUTOR=redhat
        return
    fi

    if [ -f /etc/SuSE-release ]; then
        OS_DISTRIBUTOR=suse
        return
    fi

    if which lsb_release > /dev/null 2>&1; then
        OS_DISTRIBUTOR=$(lsb_release -s -i)
        if [ "$OS_DISTRIBUTOR""x" == "SUSE""x" ];then
            OS_DISTRIBUTOR=suse
        fi
        return
    fi
    if [ "${OS_DISTRIBUTOR}" == "Unknown" ]; then
         ## Amazon linux 2 - redhat 7 equivalence
        if grep 'Amazon Linux 2' /etc/os-release > /dev/null 2>&1; then
            OS_DISTRIBUTOR=amazonlinux
            return
        fi
    fi
}

discover_os_version()
{
    if [ "${OS_DISTRIBUTOR}" == "ubuntu" ]; then
        source /etc/os-release
        OS_VERSION=${VERSION_ID}
    fi

    if [ "${OS_DISTRIBUTOR}" == "debian" ]; then
        source /etc/os-release
        OS_VERSION=${VERSION_ID}
    fi

    if [ "${OS_DISTRIBUTOR}" == "redhat" ]||[ "${OS_DISTRIBUTOR}" == "almalinux" ]||[ "${OS_DISTRIBUTOR}" == "amazonlinux" ]; then
        if grep "Amazon Linux 2" /etc/os-release > /dev/null 2>&1; then
             OS_VERSION=2
        else
             line=`cat /etc/redhat-release`
             line=${line%(*}
             ver=${line##*release}
             ver=`echo $ver | xargs`
             OS_VERSION=${ver%%.*}
        fi
    fi

    if [ "$OS_DISTRIBUTOR" == "centos" ]; then
        if [ -e "/etc/os-release" ]; then
            source /etc/os-release
            OS_VERSION=${VERSION_ID}
        else
            OS_VERSION=$(cat /etc/centos-release | cut -d' ' -f3)
        fi
        OS_VERSION=${OS_VERSION%.*}
    fi

    if [ "$OS_DISTRIBUTOR" == "suse" ]; then
        if [ -e "/etc/os-release" ]; then
            source /etc/os-release
            OS_VERSION=`echo ${VERSION_ID} | cut -d'.' -f1`
	    else
	        major=`cat /etc/SuSE-release|grep 'VERSION = '|cut -d' ' -f3`
	        #patch=`cat /etc/SuSE-release|grep 'PATCHLEVEL= '|cut -d' ' -f3`
	        OS_VERSION="$major"
        fi
    fi

    if [ "$OS_DISTRIBUTOR" == "oracle" ]; then
        if [ -e "/etc/os-release" ]; then
            source /etc/os-release
            OS_VERSION=`echo ${VERSION_ID} | cut -d'.' -f1`
	    else
	        OS_VERSION=$(cat /etc/oracle-release | cut -d' ' -f5)
            OS_VERSION=${OS_VERSION%.*}
        fi
    fi
}

usage() {
    echo "$1 (1.8.2) --version 4.3.601 [--cm <ip address>] [--dev]"
    echo 'version            : Target software version to be installed'
    echo 'cm                 : cm ip'
    echo 'dev                : Development environment support'
    echo 'check              : Show system information'
    echo 'epel6              : Generate epel 6 in /tmp/epel.repo'
    echo 'package            : Local package path'
    echo 'mode               : Internal use, agent or container'
    echo 'role               : Internal use, ds or dds'
    exit 1
}

if [ $# -lt 1 ]; then
    usage $0
fi

OPTS=`getopt -o v:dcp:m:r: --long version:,dev,check,package:,mode:,role:,cm: -n "$0" -- "$@"`
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
        --cm)
            cm_ip=$2 ; shift ;;
        -- ) shift ; break ;;
        * ) break ;;
    esac
    shift
done

discover_os
discover_os_version

supported_os="
oracle-8
almalinux-9
amazonlinux-2
redhat-7
redhat-8
redhat-9
ubuntu-16.04
ubuntu-18.04
ubuntu-20.04
ubuntu-21.04
ubuntu-22.04
suse-12
amazonlinux-2
"
supported=0

for os in $supported_os; do
    if [ "$os""x" == "${OS_DISTRIBUTOR}-${OS_VERSION}""x" ]; then
        supported=1
        break
    fi
done

if [ $supported -eq 0 ]; then
    echo "${OS_DISTRIBUTOR} ${OS_VERSION} isn't supported self-contain package"
    exit 0
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

required_pkgs="
curl
"
echo "Check required packages ..."

for pkg in $required_pkgs; do
    if [ "${OS_DISTRIBUTOR}" == "ubuntu" ]; then
        if dpkg -l | grep -q "^ii\s*$pkg"; then
            echo "$pkg is installed on your system."
        else
            echo "$pkg is not installed on your system, exit."
            exit 1
        fi
    else
        if rpm -q $pkg; then
            echo "$pkg is installed on your system."
        else
            echo "$pkg is not installed on your system, exit."
            exit 1
        fi
    fi
done

if [ -n "${path}" ]; then
    target=${path}
else
    if [ "${OS_DISTRIBUTOR}" == "ubuntu" ]; then
        target_package=aellads_${release}ubuntu1-binary_amd64.deb
    elif [ "${OS_DISTRIBUTOR}" == "suse" ]; then
        target_package=aellads-${release}-1.sles${OS_VERSION}.x86_64.rpm
    else
        target_package=aellads-${release}-1.redhat-binary.x86_64.rpm
    fi
    url=https://${server}/release/${release}/datasensor/${target_package}
    target=/tmp/${target_package}
    download_file ${url} ${target}
    echo "######## Download package ${target_package} done ########"
fi

if [ "${OS_DISTRIBUTOR}" == "ubuntu" ]; then
    dpkg --purge aellade > /dev/null 2>&1
    dpkg --purge aellads > /dev/null 2>&1

    export DSMODE=${dsmode} DSFEATURE=${dsrole}
    dpkg -i --force-overwrite ${target}
else
    rpm -e aellade > /dev/null 2>&1
    rpm -e aellads > /dev/null 2>&1

    export DSMODE=${dsmode} DSFEATURE=${dsrole}
    rpm -ivh --nodeps ${target}
fi
echo "######## Install package ${target} done ########"

if [ -z "${path}" ]; then
    rm -rf ${target}
    echo "######## Clean package ${target} done ########"
fi

if [ -n "${cm_ip}" ]; then
    sed -i -e "s:cm_ip = 0.0.0.0:cm_ip = ${cm_ip}:g" /etc/aella/aos.yaml
    service aella_conf restart &> /dev/null
fi
