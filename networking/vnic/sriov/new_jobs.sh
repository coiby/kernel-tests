distro="RHEL-7.7-20190619.0"
#RPM_KERNEL="http://netqe-bj.usersys.redhat.com/share/liali/kernel-3.10.0-691.el7.x86_64.rpm"
image_name="rhel7.7.qcow2"
#image_name="RHEL-8.0-20181018.2.x86_64.qcow2"
#image_name="RHEL-ALT-7.4-20171026.0.qcow2"
#distro=${distro:-"RHEL-7.2-20150820.0"}
dryrun=${dryrun:-""}
if [ -n "$dryrun" ]; then
	dryrun="-n"
fi
other_options="$@"

declare -A test_pairs=(
	[machine0]="hp-dl380pg8-08.rhts.eng.pek2.redhat.com,hp-dl380pg8-15.rhts.eng.pek2.redhat.com" [systype0]="machine" [driver0]="bnx2x,cxgb4" [model0]="Broadcom-BCM57840_NetXtreme_II_10_Gb,Chelsio-T520-CR_Unified_Wire_Ethernet_Controller" [speed0]="10G,10G"
	[machine1]="hp-dl380pg8-08.rhts.eng.pek2.redhat.com,hp-dl380pg8-15.rhts.eng.pek2.redhat.com" [systype1]="machine" [driver1]="bnx2x,be2net" [model1]="Broadcom-BCM57840_NetXtreme_II_10_Gb,Emulex-OneConnect_NIC_-Skyhawk" [speed1]="10G,10G"
	[machine2]="hp-dl380pg8-08.rhts.eng.pek2.redhat.com,hp-dl380pg8-15.rhts.eng.pek2.redhat.com" [systype2]="machine" [driver2]="bnx2x,liquidio" [model2]="Broadcom-BCM57840_NetXtreme_II_10_Gb,Cavium,-CN23XX_Intelligent_Adapter" [speed2]="10G,10G"
	[machine3]="hp-dl380pg8-08.rhts.eng.pek2.redhat.com,hp-dl380pg8-15.rhts.eng.pek2.redhat.com" [systype3]="machine" [driver3]="bnx2x,mlx4_en" [model3]="Broadcom-BCM57840_NetXtreme_II_10_Gb,Mellanox-MT27500_Family" [speed3]="10G,10G"

	[machine4]="hp-dl380pg8-15.rhts.eng.pek2.redhat.com,hp-dl380pg8-08.rhts.eng.pek2.redhat.com" [systype4]="machine" [driver4]="mlx4_en,bnx2x" [model4]="Mellanox-MT27500_Family,Broadcom-BCM57840_NetXtreme_II_10_Gb" [speed4]="10G,10G"
	[machine5]="hp-dl380pg8-15.rhts.eng.pek2.redhat.com,hp-dl380pg8-08.rhts.eng.pek2.redhat.com" [systype5]="machine" [driver5]="mlx4_en,cxgb4" [model5]="Mellanox-MT27500_Family,Chelsio-T422-CR_Unified_Wire_Ethernet_Controller" [speed5]="10G,10G"
	[machine6]="hp-dl380pg8-15.rhts.eng.pek2.redhat.com,hp-dl380pg8-08.rhts.eng.pek2.redhat.com" [systype6]="machine" [driver6]="mlx4_en,sfc" [model6]="Mellanox-MT27500_Family,Solarflare-SFC9220_10-40G_Ethernet_Controller" [speed6]="10G,10G"

	[machine7]="hp-dl380g9-04.rhts.eng.pek2.redhat.com,hp-dl388g8-22.rhts.eng.pek2.redhat.com"  [systype7]="machine" [driver7]="ixgbe,sfc" [model7]="Intel-82599ES_10Gb,Solarflare-SFC9120_10G_Ethernet_Controller" [speed7]="10G,10G"

	[machine8]="hp-dl388g8-22.rhts.eng.pek2.redhat.com,hp-dl380g9-04.rhts.eng.pek2.redhat.com" [systype8]="machine" [driver8]="sfc,ixgbe" [model8]="Solarflare-SFC9120_10G_Ethernet_Controller,Intel-82599ES_10Gb" [speed8]="10G,10G"
	[machine9]="hp-dl388g8-22.rhts.eng.pek2.redhat.com,hp-dl380g9-04.rhts.eng.pek2.redhat.com" [systype9]="machine" [driver9]="sfc,i40e" [model9]="Solarflare-SFC9120_10G_Ethernet_Controller,Intel-Ethernet_Controller_X710_for_10Gb" [speed9]="10G,10G"
	[machine10]="hp-dl388g8-22.rhts.eng.pek2.redhat.com,hp-dl380g9-04.rhts.eng.pek2.redhat.com" [systype10]="machine" [driver10]="sfc,igb" [model10]="Solarflare-SFC9120_10G_Ethernet_Controller,Intel-I350_Gb" [speed10]="10G,1G"

)

origin_other_options="$other_options"
for ((i=0; i<$((${#test_pairs[*]}/5)); i++)); do
	test_driver=$driver
	if [ -z "$test_driver" ];then
		test_driver=$(echo ${test_pairs[driver$i]}|awk -F"," '{print $2}')
	fi

	#only run on those drivers
	TEST_DRIVERS="i40e ixgbe cxgb4"
	if ! echo $TEST_DRIVERS|grep -q all && ! echo $TEST_DRIVERS|grep -q $test_driver;then
			continue
	fi

	#use HOSTDEV method to attach cxgb4 VF to VM
	if [ "$test_driver" = "cxgb4" ];then
		other_options="${origin_other_options} --param=SRIOV_USE_HOSTDEV=yes"
	else
		other_options="${origin_other_options}"
	fi
	if [ -z "$driver" ] || echo ${test_pairs[driver$i]} | grep -e ",$driver" > /dev/null; then
		if [ "$format" = "new" ]; then
			#lstest | grep -v -e sriov_all | sed 's/ssched=yes.longtime/ssched=no/' |
			lstest | sed 's/ssched=yes.longtime/ssched=no/' | grep -v $test_driver |
				runtest ${dryrun} ${distro} -  \
					--arch=x86_64 \
					--variant=BaseOS \
					--ks-meta="beah_no_ipv6" \
					--machine=${test_pairs[machine${i}]} \
					--systype=${test_pairs[systype${i}]} \
					--param=image_name=${image_name} \
					--param=RPM_KERNEL=${RPM_KERNEL} \
					${other_options} \
					--param=mh-NIC_DRIVER=${test_pairs[driver${i}]} \
					--param=mh-NIC_MODEL=${test_pairs[model${i}]} \
					--param=mh-NIC_SPEED=${test_pairs[speed${i}]} \
					--param=NAY=yes
		else
			#lstest | grep sriov_all | sed 's/ssched=yes.longtime/ssched=no/' |
			lstest | grep -v $test_driver | runtest ${dryrun} ${distro} -  \
					--arch=x86_64 \
					--variant=server \
					--harness=restraint \
					--machine=${test_pairs[machine${i}]} \
					--systype=${test_pairs[systype${i}]} \
					--param=image_name=${image_name} \
					--param=RPM_KERNEL=${RPM_KERNEL} \
					${other_options} \
					--param=mh-NIC_DRIVER=${test_pairs[driver${i}]} \
					--param=mh-NIC_MODEL=${test_pairs[model${i}]} \
					--param=mh-NIC_SPEED=${test_pairs[speed${i}]} \
					--param=NAY=yes
		fi
	fi
done

