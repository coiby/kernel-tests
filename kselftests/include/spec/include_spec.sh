#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Needed to be able to include net.sh
Mock rhel_major
    echo "${MAJOR_RELEASE}"
End
Include kselftests/include/net.sh


function which(){
    echo "which $1"
    exit_code=${WHICH_EXITCODES[0]}
    export WHICH_EXITCODES=${WHICH_EXITCODES[*]:1}
    return "$exit_code"
}

export pkg_mgr="dnf"
export pkg_mgr_inst_string="-y install"

Describe 'kselftests/include/net install_netsniff'
    function rpm(){
        echo "rpm $*"
        return "${RPM_EPEL:-1}"
    }

    # the function call which command twice
    export WHICH_EXITCODES=(1 0)
    It "can install_netsniff krelease 7"
        export krelease=7
        When call install_netsniff
        The line 1 should equal "which mausezahn"
        The line 2 should equal "dnf -y install jq netsniff-ng"
        The line 3 should equal "which mausezahn"
        The status should be success
    End

    It "can install_netsniff krelease 8 no epel"
        export krelease=8
        When call install_netsniff
        The line 1 should equal "which mausezahn"
        The line 2 should equal "rpm -q --quiet epel-release"
        The line 3 should equal "dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
        The line 4 should equal "dnf -y install jq netsniff-ng"
        The line 5 should equal "dnf -y remove epel-release"
        The line 6 should equal "which mausezahn"
     End

    It "can install_netsniff krelease 9 with epel"
        export RPM_EPEL=0
        export krelease=9
        When call install_netsniff
        The line 1 should equal "which mausezahn"
        The line 2 should equal "rpm -q --quiet epel-release"
        The line 3 should equal "dnf -y install --enablerepo=epel jq netsniff-ng"
        The line 4 should equal "which mausezahn"
     End
End

Describe 'kselftests/include/net install_smcroute'
    # the function call which command twice
    export WHICH_EXITCODES=(1 0)
    It "can install_smcroute"
        When call install_smcroute
        The line 1 should equal "which smcroute"
        The line 2 should equal "dnf copr -y enable liuhangbin/smcroute"
        The line 3 should equal "dnf -y install smcroute"
        The line 4 should equal "which smcroute"
        The status should be success
    End
End

Describe 'kselftests/include/net install_sendip'
    # the function call which command twice
    export WHICH_EXITCODES=(1 0)
    It "can call install_sendip"
        When call install_sendip
        The line 1 should equal "which sendip"
        The line 2 should equal "dnf -y copr enable cygn/SendIP"
        The line 3 should equal "dnf -y install sendip"
        The line 4 should equal "which sendip"
        The status should be success
    End
End

Describe 'kselftests/include/net install_scapy'
    # the function call scapy command twice
    export SCAPY_EXITCODES=(1 0)
    It "can call install_scapy"
        scapy(){
            echo "scapy $*"
            exit_code=${SCAPY_EXITCODES[0]}
            # shellcheck disable=SC2178
            export SCAPY_EXITCODES=${SCAPY_EXITCODES[*]:1}
            return "$exit_code"
        }

        export krelease=8
        When call install_scapy
        The line 1 should equal "scapy -h"
        The line 2 should equal "dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
        The line 3 should equal "dnf -y install scapy"
        The line 4 should equal "rpm -e epel-release"
        The line 5 should equal "scapy -h"
        The status should be success
    End
End

Describe 'kselftests/include/net do_net_forwarding_config'
    It "can call do_net_forwarding_config"
        function set_network_env(){
            echo "set_network_env"
        }
        function install_netsniff(){
            echo "install_netsniff"
        }
        function install_smcroute(){
            echo "install_smcroute"
        }
        function which(){
            echo "which $*"
            return 1
        }
        function sed(){
            echo "sed $*"
        }
        function pushd(){
            echo "pushd"
        }
        function popd(){
            echo "popd"
        }
        function sysctl_set(){
            echo "sysctl_set $*"
        }
        function lsmod(){
            echo "br_netfilter"
        }
        function cp(){
            echo "cp $*"
        }

        export krelease=9
        When call do_net_forwarding_config
        The line 1 should equal "set_network_env"
        The line 2 should equal "which tc"
        The line 3 should equal "dnf -y install iproute-tc"
        The line 4 should equal "install_netsniff"
        The line 5 should equal "install_smcroute"
        The line 6 should equal "pushd"
        The line 7 should equal "sed -i 0, /ets_test_strict/ {/ets_test_strict/d;} sch_ets.sh"
        The line 8 should equal "sed -i 0, /ets_test_mixed/ {/ets_test_mixed/d;} sch_ets.sh"
        The line 9 should equal "sed -i 0, /ets_test_dwrr/ {/ets_test_dwrr/d;} sch_ets.sh"
        The line 10 should equal "sed -i /classifier_mode/d sch_ets.sh"
        The line 11 should equal "sysctl_set net.ipv4.ping_group_range 1 0"
        The line 12 should equal "sysctl_set net.bridge.bridge-nf-call-iptables 0"
        The line 13 should equal "sysctl_set net.bridge.bridge-nf-call-ip6tables 0"
        The line 14 should equal "cp forwarding.config.sample forwarding.config"
        The line 15 should equal "popd"
        The status should be success
    End
End

Describe 'kselftests/include/net do_netfilter_config'
    It "can call do_net_forwarding_config"
        function set_network_env(){
            echo "set_network_env"
        }
        function install_sendip(){
            echo "install_sendip"
        }
        function which(){
            echo "which $*"
            return 1
        }

        When call do_netfilter_config
        The line 1 should equal "set_network_env"
        The line 2 should equal "which conntrack"
        The line 3 should equal "dnf -y install conntrack-tools"
        The line 4 should equal "install_sendip"
        The status should be success
    End
End

Describe 'kselftests/include/net do_tc-testing_config'
    It "can call do_net_forwarding_config"
        function set_network_env(){
            echo "set_network_env"
        }
        function install_scapy(){
            echo "install_scapy"
        }
        function modprobe(){
            echo "modprobe $*"
        }
        function pushd(){
            echo "pushd"
        }
        function popd(){
            echo "popd"
        }
        function sed(){
            echo "sed $*"
        }

        When call do_tc-testing_config
        The line 1 should equal "set_network_env"
        The line 2 should equal "dnf -y install clang valgrind"
        The line 3 should equal "install_scapy"
        The line 4 should equal "modprobe -r veth"
        The line 5 should equal "modprobe netdevsim"
        The line 6 should equal "pushd"
        The line 7 should equal "sed -i /TIMEOUT/s/24/180/ tdc_config.py"
        The line 8 should equal "sed -i s/python3 -sP\?/python3/ *.py plugin-lib/*.py"
        The line 9 should equal "popd"
        The status should be success
    End
End
