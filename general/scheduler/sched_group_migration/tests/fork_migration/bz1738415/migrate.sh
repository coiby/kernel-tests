pid=${*:-0}

. ../../../../include/runtest.sh

while true; do
	cgroup_classify /test/test1		cpu $pid
	cgroup_classify /TEST/test1/test2 cpu $pid
	cgroup_classify /test/test1       cpu $pid
	cgroup_classify /                 cpu $pid
	cgroup_classify /TEST             cpu $pid
done
