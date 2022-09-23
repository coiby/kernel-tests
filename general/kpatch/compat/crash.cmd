mod | grep kpatch | awk '{print }' > ~/kpatch_mods
mod -s kpatch_3_10_0_663_0_1_test
mod -s kpatch
sym cmdline_proc_show
dis -sl ffffffffc0827410 > /root/source
exit
