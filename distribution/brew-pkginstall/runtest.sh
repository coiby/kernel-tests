#!/bin/bash

# This script will use brewkoji package to download all rpms from the build nvr,
# it will create a local repo with the rpms and it will try to install the provides package names.

set -x

if [[ -z "${BUILD_NVR}" ]]; then
    echo "ERROR: BUILD_NVR is not set."
    rstrnt-report-result "build_nvr" WARN
    rstrnt-abort recipe
    exit 0
fi

if [[ "${BUILD_NVR}" =~ kernel ]]; then
    echo "ERROR: don't use this script to install kernel packages."
    rstrnt-report-result "kernel-rpms" WARN
    rstrnt-abort recipe
    exit 0
fi

repo_directory=/tmp/"${BUILD_NVR}"
repo_file_path=/etc/yum.repos.d/brew-pkginstall.repo

install_brew() {
    rhel_major=$(rpm -E %rhel)
    if [[ -z ${rhel_major} ]]; then
        echo "ERROR: It is not running on RHEL."
        cat /etc/os-release
        rstrnt-report-result "install_brew" WARN
        rstrnt-abort recipe
        exit 0
    fi

    baseurl="http://download.devel.redhat.com/rel-eng/RCMTOOLS"

    case "${rhel_major}" in
        9|10)
            curl -L --retry 5 "${baseurl}/rcm-tools-rhel-${rhel_major}-baseos.repo" > /etc/yum.repos.d/rcm-tools.repo
            ;;
        *)
            echo "ERROR: release ${rhel_major} is not supported."
            cat /etc/os-release
            rstrnt-report-result "install_brew" WARN
            rstrnt-abort recipe
            exit 0
            ;;
    esac

    if ! dnf install -y brewkoji; then
        echo "ERROR: couldn't install brewkoji."
        rstrnt-report-result "install_brew" WARN
        rstrnt-abort recipe
        exit 0
    fi
}

install_createrepo() {
    if ! dnf install -y createrepo_c; then
        echo "ERROR: couldn't install createrepo_c."
        rstrnt-report-result "createrepo" WARN
        rstrnt-abort recipe
        exit 0
    fi
}

create_build_repo() {
    mkdir -p "${repo_directory}"
    pushd "${repo_directory}"

    if ! brew download-build "${BUILD_NVR}" --arch="$(arch)" --arch=noarch; then
        echo "ERROR: couldn't download build rpms."
        rstrnt-report-result "download-rpms" WARN
        rstrnt-abort recipe
        exit 0
    fi
    createrepo .
    popd

    # Create a repo file
    (
        echo "[${BUILD_NVR}]"
        echo "name=${BUILD_NVR}"
        echo "baseurl=file:///tmp/${BUILD_NVR}"
        echo "enabled=1"
        echo "gpgcheck=0"
    ) > "${repo_file_path}"

}

main() {
    if [[ -f ./needs_reboot ]]; then
        rm -f ./needs_reboot
        echo "INFO: rebooted after $BUILD_NVR was installed"
        rstrnt-report-result "brew-pkginstall" PASS
    else
        rpm -q brewkoji || install_brew
        rpm -q createrepo_c || install_createrepo

        create_build_repo

        if [[ -z "${PACKAGES_NAMES:-}" ]]; then
            PACKAGES_NAMES="${BUILD_NVR}"
        fi

        repofrompath="brewrpm,${repo_directory}"

        packages_nvr=$(dnf repoquery --nvr --quiet  --disablerepo=* --repofrompath="${repofrompath}" ${PACKAGES_NAMES})

        if ! dnf install --disablerepo=* --repofrompath="${repofrompath}" -y ${packages_nvr}; then
                echo "ERROR: couldn't install package rpms."
                rstrnt-report-result "install-rpms" WARN
                rstrnt-abort recipe
                exit 0
        fi
        rm -rf "${repo_directory}"
        rm -f "${repo_file_path}"

        if ! rpm -q ${packages_nvr}; then
            echo "ERROR: packages not installed properly."
            rstrnt-report-result "install-rpms" WARN
            rstrnt-abort recipe
            exit 0
        fi

        if ! dnf needs-restarting -r; then
            touch ./needs_reboot
            rstrnt-reboot
        else
            rstrnt-report-result "brew-pkginstall" PASS
        fi
    fi
}

main
