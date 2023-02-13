#!/bin/bash

TEST="distribution/kpkginstall"
TEST_DEPS="elfutils-libelf-devel flex bison gcc openssl-devel make curl grubby tar binutils"
ARCH=$(uname -m)
REBOOTCOUNT=${RSTRNT_REBOOTCOUNT:-0}
YUM=""
PACKAGE_NAME=""

# supported kernel packages
SUPPORTED_KERNEL_PKGS=(kernel kernel-core kernel-debug kernel-debug-core \
kernel-rt kernel-rt-core kernel-rt-debug kernel-rt-debug-core \
kernel-automotive kernel-automotive-debug \
kernel-64k kernel-64k-debug)

# default values for URL parameters
KPKG_VAR_DEBUG_KERNEL="false"

# Bring in library functions.
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
source "${CDIR}"/../../cki_lib/libcki.sh

function parse_kpkg_url_variables()
{
  # The KPKG_URL can contain variables after a pound sign that are important
  # for this script. For example:
  #    https://example.com/job/12345/repo#package_name=kernel-rt&amp;foo=bar
  # In those situations we need to:
  #   1) Remove the pound sign and variables from KPKG_URL
  #   2) Parse those URL variables into shell variables

  # Get the params from the end of KPKG_URL
  KPKG_PARAMS=$(grep -oP "\#\K(.*)$" <<< "$KPKG_URL")

  # Clean up KPKG_URL so that it contains only the URL without variables.
  KPKG_URL=${KPKG_URL%\#*}

  # Kudos to Dennis for the inspiration here:
  #   https://stackoverflow.com/questions/3919755/how-to-parse-query-string-from-a-bash-cgi-script
  saveIFS=$IFS                    # Store the current field separator
  IFS='=&'                        # Set a new field separate for parameter delimiters
  # shellcheck disable=SC2206
  parm=(${KPKG_PARAMS/&amp;/\&}) # Split the variables into their pieces
  IFS=$saveIFS                    # Restore the original field separator

  # Loop over the variables we found and set KPKG_VAR_"KEY" = VALUE. We make
  # all keys uppercase for consistency.
  for ((i=0; i<${#parm[@]}; i+=2))
  do
    cki_print_success "Found URL parameter: ${parm[i]^^}=${parm[i+1]}"
    readonly "KPKG_VAR_${parm[i]^^}=${parm[i+1]}"
  done
}

function set_package_name()
{
  # Recover the saved package name from KPKG_PACKAGE_NAME if it exists.
  if [ -f "/var/tmp/kpkginstall/KPKG_PACKAGE_NAME" ]; then
    PACKAGE_NAME=$(cat /var/tmp/kpkginstall/KPKG_PACKAGE_NAME)
    cki_print_success "Found cached package name on disk: ${PACKAGE_NAME}"
    return
  fi

  # If the pipeline provides the package name after the # sign in the URL, we
  # can use that here and be done really fast.
  if [ -n "${KPKG_VAR_PACKAGE_NAME:-}" ]; then
    PACKAGE_NAME=$KPKG_VAR_PACKAGE_NAME
    cki_print_success "Found package name in URL variables: ${PACKAGE_NAME}"
  fi

  # Append "-debug" if we were asked to install the debug kernel.
  if cki_is_true "${KPKG_VAR_DEBUG_KERNEL}"; then
    cki_print_info "Debug kernel was requested -- appending -debug to package name"
    PACKAGE_NAME=${PACKAGE_NAME}-debug
  fi

  # Write the PACKAGE_NAME to a file so we have it after reboot.
  echo -n "${PACKAGE_NAME}" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
  cki_print_success "Package name is set: ${PACKAGE_NAME} (cached to disk)"
}

function get_kpkg_ver()
{
  # Recover the saved package name from KPKG_KVER if it exists.
  if [ -f "/var/tmp/kpkginstall/KPKG_KVER" ]; then
    KVER=$(cat /var/tmp/kpkginstall/KPKG_KVER)
    cki_print_success "Found kernel version string in cache on disk: ${KVER}"
    return
  fi

  if [[ "${KPKG_URL}" =~ .*\.tar\.gz ]] ; then
    declare -r kpkg=${KPKG_URL##*/}
    KVER=$(tar tf "$kpkg" | sed -n 's/^boot\/vmlinu[xz]\(-kbuild\)\?-//p' | head -n 1)
  else
    if [[ "${KPKG_URL}" =~ ^[^/]+/[^/]+$ ]] ; then
      # Repo names in configs are formatted as "USER-REPO", so take the kpkgurl
      # and change / to -
      REPO_NAME=${KPKG_URL/\//-}
    else
      REPO_NAME='kernel-cki'
    fi
    cki_print_info "Repo Name set REPO_NAME=$REPO_NAME"

    # Grab the kernel version from the provided repo directly
    KVER=$(
      ${YUM} -q --disablerepo="*" --enablerepo="${REPO_NAME}" list "${ALL}" "${PACKAGE_NAME}" --showduplicates \
        | tr "\n" "#" | sed -e 's/# / /g' | tr "#" "\n" \
        | grep -m 1 "$ARCH.*${REPO_NAME}" \
        | awk -v arch="$ARCH" '{print $2"."arch}'
    )
  fi

  # Write the KVER to a file so we have it after reboot.
  echo -n "${KVER}" > /var/tmp/kpkginstall/KPKG_KVER
}

function targz_install()
{
  declare -r kpkg=${KPKG_URL##*/}
  cki_print_info "Fetching kpkg from ${KPKG_URL}"

  if curl -sOL "${KPKG_URL}" 2>&1; then
    cki_print_success "Downloaded kernel package successfully from ${KPKG_URL}"
  else
    cki_abort_recipe "Failed to download package from ${KPKG_URL}" WARN
  fi

  cki_print_info "targz_install: Extracting kernel version from ${KPKG_URL}"
  get_kpkg_ver
  if [ -z "${KVER}" ]; then
    cki_abort_recipe "targz_install: Failed to extract kernel version from the package" FAIL
  else
    cki_print_success "Kernel version is ${KVER}"
  fi

  if tar xfh "${kpkg}" -C / 2>&1; then
    cki_print_success "Extracted kernel package successfully: ${kpkg}"
  else
    cki_abort_recipe "Failed to extract kernel package: ${kpkg}" WARN
  fi

  cki_print_info "Applying architecture-specific workarounds (if needed)"
  case ${ARCH} in
    ppc64|ppc64le)
      if [ -f "/boot/vmlinux-kbuild-${KVER}" ]; then
        mv "/boot/vmlinux-kbuild-${KVER}" "/boot/vmlinuz-${KVER}"
      fi
      # vmlinux shouldn't be necessary and just uses too much space on /boot
      rm -f "/boot/vmlinux-${KVER}"
      ;;
    s390x)
      # These steps are required until the following patch is backported into
      # the kernel trees: https://patchwork.kernel.org/patch/10534813/

      # Check to see if vmlinuz is present (it's a sign that upstream patch)
      # has merged)
      if [ -f "/boot/vmlinuz-${KVER}" ]; then
        # Remove the vmlinux from /boot and use only the vmlinuz
        rm -f "/boot/vmlinux-${KVER}"
      else
        # Copy over the vmlinux-kbuild binary as a temporary workaround. With
        # newer kernels, this is identical to the missing bzImage. With older
        # (3.10) kernels, the vmlinux-kbuild marks built "image" instead of
        # "bzImage", which is still bootable by s390x.
        mv "/boot/vmlinux-kbuild-${KVER}" "/boot/vmlinuz-${KVER}"
      fi
      ;;
  esac
  cki_print_success "Architecture-specific workarounds applied successfully"

  cki_print_info "Finishing boot loader configuration for the new kernel"
  if [ ! -x /sbin/new-kernel-pkg ]; then
    if kernel-install add "${KVER}" "/boot/vmlinuz-${KVER}" 2>&1; then
      cki_print_success "Kernel installed"
    else
      ls -allh /boot
      cki_abort_recipe "kernel-install failed" FAIL
    fi
    if grubby --set-default "/boot/vmlinuz-${KVER}" 2>&1; then
      cki_print_success "updated default kernel"
    else
      ls -allh /boot
      cki_abort_recipe "fail to update default kernel" FAIL
    fi
  else
    if new-kernel-pkg -v --mkinitrd --dracut --depmod --make-default --host-only --install "${KVER}" 2>&1; then
      cki_print_success "new kernel installed correctly"
    else
      cki_abort_recipe "fail to install new kernel" FAIL
    fi
  fi
  cki_print_success "Boot loader configuration complete"

  # Workaround for kernel-install problem when it's not sourcing os-release
  # file, no official bug number yet.
  if [[ "${ARCH}" == s390x ]] ; then
      # Yay matching with wildcard, as we only want to execute this part of the
      # code on BLS systems and when this file exists, to prevent weird failures.
      for f in /boot/loader/entries/*"${KVER}".conf ; do
        title=$(grep title "${f}" | sed "s/[[:space:]]*$//")
        sed -i "s/title.*/$title/" "${f}"
        cki_print_success "Removed trailing whitespace in title record of $f"
      done
  fi

  # "quiet" makes us miss important kernel logs which makes debugging harder, remove it if present
  if grep -wq quiet /boot/loader/entries/*-"${KVER}".conf; then
    sed -i s/quiet// /boot/loader/entries/*-"${KVER}".conf
    cki_print_success "removed 'quiet' from kernel arguments"
  fi
}

function select_yum_tool()
{
  if [ -x /usr/bin/dnf ]; then
    YUM=/usr/bin/dnf
    ALL="--all"
    COPR_PLUGIN_PACKAGE=dnf-plugins-core
    if [[ -e /run/ostree-booted ]]; then
      RPM_OSTREE=/usr/bin/rpm-ostree
    fi
  elif [ -x /usr/bin/yum ]; then
    YUM=/usr/bin/yum
    ALL="all"
    COPR_PLUGIN_PACKAGE=yum-plugin-copr
  else
    cki_abort_recipe "No tool to download kernel from a repo" WARN
  fi

  cki_print_info "Installing package manager prerequisites"
  ${YUM} install -y ${COPR_PLUGIN_PACKAGE} > /dev/null
  cki_print_success "Package manager prerequisites installed successfully"
}

function rpm_prepare()
{
  # Detect if we have yum or dnf and install packages for managing COPR repos.
  select_yum_tool

  _cki_excluded_pkgs=()
  for pkg in "${SUPPORTED_KERNEL_PKGS[@]}"; do
     if [[ "${pkg}" != "${PACKAGE_NAME}" ]] && [[ "${pkg}" != "${PACKAGE_NAME}-core" ]]; then
         _cki_excluded_pkgs+=("${pkg}")
     fi
  done

  # setup yum repo based on url
  cat > /etc/yum.repos.d/kernel-cki.repo << EOF
[kernel-cki]
name=kernel-cki
baseurl=${KPKG_URL}
enabled=1
gpgcheck=0
exclude=${_cki_excluded_pkgs[*]}
EOF
  cki_print_success "Kernel repository file deployed"

  return 0
}

function copr_prepare()
{
  # set YUM var.
  select_yum_tool

  if ${YUM} copr enable -y "${KPKG_URL}"; then
    cki_print_success "Successfully enabled COPR repository: ${KPKG_URL}"
  else
    cki_abort_recipe "Could not enable COPR repository: ${KPKG_URL}" WARN
  fi
  return 0
}

function download_install_package()
{
  if ! cki_is_kernel_automotive; then
    # If download of a package fails, report warn/abort -> infrastructure issue
    if $YUM install --downloadonly -y "$1" > /dev/null || yumdownloader -y "$1" > /dev/null; then
      cki_print_success "Downloaded $1 successfully"
    else
      cki_abort_recipe "Failed to download ${1}!" WARN
    fi

  # If installation of a downloaded package fails, report fail/abort
  # -> distro issue
    if $YUM install -y "$1" > /dev/null; then
      cki_print_success "Installed $1 successfully"
    else
      cki_abort_recipe "Failed to install $1!" FAIL
    fi
  else
    # download
    if $YUM download --resolve "$1" > /dev/null; then
    cki_print_success "Downloaded $1 successfully"
    else
      cki_abort_recipe "Failed to download ${1}!" WARN
    fi

    # install
    cki_print_info "$1 will be installed using rpm-ostree override"
    if ! cki_is_true "${KPKG_VAR_DEBUG_KERNEL}"; then
      if rpm-ostree override replace ./kernel*.rpm > /dev/null; then
        cki_print_success "Installed $1 successfully"
      else
        cki_abort_recipe "RPM-OSTREE failed to install $1!" FAIL
      fi
    else
      # debug kernel automotive
      if rpm-ostree override remove kernel-automotive kernel-automotive-core kernel-automotive-modules\
      --install "$(pwd)/kernel-automotive-debug-${KVER}.rpm"\
      --install "$(pwd)/kernel-automotive-debug-modules-${KVER}.rpm"\
      --install "$(pwd)/kernel-automotive-debug-core-${KVER}.rpm" > /dev/null; then
        cki_print_success "Installed $1 successfully"
      else
        cki_abort_recipe "RPM-OSTREE failed to install $1!" FAIL
      fi
    fi
  fi
}

function rpm_install()
{
  cki_print_info "rpm_install: Extracting kernel version from ${KPKG_URL}"
  get_kpkg_ver
  if [ -z "${KVER}" ]; then
    cki_abort_recipe "rpm_install: Failed to extract kernel version from the package" FAIL
  else
    cki_print_success "Kernel version is ${KVER}"
  fi

  # Ensure that the debug kernel is selected as the default kernel in
  # /boot/grub2/grubenv.
  if cki_is_true "${KPKG_VAR_DEBUG_KERNEL}"&& [[ -z $RPM_OSTREE ]]; then
    echo "Adjusting settings in /etc/sysconfig/kernel to set debug as default"
    echo "UPDATEDEFAULT=yes" > /etc/sysconfig/kernel
    echo "DEFAULTKERNEL=kernel-debug" >> /etc/sysconfig/kernel
    echo "DEFAULTDEBUG=yes" >> /etc/sysconfig/kernel
    cki_print_success "Updated /etc/sysconfig/kernel to set debug kernels as default"
  fi

  # download & install kernel, or report result
  download_install_package "${PACKAGE_NAME}-$KVER"

  if ! cki_is_kernel_automotive ;then
    if $YUM install -y "${PACKAGE_NAME}-devel-${KVER}" > /dev/null; then
      cki_print_success "Installed ${PACKAGE_NAME}-devel-${KVER} successfully"
    else
      cki_print_warning "No package ${PACKAGE_NAME}-devel-${KVER} found, skipping!"
      cki_print_warning "Note that some tests might require the package and can fail!"
    fi
    if $YUM install -y "${PACKAGE_NAME}-modules-extra-${KVER}" > /dev/null; then
      cki_print_success "Installed ${PACKAGE_NAME}-modules-extra-${KVER} successfully"
    else
      cki_print_warning "No package ${PACKAGE_NAME}-modules-extra-${KVER} found, skipping!"
      cki_print_warning "Note that some tests might require the package and can fail!"
    fi
    if $YUM install -y "${PACKAGE_NAME}-modules-internal-${KVER}" > /dev/null; then
      cki_print_success "Installed ${PACKAGE_NAME}-modules-internal-${KVER} successfully"
    else
      cki_print_warning "No package ${PACKAGE_NAME}-modules-internal-${KVER} found, skipping!"
      cki_print_warning "Note that some tests might require the package and can fail!"
    fi
    if $YUM install -y "${PACKAGE_NAME}-headers-${KVER}" > /dev/null; then
      cki_print_success "Installed ${PACKAGE_NAME}-headers-${KVER} successfully"
    else
      cki_print_warning "No package ${PACKAGE_NAME}-headers-${KVER} found, trying without exact ${KVER}"
      # shellcheck disable=SC2010
      ALT_HEADERS=$(ls "${PACKAGE_NAME}"-headers* | grep -v src.rpm | head -1)
      if $YUM install -y "${ALT_HEADERS}" > /dev/null; then
          cki_print_success "Installed ${ALT_HEADERS} successfully"
      else
          cki_print_warning "No package ${PACKAGE_NAME}-headers-${KVER} found, skipping!"
          cki_print_warning "Note that some tests might require the package and can fail!"
      fi
    fi

    if [[ ${PACKAGE_NAME} =~ "kernel-rt" ]]; then
      if $YUM install -y "/usr/sbin/kernel-is-rt" > /dev/null; then
        cki_print_success "Installed /usr/sbin/kernel-is-rt successfully"
      else
        cki_print_warning "No package for /usr/sbin/kernel-is-rt found, skipping!"
      fi
    fi

    # The package was renamed (and temporarily aliased) in Fedora/RHEL"
    if $YUM search kernel-firmware | grep "^kernel-firmware\.noarch" ; then
      FIRMWARE_PKG=kernel-firmware
    else
      FIRMWARE_PKG=linux-firmware
    fi
    cki_print_info "Installing kernel firmware package"
    $YUM install -y $FIRMWARE_PKG > /dev/null
    cki_print_success "Kernel firmware package installed"

    KVER_UNAME="${KVER}"
    if [[ ${PACKAGE_NAME} =~ "kernel-64k" ]]; then
      # kernel-64k variant doesn't update the default kernel in grubby
      # make sure the correct version is set

      # on kernel-64k the kernel version from rpm is a bit different from the uname
      KVER_UNAME="${KVER}+64k"
      if grubby --set-default /boot/vmlinuz-"${KVER_UNAME}"; then
        cki_print_success "Grubby set default kernel to /boot/vmlinuz-${KVER_UNAME}"
      else
        cki_abort_recipe "Fail to set default kernel to /boot/vmlinuz-${KVER_UNAME}" FAIL
      fi
    fi

    # Workaround for BZ 1698363 - was fixed in 8.3 but not backported to 8.1 nor 8.2
    if [[ "${ARCH}" == s390x ]] ; then
      grubby --set-default /boot/vmlinuz-"${KVER_UNAME}" && zipl
      cki_print_success "Grubby workaround for s390x completed"
    fi
  fi
  return 0
}

function ostree_extra_package_install()
{
  PKG_CMD="${RPM_OSTREE} -A install --allow-inactive --idempotent -y "
  if $PKG_CMD "${PACKAGE_NAME}-devel-${KVER}" > /dev/null; then
    cki_print_success "Installed ${PACKAGE_NAME}-devel-${KVER} successfully"
  else
    cki_print_warning "No package ${PACKAGE_NAME}-devel-${KVER} found, skipping!"
    cki_print_warning "Note that some tests might require the package and can fail!"
  fi
  if $PKG_CMD "${PACKAGE_NAME}-modules-extra-${KVER}" > /dev/null; then
    cki_print_success "Installed ${PACKAGE_NAME}-modules-extra-${KVER} successfully"
  else
    cki_print_warning "No package ${PACKAGE_NAME}-modules-extra-${KVER} found, skipping!"
    cki_print_warning "Note that some tests might require the package and can fail!"
  fi
  if $PKG_CMD "${PACKAGE_NAME}-modules-internal-${KVER}" > /dev/null; then
    cki_print_success "Installed ${PACKAGE_NAME}-modules-internal-${KVER} successfully"
  else
    cki_print_warning "No package ${PACKAGE_NAME}-modules-internal-${KVER} found, skipping!"
    cki_print_warning "Note that some tests might require the package and can fail!"
  fi
  if $PKG_CMD "${PACKAGE_NAME}-headers-${KVER}" > /dev/null; then
    cki_print_success "Installed ${PACKAGE_NAME}-headers-${KVER} successfully"
  else
    cki_print_warning "No package ${PACKAGE_NAME}-headers-${KVER} found, trying without exact ${KVER}"
    # shellcheck disable=SC2010
    ALT_HEADERS=$(ls "${PACKAGE_NAME}"-headers* | grep -v src.rpm | head -1)
    if $YUM install -y "${ALT_HEADERS}" > /dev/null; then
        cki_print_success "Installed ${ALT_HEADERS} successfully"
    else
        cki_print_warning "No package ${PACKAGE_NAME}-headers-${KVER} found, skipping!"
        cki_print_warning "Note that some tests might require the package and can fail!"
    fi
  fi
  # The package was renamed (and temporarily aliased) in Fedora/RHEL"
  if $YUM search kernel-firmware | grep "^kernel-firmware\.noarch" ; then
    FIRMWARE_PKG=kernel-firmware
  else
    FIRMWARE_PKG=linux-firmware
  fi
  cki_print_info "Installing kernel firmware package"
  $RPM_OSTREE install -A -y $FIRMWARE_PKG > /dev/null
  cki_print_success "Kernel firmware package installed"

  return 0
}

function io_test() {
  cki_run "uname -r"
  sync
  start_time=$(date +%s)
  for _ in $(seq 5); do
      cki_run "dd if=/dev/zero of=/opt/test.img oflag=dsync bs=1M count=500"
  done
  sync
  end_time=$(date +%s)
  total_time=$(( end_time - start_time ))
  rm -f /opt/test.img
  echo "io_test took ${total_time} seconds on kernel $(uname -r)"
  return $total_time
}

function main() {
    cki_print_info "REBOOTCOUNT is ${REBOOTCOUNT}"
    if [ "${REBOOTCOUNT}" -eq 0 ]; then
      local deps
      read -ra deps <<< "$TEST_DEPS"
      # set YUM var.
      select_yum_tool
      if [[ -z $RPM_OSTREE ]];then
          if $YUM install -y "${deps[@]}"; then
              cki_print_success "Installed test dependencies"
          else
              cki_abort_recipe "Failed to install test dependencies" WARN
          fi
      else
          if rpm-ostree install -A --idempotent --allow-inactive "${deps[@]}"; then
              cki_print_success "Installed test dependencies"
          else
              cki_abort_recipe "Failed to install test dependencies" WARN
          fi
      fi

      # kernel packages only from CKI kernel repo should be used
      # rpm_prepare creates kernel-cki.repo
      _exclude_pkgs="${SUPPORTED_KERNEL_PKGS[*]}"
      # shellcheck disable=SC2010
      _repofiles=$(ls /etc/yum.repos.d/ | grep -v kernel-cki.repo)

      # If we haven't rebooted yet, then we shouldn't have the directory present on the system.
      rm -rfv /var/tmp/kpkginstall
      # Make a directory to hold small bits of information for the test.
      mkdir -p /var/tmp/kpkginstall

      # If the KPKG_URL contains a pound sign, then we have variables on the end
      # which need to be removed and parsed.
      if [[ $KPKG_URL =~ \# ]]; then
          parse_kpkg_url_variables
      fi

      # If we are installing a debug kernel, make a reminder for us to check for
      # a debug kernel after the reboot
      if cki_is_true "${KPKG_VAR_DEBUG_KERNEL}"; then
        echo "true" > /var/tmp/kpkginstall/KPKG_VAR_DEBUG_KERNEL
      fi

      if [ -z "${KPKG_URL}" ]; then
        cki_abort_recipe "No KPKG_URL specified" FAIL
      fi

      # Make sure exclude kernel files from removed from config file
      # this can happen when rerunning the test
      cki_print_info "remove kernel exclude from repos"
      for _repo in ${_repofiles}; do
        sed -i "/^exclude=${_exclude_pkgs}/d" "/etc/yum.repos.d/${_repo}"
      done

      error=0
      if [[ "${KPKG_URL}" =~ .*\.tar\.gz ]] ; then
          targz_install || error=1
      elif [[ "${KPKG_URL}" =~ ^[^/]+/[^/]+$ ]] ; then
          set_package_name || error=1
          copr_prepare || error=1
          rpm_install || error=1
      else
          set_package_name || error=1
          rpm_prepare || error=1
          rpm_install || error=1
      fi

      if [ "$error" -ne 0 ]; then
        cki_abort_recipe "Failed installing kernel ${KVER}" WARN
      fi

      # Make sure tests are not able to install other kernels
      cki_print_info "adding kernel exclude from repos"
      for _repo in ${_repofiles}; do
        sed -i "/^enabled=1/a exclude=${_exclude_pkgs}" "/etc/yum.repos.d/${_repo}"
      done

      # collect IO perf data on original kernel
      io_test
      io_time=$?
      echo $io_time > io_perf_base_kernel.log
      rstrnt-report-log -l io_perf_base_kernel.log

      # force panic on oops
      # oops can cause system to crash, but restraint fails to detect it
      # causing in some cases the task to abort by external watchdog
      # and pipeline to handle this as infra failure.
      # Hopefully, forcing the panic will help to handle this as test failure.
      # https://gitlab.com/cki-project/upt/-/issues/49
      echo "kernel.panic_on_oops = 1" >> /etc/sysctl.conf
      cki_print_success "Set panic_on_oops to 1"

      cki_print_success "Installed kernel ${KVER}, rebooting (this may take a while)"
      cat << EOF
*******************************************************************************
*******************************************************************************
** A reboot is required to boot the new kernel that was just installed.      **
** This can take a while on some systems, especially those with slow BIOS    **
** POST routines, like HP servers.                                           **
**                                                                           **
** Please be patient...                                                      **
*******************************************************************************
*******************************************************************************
EOF
      rstrnt-report-result ${TEST}/kernel-in-place PASS 0
      rstrnt-reboot
      # Make sure the script doesn't continue if rstrnt-reboot get's killed
      # https://github.com/beaker-project/restraint/issues/219
      return 0
    else
      # set YUM var.
      select_yum_tool

      if [[ ! "${KPKG_URL}" =~ .*\.tar\.gz ]] ; then
        set_package_name
      fi
      cki_print_info "after reboot: Extracting kernel version from ${KPKG_URL}"
      get_kpkg_ver
      if [ -z "${KVER}" ]; then
        cki_abort_recipe  "Failed to extract kernel version from the package after reboot" FAIL
      fi

      # Make a list of kernel versions we expect to see after reboot.
      # the debug suffix on kernel names do not apply for kernel builds from tarball
      if [ -f /var/tmp/kpkginstall/KPKG_VAR_DEBUG_KERNEL ] && [[ ! "${KPKG_URL}" =~ .*\.tar\.gz ]]; then
        valid_kernel_versions=(
          "${KVER}.debug"           # RHEL 7 style debug kernels
          "${KVER}+debug"           # RHEL 8 style debug kernels
        )
      else
        KVER=${KVER//.$(uname -i)/}
        valid_kernel_versions=(
          "${KVER}"
          "${KVER}.${ARCH}"
          "${KVER}.${ARCH}+64k"
        )
      fi
      ckver=$(uname -r)
      cki_print_info "Acceptable kernel version strings: ${valid_kernel_versions[*]} "
      cki_print_info "Running kernel version string:     ${ckver}"

      # Did we get the right kernel running after reboot?
      if [[ ! " ${valid_kernel_versions[*]} " == *" ${ckver} "* ]]; then
        cki_abort_recipe "Kernel version after reboot (${ckver}) does not match expected version strings!" FAIL
      fi

      cki_print_success "Found the correct kernel version running!"

      # rpm-ostree extra packages install has to be after reboot
      if [[ -n $RPM_OSTREE ]]; then
        cki_print_info "Install kernel extra packages - rpm-ostree after reboot"
        ostree_extra_package_install
      fi

      # save the CKI installed kernel so following tests can check if they are running on correct kernel
      # this should help detect cases where by mistake the kernel gets updated.
      # https://gitlab.com/redhat/centos-stream/tests/kernel/kpet-db/-/issues/56
      mkdir -p /var/opt/cki/
      echo "${ckver}" > /var/opt/cki/kernel_version

      # Workaround for cross compiling non x86_64 kernels
      if [[ ! -f /usr/src/kernels/$ckver/scripts/basic/fixdep ]]; then
        cki_print_info "Workaround for cross compiling non x86_64 kernels"
        if [[ -n $RPM_OSTREE ]]; then
            cki_print_info "skipping workaround for cross compiling non x86_64 kernels as it is running on rpm-ostree environment"
        else
          PREFIX="/usr/src/kernels/$ckver"

          # detect the right compiler to use
          if grep -qFx CONFIG_CC_IS_GCC=y "$PREFIX/.config"; then
            KCC=gcc
          elif grep -qFx CONFIG_CC_IS_CLANG=y "$PREFIX/.config"; then
            KCC=clang
          else
            cki_abort_recipe "Kernel built with an unknown compiler" WARN
          fi

          # detect the right linker to use
          if grep -qFx CONFIG_LD_IS_BFD=y "$PREFIX/.config"; then
            KLD=ld.bfd
          elif grep -qFx CONFIG_LD_IS_LLD=y "$PREFIX/.config"; then
            KLD=ld.lld
          else
            cki_abort_recipe "Kernel built with an unknown linker" WARN
          fi

          # Backup and restore the .config files otherwise regenerated .config
          # files will be incompatible with the running kernel
          # Backup the files individually otherwise missing files will abort rstrnt-backup
          FILES="$PREFIX/.config
            $PREFIX/include/config/auto.conf
            $PREFIX/include/config/auto.conf.cmd
            $PREFIX/include/config/cc/can/link/static.h
            $PREFIX/include/generated/autoconf.h"
          for file in $FILES; do
            rstrnt-backup "$file"
          done

          error=0
          # Temporarily unset ARCH var defined in libcki to avoid Makefile conflicts
          # otherwise you will see an error about a non-existing arch dir
          env -u ARCH make -C "$PREFIX" CC="$KCC" LD="$KLD" olddefconfig || error=1
          if [ $error -eq 0 ]; then
              env -u ARCH make -C "$PREFIX" CC="$KCC" LD="$KLD" modules_prepare || error=1
          fi
          if [ $error -eq 0 ]; then
            env -u ARCH make -C "$PREFIX" CC="$KCC" LD="$KLD" scripts || error=1
          fi

          rstrnt-restore
          if [ $error -ne 0 ]; then
              # Make sure the file is removed, in case of rerun it doens't skip this step
              rm -f "/usr/src/kernels/$ckver/scripts/basic/fixdep"
              cki_abort_recipe "Failed applying cross compiling workaround" WARN
          fi
        fi
      fi

      # Save configuration used to build the kernel
      cat "/boot/config-${ckver}" > "kernel_${ckver}_config.log"
      rstrnt-report-log -l "kernel_${ckver}_config.log"

      sysctl kernel.panic_on_oops

      # collect IO perf data on CKI kernel
      io_test
      io_time=$?
      echo $io_time > io_perf_cki_kernel.log
      rstrnt-report-log -l io_perf_cki_kernel.log

      # We have the right kernel. Do we have any call traces?
      reboot_status="PASS"
      dmesg | grep -qi 'Call Trace:'
      dmesgret=$?
      if [[ ${dmesgret} -eq 0 ]]; then
        reboot_status="FAIL"
        DMESGLOG=/tmp/dmesg.log
        dmesg > ${DMESGLOG}
        rstrnt-report-log -l ${DMESGLOG}
        cki_print_warning "Call trace found in dmesg, see dmesg.log"
        rstrnt-report-result ${TEST}/dmesg-check WARN 7
      else
        rstrnt-report-result ${TEST}/dmesg-check PASS 0
      fi
      if which journalctl > /dev/null 2>&1; then
        journalctl -b | grep -qi 'Call Trace:'
        journalctlret=$?
        if [[ ${journalctlret} -eq 0 ]]; then
          reboot_status="FAIL"
          JOURNALCTLLOG=/tmp/journalctl.log
          journalctl -b > ${JOURNALCTLLOG}
          rstrnt-report-log -l ${JOURNALCTLLOG}
          cki_print_warning "Call trace found in journalctl, see journalctl.log"
          rstrnt-report-result ${TEST}journalctl-check WARN 7
        else
          rstrnt-report-result ${TEST}/journalctl-check PASS 0
        fi
      fi
      rstrnt-report-result ${TEST}/reboot ${reboot_status}

      # Clean up temporary files
      rm -rfv /var/tmp/kpkginstall
    fi
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
    main
fi
