#!/bin/sh

# This script is from kernel-general.git, started by chuhu@redhat.com. Also
# ever got updated by liwan@redhat.com with cleanup and let it choose nearest
# lab.

# When testing scratch build, we can setup this url.
# ROOT_URL=http://brew-task-repos.usersys.redhat.com/repos/scratch/llong/
ROOT_URL=${ROOT_URL:-}
kernel_names="kernel kernel-rt kernel-alt kernel-pegas kernel-aarch64 kernel-64k"

Usage(){
    echo "Usage"
    echo "        $(basename $0) [ --nvr <version-number> | --running | --ckirepo <ckirepo> ] --arch [arch] [--rpm | --srpm | --debuginfo | --kabi | --kvm | --devel | --print | --internal | --ktest | --extra ]"
    echo "Example"
    echo "        $(basename $0) --nvr kernel-5.14.0-244.el9 -i"
    echo "        $(basename $0) --nvr kernel-64k-5.14.0-244.el9 -i"
    echo "        $(basename $0) --nvr 5.14.0-244.el9 --variant 64k -i"
    echo "        $(basename $0) --nvr 3.10.0-123.el7 --arch x86_64 --rpm"
    echo "        $(basename $0) --nvr 3.10.0-123.el7 --srpm"
    echo "        $(basename $0) --nvr 3.10.0-370.el7 --debuginfo"
    echo "        $(basename $0) --nvr 4.18.0-165.el8 --debugkernel --internal" # rhel-8 kernel-debug-internal-module
    echo "        $(basename $0) --nvr 4.18.0-165.el8 --internal" # rhel-8 kernel-internal-module
    echo "        $(basename $0) --nvr 4.18.0-165.el8 --extra" # rhel-8 kernel-modules-extra
    echo "        $(basename $0) --nvr 2.6.32-637.el6 --fw"     # firmware rpm
    echo "        $(basename $0) --nvr 3.10.0-123.el7 --print"  # print all the pkgs
    echo "        $(basename $0) --devel -i --running " # install the kernel-devel for the running kernel
    echo "        $(basename $0) --kvm -i --running " # install the kernel-rt-kvm for the running kernel-rt
    echo "        $(basename $0) --ckirepo 'HTTP_URL/3.10.0-1160.21.1.el7.test.\$basearch' --devel -i" # install the kernel-devel for the running kernel from the cki test repo
    echo "        $(basename $0) --brewrepo htp://brew-task-repos.usersys.redhat.com/repos/scratch/jlelli/kernel-rt/4.18.0/193.48.1.rt13.98.el8_2.mreq230.1/x86_64/ --devel -i " # install the kernel-devel for the running kernel from the cki test repo
    echo
    echo " Provide a non-brew url base link (ROOT_URL):"
    echo "        ROOT_URL=http://brew-task-repos.usersys.redhat.com/repos/scratch/llong/ $(basename $0) --nvr 3.10.0-957.37.1.el7.bz1751558_test_RH_Unsupported --srpm"  # print all the pkgs
    echo
    echo " Fedora kernel install with (ROOT_URL):"
    echo "        ROOT_URL=https://kojipkgs.fedoraproject.org/packages ./wget-kernel.sh --nvr 5.6.4-300.fc32 -i"
    echo

    echo " Install directlly (-i):"
    echo "        $(basename $0) --nvr 3.10.0-123.el7 --srpm -i"
}

function check_existence()
{
    local url=$1
    curl --head -s -f $url -o /dev/null
}

# cki test kernel repo is not stored in brew, but in different location and url pattern
# Assume the repo below is already been put under /etc/yum.repos.d/XXXX.repo by beaker job.
# Or provide the repo address with '--ckirepo xxxxxxxxxx'

basearch=${arch:-$(uname -m)}

init_vars_repo_cki()
{
    ((use_cki_kernel)) || return

    # For the eval translating '$basearch' in the url.
    basearch=${arch:-$(uname -m)}

    if test -n "$cki_repo"; then
        eval def_url_cki="$cki_repo"
    elif test -n "$CKI_REPO"; then
        eval def_url_cki="$CKI_REPO"
    else
        eval def_url_cki="$(awk -F= 'BEGIN{IGNORECASE=1} /baseurl=.*CKI/ {getline l; if (l == "enabled=1") print $2}' /etc/yum.repos.d/*.repo | head -n1)"
    fi

    if echo $def_url_cki | grep -q "$(uname -m)-debug"; then
        echo "Using cki repo: $def_url_cki"
        use_debug_repo=1
        cki_repo_produ=$(echo $def_url_cki | sed 's/'$(uname -m)'-debug/'$(uname -m)'/')
        cki_repo_debug=$def_url_cki
    else
        echo "Using cki repo: $def_url_cki"
        use_debug_repo=0
        cki_repo_produ=$def_url_cki
        cki_repo_debug=$(echo $def_url_cki | sed 's/\/'$(uname -m)'\//\/'$(uname -m)'-debug\//')
    fi

    return 0
}

init_vars_repo_brew()
{
    # For the eval translating '$basearch' in the url.
    basearch=${arch:-$(uname -m)}
    ((use_brew_kernel)) || return

    if test -z "$brew_repo"; then
        eval brew_repo="$(awk -F= 'BEGIN{IGNORECASE=1} /baseurl=.*brew/ {getline l; if (l == "enabled=1") print $2}' /etc/yum.repos.d/*.repo | head -n1)"
        shopt -s extglob
        ROOT_URL=$brew_repo
        ROOT_URL=${ROOT_URL%kernel*}
        ROOT_URL=${ROOT_URL%%+(/)}
        shopt -u extglob
    fi
}

init_vars()
{
    src_folder_names="src noarch $(uname -m)"
    arch=${arch:-$(uname -m)}

    HOST=$(hostname)
    case ${HOST} in
        *nay*) def_url="http://download.eng.pek2.redhat.com/pub/rhel/brewroot/packages";;
        *pek*) def_url="http://download.eng.pek2.redhat.com/pub/rhel/brewroot/packages";;
        *rdu*) def_url="http://download.eng.rdu.redhat.com/pub/rhel/brewroot/packages";;
        *bos*) def_url="http://download.devel.redhat.com/brewroot/packages";;
        *brq*) def_url="http://download.eng.brq.redhat.com/brewroot/packages";;
        *tlv*) def_url="http://download.eng.tlv.redhat.com/pub/brewroot/packages";;
        *blr*) def_url="http://download.eng.blr.redhat.com/brewroot/packages";;
        *pnq*) def_url="http://download.eng.pnq.redhat.com/brewroot/packages";;
        *) def_url="http://download.devel.redhat.com/brewroot/packages";;
    esac

    def_url=${ROOT_URL:-$def_url}

    if ((debugkernel)); then
        check_var=debug_rpm_url
    else
        check_var=rpm_url
    fi

    if [[ "$variant" =~ 64k ]]; then
        kernel_names="kernel-64k"
    elif [ -n "$variant" ]; then
        echo "Unknown kernel variant: $variant!"
    fi
    kernel_mar=$(echo $version | cut -d. -f1)
    kernel_mir=$(echo $version | cut -d. -f2)
    kernel_rma=$(echo $release | cut -d. -f1)

    local found=0
    # folder name may be different from rpm name, like kernel-64k/rt may be in kernel folder.
    for pkg_name in $kernel_names; do
        sub_path=${pkg_name}
        sub_name=${pkg_name}
        [[ $pkg_name =~ kernel-alt|kernel-64k ]] && sub_path=kernel
        # after 5.14.0-285.el9, kernel-rt also stores in kernel folder in brew
        if [ $kernel_mar -gt 5 ] || [ $kernel_mar -eq 5 -a $kernel_rma -ge 285 ]; then
            sub_path=kernel
        fi
        path_prefix=${def_url}/$sub_path/${version}/${release}
        doc_url="${path_prefix}/$arch/${sub_name}-devel-${version}-${release}.$arch.rpm"
        rpm_url="${path_prefix}/$arch/${sub_name}-${version}-${release}.$arch.rpm"
        debug_rpm_url="${path_prefix}/$arch/${sub_name}-debug-${version}-${release}.$arch.rpm"
        rt_kvm_url="${path_prefix}/$arch/${sub_name}-kvm-${version}-${release}.$arch.rpm"
        echo "Checking existence of $(switch_to_final_url ${!check_var})" 1>&2
        check_existence $(switch_to_final_url ${!check_var}) && found=1 && break
        ((found == 1)) && break
    done

    # Fall back to bos when package do not exist in local globalsync server.
    if [ "$found" = 0 ]; then
        if [[ $def_url =~ brewroot ]]; then
            def_url="http://download.devel.redhat.com/brewroot/packages"
            echo "Fall back to bos server $def_url"
        fi
        for pkg_name in $kernel_names; do
            if [[ ! $def_url =~ brewroot ]]; then
                break
            fi
            sub_path=${pkg_name}
            sub_name=${pkg_name}
            [[ $pkg_name =~ kernel-alt|kernel-64k ]] && sub_path=kernel
            # after 5.14.0-285.el9, kernel-rt also stores in kernel folder in brew
            if [ $kernel_mar -gt 5 ] || [ $kernel_mar -eq 5 -a $kernel_rma -ge 285 ]; then
                sub_path=kernel
            fi
            path_prefix=${def_url}/$sub_path/${version}/${release}
            doc_url="${path_prefix}/$arch/${sub_name}-devel-${version}-${release}.$arch.rpm"
            rpm_url="${path_prefix}/$arch/${sub_name}-${version}-${release}.$arch.rpm"
            rt_kvm_url="${path_prefix}/$arch/${sub_name}-kvm-${version}-${release}.$arch.rpm"
            debug_rpm_url="${path_prefix}/$arch/${sub_name}-debug-${version}-${release}.$arch.rpm"
            echo "Checking existence of $(switch_to_final_url ${!check_var})" 1>&2
            check_existence $(switch_to_final_url ${!check_var}) && found=1 && break
            ((found == 1)) && break
        done
    fi

    release=${release/.[[:alpha:]]*/}.$dist

    ((found==0)) && echo "failed to find the $(switch_to_final_url ${!check_var})" 1>&2 && exit
    echo "$(switch_to_final_url ${!check_var}) existed." 1>&2

    if ((debugkernel == 1)); then
        debuginfo_url="${path_prefix}/$arch/${sub_name}-debug-debuginfo-${version}-${release}.$arch.rpm ${path_prefix}/$arch/${sub_path}-debuginfo-common-$arch-${version}-${release}.$arch.rpm"
        dev_url="${path_prefix}/$arch/${sub_name}-debug-devel-${version}-${release}.$arch.rpm"
    else
        dev_url="${path_prefix}/$arch/${sub_name}-devel-${version}-${release}.$arch.rpm"
        debuginfo_url="${path_prefix}/$arch/${sub_name}-debuginfo-${version}-${release}.$arch.rpm ${path_prefix}/$arch/${sub_path}-debuginfo-common-$arch-${version}-${release}.$arch.rpm"
    fi

    if [ $kernel_mar -gt 4 ] || [ $kernel_mar -eq 4 -a $kernel_mir -ge 16 ]; then
        rpm_url+=" ${path_prefix}/$arch/${pkg_name}-modules-${version}-${release}.$arch.rpm"
        rpm_url+=" ${path_prefix}/$arch/${pkg_name}-core-${version}-${release}.$arch.rpm"
        debug_rpm_url+=" ${path_prefix}/$arch/${pkg_name}-debug-modules-${version}-${release}.$arch.rpm"
        debug_rpm_url+=" ${path_prefix}/$arch/${pkg_name}-debug-core-${version}-${release}.$arch.rpm"
        if check_existence $(switch_to_final_url ${path_prefix}/$arch/${pkg_name}-modules-core-${version}-${release}.$arch.rpm); then
            rpm_url+=" ${path_prefix}/$arch/${pkg_name}-modules-core-${version}-${release}.$arch.rpm"
            debug_rpm_url+=" ${path_prefix}/$arch/${pkg_name}-debug-modules-core-${version}-${release}.$arch.rpm"
        fi
        if ((debugkernel == 1)); then
            internal_module_url="${path_prefix}/$arch/${pkg_name}-debug-modules-internal-${version}-${release}.$arch.rpm"
            extra_module_url="${path_prefix}/$arch/${pkg_name}-debug-modules-extra-${version}-${release}.$arch.rpm"
            kselftest_url="${path_prefix}/$arch/${pkg_name}-debug-selftests-internal-${version}-${release}.$arch.rpm"
        else
            internal_module_url="${path_prefix}/$arch/${pkg_name}-modules-internal-${version}-${release}.$arch.rpm"
            extra_module_url="${path_prefix}/$arch/${pkg_name}-modules-extra-${version}-${release}.$arch.rpm"
            kselftest_url="${path_prefix}/$arch/${pkg_name}-selftests-internal-${version}-${release}.$arch.rpm"
        fi
    fi

    src_url="${path_prefix}/src/${sub_path}-${version}-${release}.src.rpm"
    check_existence $(switch_to_final_url $src_url)
    [ $? -ne 0 ] && src_url="${path_prefix}/noarch/${sub_path}-${version}-${release}.src.rpm"
    check_existence $(switch_to_final_url $src_url)
    # Brew scratch build
    [ $? -ne 0 ] && src_url="${path_prefix}/$(uname -m)/${sub_path}-${version}-${release}.src.rpm"

    abi_url=${path_prefix}/noarch/kernel-abi-whitelists-${version}-${release}.noarch.rpm
    fmw_url="${path_prefix}/noarch/kernel-firmware-${version}-${release}.noarch.rpm"
    doc_url=${path_prefix}/noarch/kernel-doc-${version}-${release}.noarch.rpm
    perf_url="${path_prefix}/$arch/perf-${version}-${release}.$arch.rpm"
}


function get_alllist(){
    local pkg_name_list="kernel kernel-debug kernel-debug-debuginfo kernel-debuginfo-common"
    pkg_name_list+=" kernel-headers perf perf-debuginfo python-perf python-perf-debuginfo"
    pkg_name_list+=" kernel-devel"

    local pkg
    for pkg in $pkg_name_list; do
        echo $path_prefix/$arch/${pkg}-${version}-${release}.$arch.rpm
    done

    echo $path_prefix/src/${sub_path}-${version}-${release}.src.rpm
    echo $path_prefix/noarch/kernel-firmware-${version}-${release}.noarch.rpm
    echo $path_prefix/noarch/kernel-doc-${version}-${release}.noarch.rpm
    echo $path_prefix/noarch/kernel-abi-whitelists-${version}-${release}.noarch.rpm
}

function switch_to_final_url()
{
    # debuginfo_url contains two links separated with white space
    local origin="$*"
    local final
    local single_link
    local krpm
    if ((use_cki_kernel)); then
        for single_link in $origin; do
            krpm=$(basename $single_link)
            echo $krpm | grep -q srpm && final+="${cki_repo_produ}/$krpm " && continue
            ((debugkernel)) && final+="$cki_repo_debug/$krpm " || final+="${cki_repo_produ}/$krpm "
        done
        echo $final
        return
    fi
    echo $origin
}

function download_rpm()
{
    local url_var
    declare -A compound_urls
    local url_dirname
    local url_basename

    function map_compound_url()
    {
        local input_url=$1
        local comp=0
        for u in $input_url; do
            local url_dirname=$(dirname $u)
            local url_basename=$(basename $u)
            for ub in ${!compound_urls[*]}; do
                if [ "$ub" = "$url_dirname" ]; then
                    comp=1
                    compound_urls[$url_dirname]+=",$url_basename"
                    break
                fi
            done
            [ "$comp" = 1 ] || { compound_urls[$url_dirname]="$url_basename"; }
            comp=0
        done
    }

    for url_var in ${list_url}; do
        url+="$(switch_to_final_url ${!url_var}) "
    done
    # If we get an empty url, that means we are using the default usage (just for
    # kernel install) with cli like below:
    # $ sh wget-kernel.sh --nvr xxxxxxx or sh wget-kernel.sh --nvr xxxx --debugkernel
    if [ -z "${url}" ]; then
        if ((debugkernel)); then
            url=$(switch_to_final_url $debug_rpm_url)
        else
            url=$(switch_to_final_url $rpm_url)
        fi
    fi
    if [ -z "${url// /}" ]; then
        echo  "Don't support "${list_url// /}" in this kernel version"
        exit 0
    fi
    map_compound_url "$url"

    echo -n "wget "
    for url_dirname in ${!compound_urls[*]}; do
            local nr_basename=$(echo "${compound_urls[$url_dirname]}" | awk -F, '{print NF}')
            if ((nr_basename > 1)); then
                echo $url_dirname/"{"${compound_urls[$url_dirname]}"}"
            else
                echo $url_dirname/${compound_urls[$url_dirname]}
            fi
    done
    rpm -q wget &>/dev/null || yum -y install wget >/dev/null
    wget -q ${url} && echo "Succeed."
    ret=$?
    [ $ret -ne 0 ] && echo FAILED
    if [ $ret -ne 0 ] && ((use_cki_kernel==0)); then
        stupid_url=$(echo ${url} | sed 's/eng\..*\.redhat/lab\.bos\.redhat/' | sed 's/\/pub\//\//;s/\/rhel\//\//;s/download-node-02/download/')
        wget $stupid_url
        [ $? -ne 0 ] && "echo download $stupid_url failed" && exit 1
    fi

    if ((install)); then
        local url_list=${url}
        local u=""
        local pkg=""
        for u in $url_list; do
            pkg+=" $(basename ${u})"
        done
        echo "Installing $pkg"
        if echo $pkg | grep -q -e "kernel-rt-[0-4]\." -e "kernel-rt-debug-[0-4]\." -e "kernel-rt.*modules-[0-4]\."; then
            rpm -q rt-setup || yum install -y rt-setup
        elif echo $pkg | grep -q -e "kernel-rt-[0-9]" -e "kernel-rt-debug-[0-9]" -e "kernel-rt.*modules"; then
            rpm -q realtime-setup || yum install -y realtime-setup
        fi
        rpm -ivh $pkg --force
        ret=$?
        [ $ret -ne 0 ] && echo "force install $pkg failed" \
            && echo "Trying to use yum localinstall $pkg" && yum localinstall -y --nogpgcheck $pkg && ret=$?
        [ $ret -ne 0 ] && echo "force install and yum localinstall $pkg failed" && return 1
    fi
}

# ------- start ------------
TEMP=$(getopt -o vd:aipt -l cki:,brewrepo:,brew:,ckirepo:,srpm,rpm,kabi,perf,fw,install,arch:,debuginfo,debugkernel,internal,int,extra,ext,ktest,curr,running,nvr:,kvm,devel,print,variant:, -n 'example.bash' -- "$@")
if [ $? != 0 ]; then echo "Terminating..." >&2; exit 1; fi
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -p|--print) exec_cmd=get_alllist;shift ;;
        --int|--internal) list_url+=" internal_module_url" ;internal_module=1;shift;;
        --ext|--extra) list_url+=" extra_module_url" ;extra_module=1;shift;;
        -t|--ktest) list_url+=" kselftest_url"; kselftest=1;shift;;
        --kabi)  list_url+=" abi_url";shift;;
        --rpm)   list_url+=" rpm_url";shift 1;;
        --devel) list_url+=" dev_url";shift 1;;
        --srpm)  list_url+=" src_url";shift 1;;
        --perf)  list_url+=" perf_url";shift 1;;
        --curr|--running)
                current=$(uname -r | sed -e 's/.'$(uname -m)'//' -e 's/[.+-]debug//' -e 's/[.+]64k//' -e 's/[.+]rt//')
                uname -r | grep -Eq '[+.-]debug' && debugkernel=1
                uname -r | grep -q '+64k' && kernel_64k=1 && kernel_names=kernel-64k
                uname -r | grep -q '+rt' && kernel_rt=1 && kernel_names=kernel-rt
                version=${current%%-*}
                release=${current#*-}
                dist=$(echo $release | grep -Eo "[[:alpha:]].*$")
                 # try cki kernel in there's repo in repos.d
                uname -r | grep -iEq "test|mr|[0-9]{1,}_[0-9]{9,}.el[0-9]" && grep -iEq "/s3.upshift.*${version}-${release}" /etc/yum.repos.d/*.repo && use_cki_kernel=1
                grep -iEq "brew.*${version}.*${release}" /etc/yum.repos.d/*.repo && use_brew_kernel=1
                shift 1;;
        --fw)    list_url+=" fmw_url";shift 1;;
        --arch)  arch=$2;shift 2;;
        -i|--isntall)  install=1; shift 1;;
        --nvr)
            echo "$2" | grep "^[a-zA-Z]" -qE && kernel_names=${2%%-[0-9].*}
            version_release=$(echo $2| grep -oE "[[:digit:]]\..*$")
            version=${version_release%%-*}
            release=${version_release#*-}
            dist=$(echo $release | grep -Eo "[[:alpha:]].*$")
            # try cki kernel in there's repo in repos.d
            echo "$release" | grep -iEq "test|mr|[0-9]{4,}_[0-9]{9,}.el[0-9]" && grep -iEq "cki.*${version}-${release}" /etc/yum.repos.d/*.repo && use_cki_kernel=1
            grep -iEq "brew.*${version}.*${release}" /etc/yum.repos.d/*.repo && use_brew_kernel=1
            shift 2;;
        --debuginfo|-d) list_url+=" debuginfo_url"; debuginfo=1; shift;;
        --debugkernel) debugkernel=1;shift;;
        --variant) variant=$2;shift 2;;
        --kvm) list_url+=" rt_kvm_url";shift;;
        --ckirepo)
            shopt -s extglob
            # remove trailing '/' in the end
            eval cki_repo=${2%%+(/)}; use_cki_kernel=1
            shopt -u extglob
            version_release_arch=$(basename $cki_repo)
            version_release=${version_release_arch%.$(uname -m)}
            version=${version_release%%-*}
            release=${version_release#*-}
            dist=$(echo $release | grep -Eo "[[:alpha:]].*$")
            shift 2 ;;
        --brewrepo|--brew)
            shopt -s extglob
            # remove trailing '/' in the end
            eval brew_repo=${2%%+(/)};
            use_brew_kernel=1
            # http://brew-task-repos.usersys.redhat.com/repos/scratch/jlelli/kernel-rt/4.18.0/193.48.1.rt13.98.el8_2.mreq230.1/x86_64/
            ROOT_URL=$brew_repo
            ROOT_URL=${ROOT_URL%kernel*}
            ROOT_URL=${ROOT_URL%%+(/)}
            kernel_names=$(echo $brew_repo | awk -F/ '{print $(NF-3)}')
            version=$(echo $brew_repo | awk -F/ '{print $(NF-2)}')
            release=$(echo $brew_repo | awk -F/ '{print $(NF-1)}')
            dist=$(echo $release | grep -Eo "[[:alpha:]].*$")
            shopt -u extglob
            shift 2 ;;
        # Assume there's a repo ready in /etc/yum.repos.d/ for CKI test kernel.
        --cki) use_cki_kernel=1; shift 1;;
        --)     shift; break;;
        *)      Usage;exit 1;;
        esac
done

if [ -n "${dist// /}" ] && [ "$(echo $dist | sed -n 's/.*el\([0-9]\).*$/\1/p')" -le "9" ] &&
    [ "${dist}" == "el7a" ] && [ "${version}" == "4.11.0" ]; then
    echo "el7a to el7"
    dist="el7"
    release=${release/a/}
fi

for a do
    echo '--> '"\`$a'";
done


init_vars_repo_brew
[[ ! $dist  =~ [[:alpha:]]* || $release = "" ]] && Usage && exit 1
init_vars_repo_cki
init_vars
if [ -n "$exec_cmd" ]; then
    $exec_cmd
else
    download_rpm
fi
exit 0
