#! /bin/bash
source /etc/profile
source /root/.bash_profile
echo "start scp-beaker-tasks.sh script"
export vm_name=$1
#/usr/local/bin/vmsh run_cmd $vm_name "rm -f /etc/yum.repos.d/*"
#cat /etc/yum.repos.d/beaker-AppStream.repo | awk '{system("/usr/local/bin/vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-AppStream.repo\"")}' &> /tmp/log.txt
#cat /etc/yum.repos.d/beaker-BaseOS.repo | awk '{system("/usr/local/bin/vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-BaseOS.repo\"")}' &> /tmp/log.txt
#cat /etc/yum.repos.d/beaker-harness.repo | awk '{system("/usr/local/bin/vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-harness.repo\"")}' &> /tmp/log.txt
#cat /etc/yum.repos.d/beaker-NFV.repo | awk '{system("/usr/local/bin/vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-NFV.repo\"")}' &> /tmp/log.txt
#cat /etc/yum.repos.d/beaker-RT.repo | awk '{system("/usr/local/bin/vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-RT.repo\"")}' &> /tmp/log.txt
#cat /etc/yum.repos.d/beaker-tasks.repo | awk '{system("/usr/local/bin/vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-tasks.repo\"")}' &> /tmp/log.txt
#cat /etc/yum.repos.d/beaker-harness.repo | awk '{system("/usr/local/bin/vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-harness.repo\"")}' &> /tmp/log.txt
#/usr/local/bin/vmsh run_cmd $vm_name "cat <<-EOF > /etc/yum.repos.d/beaker-tasks.repo
#[beaker-tasks]
#name=beaker-tasks
#enabled=1
#gpgcheck=0
#skip_if_unavailable=1
#EOF"
#/usr/local/bin/vmsh run_cmd $vm_name "yum clean all"
#/usr/local/bin/vmsh run_cmd $vm_name "yum makecache"
unset vm_name
echo "finished scp_repo.sh script"
