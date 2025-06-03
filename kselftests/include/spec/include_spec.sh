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

Describe 'kselftests/include/net do_net_forwarding_config'
    It "can call do_net_forwarding_config"
        function set_network_env(){
            echo "set_network_env"
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
        The line 4 should equal "rpm -q --quiet netsniff-ng"
        The line 5 should equal "rpm -q --quiet smcroute"
        The line 6 should equal "rpm -q --quiet mcast-tools"
        The line 7 should equal "pushd"
        The line 8 should equal "sed -i 0, /ets_test_strict/ {/ets_test_strict/d;} sch_ets.sh"
        The line 9 should equal "sed -i 0, /ets_test_mixed/ {/ets_test_mixed/d;} sch_ets.sh"
        The line 10 should equal "sed -i 0, /ets_test_dwrr/ {/ets_test_dwrr/d;} sch_ets.sh"
        The line 11 should equal "sed -i /classifier_mode/d sch_ets.sh"
        The line 12 should equal "sysctl_set net.ipv4.ping_group_range 1 0"
        The line 13 should equal "sysctl_set net.bridge.bridge-nf-call-iptables 0"
        The line 14 should equal "sysctl_set net.bridge.bridge-nf-call-ip6tables 0"
        The line 15 should equal "cp forwarding.config.sample forwarding.config"
        The line 16 should equal "popd"
        The status should be success
    End
End

Describe 'kselftests/include/net do_netfilter_config'
    It "can call do_net_forwarding_config"
        function set_network_env(){
            echo "set_network_env"
        }
        function which(){
            echo "which $*"
            return 1
        }

        When call do_netfilter_config
        The line 1 should equal "set_network_env"
        The line 2 should equal "which conntrack"
        The line 3 should equal "dnf -y install conntrack-tools"
        The status should be success
    End
End

Describe 'kselftests/include/net do_tc-testing_config'
    It "can call do_net_forwarding_config"
        function set_network_env(){
            echo "set_network_env"
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
        The line 2 should equal "rpm -q --quiet python3-scapy"
        The line 3 should equal "modprobe -r veth"
        The line 4 should equal "pushd"
        The line 5 should equal "sed -i /TIMEOUT/s/24/180/ tdc_config.py"
        The line 6 should equal "popd"
        The status should be success
    End
End
