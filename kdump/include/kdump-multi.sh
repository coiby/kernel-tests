#!/bin/bash

# ---------------- Advanced Configurations for Remote Kdump   ------------------------ #

SSH_SERVER=${SSH_SERVER:-""}
SSH_USER=${SSH_USER:-"root"}

NFS_SERVER=${NFS_SERVER:-""}
EXPORT=${EXPORT:-"/mnt/testarea/nfs"}

IP_TYPE=${IP_TYPE:-"hostname"}

MNT_PATH=${MNT_PATH:-"$EXPORT"}
SUBMITTER=${SUBMITTER%@*}
DUMP_PATH=${DUMP_PATH:-""} # User may provide a base dump path. By default, it's '/'
DUMP_PATH=$(mktemp -d -u -p "${DUMP_PATH}/${SUBMITTER:-noowner}/${JOBID:-nojobid}/${HOSTNAME:-nohostname}")

NFS_MOUNT_DRACUT_ARGS=${NFS_MOUNT_DRACUT_ARGS:-"false"}

FSTAB_ENTRY=${FSTAB_ENTRY:-"false"}
FSTAB_ENTRY_OPTS=${FSTAB_ENTRY_OPTS:-"defaults,noauto"}

TARGET_MOUNTED=${TARGET_MOUNTED:-"true"}
TARGET_MOUNTED_OPTS="${TARGET_MOUNTED_OPTS:-"defaults"}"

# VMCORE Servers

# Set Remote SSH/NFS server configurations (single/multi-hosts mode)
# - AUTO_CONFIG is for RH internal use only and it works only if beaker
#   test is in single host mode. If value = true, it will point to a
#   pre-setup RH NFS/SSH server
# - If SSH/NFS server is set explicitly, AUTO_CONFIG won't be working.
SetRemoteServer(){
    Log "Set remote vmcore server"
    local server_type=${1^^} # either SSH or NFS

    if [[ ! ${server_type} =~ ^(NFS|SSH)$ ]]; then
        Error "Invalid server_type passed in: ${server_type}. Only SSH/NFS is allowed."
        return 1
    fi
    server_type+=_SERVER
    [[ -n "${!server_type}" ]] && AUTO_CONFIG="" # If SSH/NFS server is set. Skip AUTO_CONFIG

    # Multi-hosts mode
    if echo "${SERVERS}" | grep -qi "${HOSTNAME}"  ||  echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
        Log "Mulit-host mode. Setting the multi-host SERVER as server."
        eval "${server_type}=${SERVERS}"

    # Single-host -  AUTO_CONFIG is set
    else
        Log "Single-host ${server_type} mode."
        if [ -n "${AUTO_CONFIG}" ]; then
            # Call internal function to get internal vmcore servers
            if [ "$(type -t _getVmcoreServer)" = "function" ]; then
                _getVmcoreServer "${AUTO_CONFIG}" "${server_type}"
            else
                Error "AUTO_CONFIG is not supported."
                return 1
            fi

            if [ "${server_type}" = SSH_SERVER ]; then
                DUMP_PATH=$(mktemp -d -u -p "${DUMP_PATH}/${SUBMITTER:-noowner}/${JOBID:-nojobid}/${HOSTNAME:-nohostname}")
            elif [ "${server_type}" = NFS_SERVER ]; then
                DUMP_PATH=$(mktemp -d -u -p "/${SUBMITTER:-noowner}/${JOBID:-nojobid}/${HOSTNAME:-nohostname}")
            fi
        fi
    fi

    [ -z "${!server_type}" ] && return 1 || return 0
}

# SetupSSHKeys: Copy prepared SSH keys for kdump dump
SetupSSHKeys()
{
    mkdir -p /root/.ssh
    Log "Setting Kdump SSH keys (${K_ID_RSA})"
    cp -f "../include/id_rsa.pri" "${K_ID_RSA}"
    cp -f "../include/id_rsa.pub" "${K_ID_RSA}.pub"
    chmod 0600 "${K_ID_RSA}"
    chmod 0600 "${K_ID_RSA}.pub"

    # Need to setup restricted shell for client's ssh Connection
    if [ -n "${RESTRICTED_SHELL}" ]; then
        Log "[RESTRICTED_SHELL] Only allow restricted shell for client"
        sed -i 's/^/command="\/bin\/bash -r" /' "${K_ID_RSA}.pub"
    fi

    # On Server only
    if echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
        mkdir -p /${SSH_USER}/.ssh
        Log "Updating authorized_keys"
        touch "/${SSH_USER}/.ssh/authorized_keys"
        LogRun "cat \"${K_ID_RSA}.pub\" >> \"/${SSH_USER}/.ssh/authorized_keys\""
        LogRun "restorecon -R /root/.ssh/authorized_keys"
    fi
}

# TestSSHConnection: Test SSH connection from client to Server
# Parameters:
#   - remote_server: The remote server to which test the SSH connection
TestSSHConnection()
{
    local remote_server="${1}"

    # Test SSH connection from client to server
    Log "Test SSH connection"
    LogRun "ssh -o StrictHostKeyChecking=no -i ${K_ID_RSA} ${SSH_USER}@${remote_server} \
        \"touch ~/ssh-check-pass\"" || FatalError "Test SSH connection FAIL!"

    # Getting the server IP address if ip_type = v4 or v6
    if [[ "${IP_TYPE}" =~ ^(v4|v6)$ ]]; then
        Log "Get dump target ip${IP_TYPE} address"

        local ssh_cmd="ip ad show | grep 'inet ' | grep global | head -n 1"
        if [ "${IP_TYPE}" = v6 ]; then
            ssh_cmd="ip ad show | grep 'inet6' | grep global | head -n 1"
        fi

        LogRun "ssh -o StrictHostKeyChecking=no -i ${K_ID_RSA} ${SSH_USER}@${remote_server} \"${ssh_cmd}\" > \"./Server-ip${IP_TYPE}-address.out\""
        if [ ! -s "./Server-ip${IP_TYPE}-address.out" ]; then
            FatalError "Failed to get dump target ip${IP_TYPE} address"
        fi
    fi
}

# SetupSSHServer: Setup SSH service
SetupSSHServer()
{
    Log "---------------------"
    Log "Setting up SSH server"
    Log "---------------------"

    SetupSSHKeys

    if $IS_RHEL5 || $IS_RHEL6 ; then
        LogRun "service sshd restart 2>&1"
    else
        LogRun "systemctl restart sshd.service 2>&1"
    fi

    [ "${PIPESTATUS[0]}" -ne 0 ] && FatalError "Unable to start SSH service."
}

# SetupNFSServer: Set up NFS service
SetupNFSServer()
{
    Log "---------------------"
    Log "Setting up NFS server"
    Log "---------------------"

    # In case for NFS ipv4/ipv6 tests which requires retrieving server IP address
    # via SSH
    SetupSSHKeys

    Log "Setup NFS service"
    mkdir -p "${EXPORT}"
    echo "${EXPORT} *(rw,no_root_squash,sync,insecure)" > "/etc/exports"
    LogRun "cat /etc/exports"

    if $IS_RHEL5 || $IS_RHEL6 ; then
        LogRun "service nfs restart 2>&1"
    else
        LogRun "systemctl restart nfs-server.service 2>&1"
    fi

    [ "${PIPESTATUS[0]}" -ne 0 ] && {
        if ! ( $IS_RHEL5 || $IS_RHEL6 ); then
            LogRun "journalctl --no-pager --all | tail -n 20"
        fi
        FatalError "Unable to start NFS service."
    }

    LogRun "iptables -F"

    # Since kexec-2.0.7, Dump path must be created
    # on server site when triggerring nfs dump
    Log "Create dump path on NFS server"
    LogRun "mkdir -p \"${EXPORT}/${DUMP_PATH}\""
}

# SetupSSHClient: Setup SSH Client
SetupSSHClient()
{
    Log "---------------------"
    Log "Setting up SSH client"
    Log "---------------------"
    Log "-------------------------------------------------"
    Log "The SSH Server: ${SSH_SERVER}"
    Log "The SSH User: ${SSH_USER}"
    Log "-------------------------------------------------"

    # Test SSH connection
    SetupSSHKeys
    TestSSHConnection "${SSH_SERVER}"

    local remote_server=${SSH_SERVER}
    if [[ "${IP_TYPE}" =~ ^(v4|v6)$ ]]; then
        remote_server=$(cat ./Server-ip${IP_TYPE}-address.out | awk '{print $2}' | awk -F/ '{print $1}')
    fi

    if [ -z "${remote_server}" ]; then
        Error "Failed to get server address (${IP_TYPE})"
        return
    fi

    # Without link delay, it might not get a IP from DHCP.
    if $IS_RHEL5 ; then AppendConfig "net ${SSH_USER}@${remote_server}" "link_delay 60"
    elif $IS_RHEL6 ; then AppendConfig "ssh ${SSH_USER}@${remote_server}" "link_delay 60"
    else AppendConfig "ssh ${SSH_USER}@${remote_server}"
    fi

    AppendConfig "path ${DUMP_PATH}"
    echo "${DUMP_PATH}" > "${K_PATH}"

    # RHEL-8.3.0 bz1819575/bz1824327
    # '-F' must be spefieiced with makedumpfile in SSH dump. Otherwise it will fail
    # makedumpfile --check-params check.
    AppendConfig "core_collector makedumpfile -F -l -d 31"

    # RHBZ 716439 uses "kdump_id_rsa" as private key file
    if [ -f "${K_ID_RSA}" ]; then
        echo "IdentityFile ${K_ID_RSA}" >> "${K_SSH_CONFIG}"
    fi

    # Skip HostKeyChecking for IPv6 entry
    # Otherwise it may fail to restart kdump
    # Because set_ssh_without_passwd may only insert an entry with hostname (IPv4 addr) in ~/.ssh/known_hosts
    [[ -f "${K_SSH_CONFIG}" ]] && sed -i "/^StrictHostKeyChecking/d" "${K_SSH_CONFIG}"
    echo "StrictHostKeyChecking no" >> "${K_SSH_CONFIG}"

    RestartKdump
}

# SetupNFSClient: Setup NFS Client

SetupNFSClient()
{
    Log "---------------------"
    Log "Setting up NFS client"
    Log "---------------------"
    Log "-------------------------------------------------"
    Log "The NFS Server: ${NFS_SERVER}"
    Log "The EXPORT: ${EXPORT}"
    Log "The Dump PATH: ${DUMP_PATH}"
    Log "-------------------------------------------------"

    local remote_server=${NFS_SERVER}
    if [[ "${IP_TYPE}" =~ ^(v4|v6)$ ]]; then
        SetupSSHKeys
        TestSSHConnection "${NFS_SERVER}"

        remote_server=$(cat ./Server-ip${IP_TYPE}-address.out | awk '{print $2}' | awk -F/ '{print $1}')
        [[ "${IP_TYPE}" == v6 ]] && remote_server="[${remote_server}]"
    fi

    if [ -z "${remote_server}" ] || [ "${remote_server}" = "[]" ]; then
        Error "Failed to get server address (${IP_TYPE})"
        return
    fi

    # Without link delay, it might not get a IP from DHCP.
    ( $IS_RHEL5 || $IS_RHEL6 ) && AppendConfig "link_delay 60"

    # Validate param 'NFSOPT'
    if   $IS_RHEL5; then [[ "${NFSOPT:=net}" = net ]]
    elif $IS_RHEL6; then [[ "${NFSOPT:=nfs}" =~ ^(net|nfs|nfs4)$ ]]
    else [[ "${NFSOPT:=nfs}" = nfs ]]
    fi
    [ $? -eq 0 ] || MajorError "The value of param 'NFSOPT' is invalid: ${NFSOPT}"

    # Configure NFS target and store NFS exports
    if [ "${NFS_MOUNT_DRACUT_ARGS}" != false ]; then
        AppendConfig "dracut_args --mount \"${remote_server}:${EXPORT} ${MNT_PATH} ${NFSOPT} defaults\""
    else
        AppendConfig "${NFSOPT} ${remote_server}:${EXPORT}"
    fi
    echo "${EXPORT}" >"${K_NFS}"

    # By default, DUMP_PATH is a path unique to current job, hostname and test steps.
    AppendConfig "path ${DUMP_PATH}"
    echo "${DUMP_PATH}" > "${K_PATH}"

    # Mount and create dump path on Server
    # Since kexec-2.0.7, dump path ${export}/${path} must be created
    # on server when starting the kdump service.
    if ! "${NFS_MOUNT_DRACUT_ARGS}"; then
        Log "create dump path"
        mkdir -p "${MNT_PATH}"
        Log "Mount and create dump path on server"
        LogRun "mount -o \"${TARGET_MOUNTED_OPTS}\" \"${remote_server}:${EXPORT}\" \"${MNT_PATH}\"" || {
            Error "Failed to mount ${remote_server}:${EXPORT} to ${MNT_PATH}."
            return
        }

        mkdir -p "${MNT_PATH}/${DUMP_PATH}"
        Log "Dump path created"
        LogRun "ls -la \"${MNT_PATH}/${DUMP_PATH}\""
    fi

    # Bug 1814121 - RFE: improve kdump service to relax file system pre-mount requirements
    # Kdump allows nfs target to be not mounted at the time of kdumpctl start if
    # - fstab has no corresponding nfs entry configured
    # - fstab has an corresponding nfs entry configured with opt 'noatuo'
    if ! "${TARGET_MOUNTED}"; then
        Log "[TARGET_MOUNTED=${TARGET_MOUNTED}] Umount NFS target."
        LogRun "umount \"${MNT_PATH}\"" || {
            Error "Failed to unmount ${remote_server}:${EXPORT} from ${MNT_PATH}."
            return
        }
        mount
    fi

    if "${FSTAB_ENTRY}"; then
        Log "[FSTAB_ENTRY=${FSTAB_ENTRY}] Config NFS mount in fstab"
        local fstab_entry="${remote_server}:${EXPORT}    ${MNT_PATH}  nfs  ${FSTAB_ENTRY_OPTS}  1 2"
        Log "Updated fstab entry: $fstab_entry"
        sed -i /^${remote_server}/d ${FSTAB_FILE}
        echo "${fstab_entry}" >> ${FSTAB_FILE}
    fi
    RhtsSubmit "${FSTAB_FILE}"
    RestartKdump

    # Check if the target is mounted by kdump service if TARGET_MOUNTED is false
    if ! "${TARGET_MOUNTED}" && mount | grep -q "${NFS_SERVER}"; then
        Log "[TARGET_MOUNTED=${TARGET_MOUNTED}] Check if NFS target is not mounted as test required"
        LogRun "mount"
        Error "NFS ${NFS_SERVER} is mounted"
        return
    fi
    mount > mount.out
    RhtsSubmit "$(pwd)/mount.out"

    # Reliably pass around where the core dumps are accessible
    if [ -n "${WEBSERVERBASEURL}" ]; then
        local vmcore_link="${WEBSERVERBASEURL}/${DUMP_PATH}"
        echo "vmcore link: <a href=\"${vmcore_link}\">${vmcore_link}</a>" > /tmp/coredumpurl.html
        RhtsSubmit /tmp/coredumpurl.html
    fi
}



