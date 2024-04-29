#!/bin/bash
# History:
# =============================
# 8/4/2022 fix amazon linux 2015.03 version issue
#
#
#NAME="Amazon Linux AMI"
#VERSION="2015.03"
#ID="amzn"
#ID_LIKE="rhel fedora"
#VERSION_ID="2015.03"
#PRETTY_NAME="Amazon Linux AMI 2015.03"
#ANSI_COLOR="0;33"
#CPE_NAME="cpe:/o:amazon:linux:2015.03:ga"
#HOME_URL="http://aws.amazon.com/amazon-linux-ami/"
#
# 5/13/2020 fix amazon linux 2 ECS optimzed issue
# 4/08/2020 add redhat 8.0 support
# 4/02/2020 fix oracle linux 7.3 issue
# 4/01/2020 fix redhat 7.3 issue
# 3/26/2020 fix redhat 6.7 issue

server=acps.stellarcyber.ai
release=
path=
dsmode=
dsrole=

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

cat_epel_6() {
    cat > /tmp/epel.repo << _EOF_
[epel]
name=Extra Packages for Enterprise Linux 6 - \$basearch
baseurl=https://archives.fedoraproject.org/pub/archive/epel/6/x86_64
mirrorlist=http://mirrors.fedoraproject.org/metalink?repo=epel-6&arch=\$basearch
failovermethod=priority
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6

[epel-debuginfo]
name=Extra Packages for Enterprise Linux 6 - \$basearch - Debug
baseurl=https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/debug
mirrorlist=http://mirrors.fedoraproject.org/metalink?repo=epel-debug-6&arch=\$basearch
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6
gpgcheck=1

[epel-source]
name=Extra Packages for Enterprise Linux 6 - \$basearch - Source
baseurl=http://download.fedoraproject.org/pub/epel/6/SRPMS
mirrorlist=http://mirrors.fedoraproject.org/metalink?repo=epel-source-6&arch=\$basearch
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6
gpgcheck=1
_EOF_
    echo "epel.repo v6 generated in /tmp/epel.repo"
}

download_file() {
    curl -k -u user310:HMTe3dJ3cmAPK $1 -o $2 --fail
    if [ $? -ne 0 ]; then
        echo "Fail to download file $1"
        echo "Please check output in $2"
        exit 1
    fi
}

check_python_version() {
    PYTHON=$(python -V 2>&1)
    if [ -n "$PYTHON" ]; then
        MAJOR=$(echo $PYTHON | cut -d' ' -f2 | cut -d'.' -f1)
        if [ $MAJOR -gt 2 ]; then
            echo "Python 2 is required to continue, abort..."
            exit 1
        fi
    fi
}

usage() {
    echo "$1 (1.8.2) --version 4.3.7 [--cm <ip address>] [--dev]"
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

OPTS=`getopt -o v:decp:m:r: --long version:,dev,check,epel6,package:,mode:,role:,cm: -n "$0" -- "$@"`
eval set -- "$OPTS"

while true ; do
    case "$1" in
        -v | --version )
            release="$2"; shift ;;
        -d | --dev )
            server=apsdev.stellarcyber.ai ;;
        -c | --check )
            show_netinfo; exit 0 ;;
        -e | --epel6 )
            cat_epel_6; exit 0 ;;
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

if [[ $(id -u) -ne 0 ]] ; then                                                   
    echo "Please run the tool as root"
    exit 1
fi

if [ -f "/etc/os-release" ]; then
    echo "File /etc/os-release found"
    source "/etc/os-release"
fi

if [ ! -f "/etc/redhat-release" ]; then
    ## fixes for Amazon ECS
    if [ -n "${ID_LIKE}" ]; then
        if [[ ${ID_LIKE} != *rhel* ]]; then
             echo "The Software only can be installed on Redhat based OS!"
             exit 1
        fi
    else
        echo "The Software only can be installed on Redhat based OS!"
        exit 1
    fi
fi

check_python_version

if [ -z "${VERSION_ID}" ]; then
    if [ -f "/etc/redhat-release" ]; then
        VERSION_ID=$(cat /etc/redhat-release | cut -d' ' -f7)
        if grep 'Red Hat Enterprise Linux' /etc/redhat-release > /dev/null 2>&1; then
            ID='rhel'
        fi
    fi
    if [ -f "/etc/centos-release" ]; then
        VERSION_ID=$(cat /etc/redhat-release | cut -d' ' -f3)
    fi
else
    if [ "${ID}""x" == "ol""x" ] || [ "${ID}""x" == "amzn""x" ] ; then
          ID='rhel'
    fi
fi

if [ -z "${VERSION_ID}" ]; then
    echo "Unknown version ID, exit...!"
    exit 1
else
    if [ "${VERSION_ID}""x" == "2015.03""x" ] ; then
        sudo sed -i 's/http:\/\/download.fedoraproject.org\/pub\/epel\/6\/\$basearch/https:\/\/archives.fedoraproject.org\/pub\/archive\/epel\/6\/x86_64/g' /etc/yum.repos.d/epel.repo
        sudo sed -i 's/^#baseurl/baseurl/g' /etc/yum.repos.d/epel.repo
        yum-config-manager --enable epel
        VERSION_ID="6"
    fi
fi
MAJOR=${VERSION_ID%.*}
if [ -z "${MAJOR}" ]; then
    echo "Invalid major version id, exit...!"
    exit 1
fi

if [ "$MAJOR" == "8" ]; then
    PM=dnf
else
    PM=yum
fi

## fixes for Amazon linux 2
if [ $MAJOR -lt 6 ]; then
     VERSION_ID=$(rpm -E %{rhel})
     MAJOR=${VERSION_ID}
fi

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

if [ -n "${path}" ]; then
    target=${path}
else
    target_package=aellads-${release}-1.el${MAJOR}.x86_64.rpm
    url=https://${server}/release/${release}/datasensor/${target_package}
    target=/tmp/${target_package}
    download_file ${url} ${target}
    echo "######## Download package ${target_package} done ########"
fi

if [ "$PM" == "dnf" ]; then
    ${PM} makecache
else
    ${PM} makecache fast
fi
# RHEL 6 and CentOS 6
if [ "$MAJOR" == "6" ]; then
    if [ "${ID}""x" == "rhel""x" ]; then
        subscription-manager repos --enable rhel-6-server-extras-rpms
    fi
    ${PM} install -y yum-utils protobuf-compiler protobuf libpcap python python-psutil python-argparse
    ${PM} install -y python-pip
elif  [ "$MAJOR" == "7" ]; then
    if [ "${ID}""x" == "rhel""x" ]; then
        subscription-manager repos --enable rhel-7-server-extras-rpms
        # python-psutil is in rhel-7-server-satellite-tools-6.8-rpms
        subscription-manager repos --enable rhel-7-server-satellite-tools-6.8-rpms
        curl -k -O http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        rpm -i epel-release-latest-7.noarch.rpm
        rm -f epel-release-latest-7.noarch.rpm
        sudo sed -i 's/\(mirrorlist=http\)s/\1/' /etc/yum.repos.d/epel.repo
        ${PM} install -y yum-utils protobuf-compiler protobuf libpcap python python-psutil
    fi
    ${PM} install -y python-pip
elif  [ "$MAJOR" == "8" ]; then
    ${PM} install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
    ## protobuf-compiler and python-psutil not found
    ${PM} install -y yum-utils protobuf libpcap python2 python2-psutil
    pip2 install pyOpenSSL
    alternatives --set python /usr/bin/python2
fi
${PM} install -y libyaml protobuf-c json-c libatomic sshpass lsof \
    libssh curl pciutils ethtool wget zip net-tools

if [ "${ID}""x" != "rhel""x" ]; then
    # Install epel-release repository for python-psutil
    ${PM} --enablerepo=extras install -y epel-release
    # python-argparse is claimed for CentOS 6.x
    ${PM} install -y python-psutil python-argparse
fi

# Install pyOpenSSL with pip2 for redhat 8 currently, must be changed later if
# pip2 isn't neccessary.
# For other centos or redhat, use yum
if [ "$MAJOR""x" != "8""x" -o $"{ID}""x" != "rhel""x" ]; then
    ${PM} install -y pyOpenSSL
fi

rpm -e aellade > /dev/null 2>&1
rpm -e aellads > /dev/null 2>&1

export DSMODE=${dsmode} DSFEATURE=${dsrole}
${PM} localinstall --nogpgcheck -y ${target}
echo "######## Install package ${target} done ########"

rm -f ${target}
echo "######## Clean package ${target} done ########"

if [ -n "${cm_ip}" ]; then
    sed -i -e "s:cm_ip = 0.0.0.0:cm_ip = ${cm_ip}:g" /etc/aella/aos.yaml
    service aella_conf restart &> /dev/null
fi

