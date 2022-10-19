distro="RHEL-6.10-20180525.0"
#RPM_KERNEL="http://netqe-bj.usersys.redhat.com/share/liali/kernel-3.10.0-691.el7.x86_64.rpm"
#image_name="RHEL-ALT-7.5-20171106.1.qcow2"
image_name="rhel6.10.qcow2"
distro=${distro:-"RHEL-7.2-20150820.0"}
dryrun=${dryrun:-""}
if [ -n "$dryrun" ]; then
	dryrun="-n"
fi
other_options="$@"

declare -A test_pairs=(
	[machine0]="hp-dl380g9-02.rhts.eng.pek2.redhat.com,hp-dl380g9-05.rhts.eng.pek2.redhat.com" [systype0]="prototype,machine" [driver0]="be2net,be2net" [model0]="Emulex-OneConnect_NIC_-Skyhawk,Emulex-OneConnect_NIC_-Skyhawk"
	[machine1]="hp-dl380g9-05.rhts.eng.pek2.redhat.com,hp-dl380g9-02.rhts.eng.pek2.redhat.com" [systype1]="machine,prototype" [driver1]="be2net,be2net" [model1]="Emulex-OneConnect_NIC_-Skyhawk,Emulex-OneConnect_NIC_-Skyhawk"

	[machine2]="hp-dl388g8-19.rhts.eng.pek2.redhat.com,hp-dl380g9-06.rhts.eng.pek2.redhat.com" [systype2]="machine,prototype" [driver2]="cxgb4,bnx2x" [model2]="Chelsio-T420-CR_Unified_Wire_Ethernet_Controller,Broadcom-NetXtreme_II_BCM57810_10_Gb"
	[machine3]="hp-dl380g9-06.rhts.eng.pek2.redhat.com,dell-per730-20.rhts.eng.pek2.redhat.com" [systype3]="prototype,machine" [driver3]="bnx2x,cxgb4" [model3]="Broadcom-NetXtreme_II_BCM57810_10_Gb,Chelsio-T420-CR_Unified_Wire_Ethernet_Controller"
	
	[machine4]="hp-dl380g9-02.rhts.eng.pek2.redhat.com,hp-dl380pg8-05.rhts.eng.pek2.redhat.com" [systype4]="prototype,prototype" [driver4]="cxgb4,cxgb4" [model4]="Chelsio-T580-CR_Unified_Wire_Ethernet_Controller,Chelsio-T422-CR_Unified_Wire_Ethernet_Controller"
	[machine5]="hp-dl380pg8-05.rhts.eng.pek2.redhat.com,hp-dl380g9-02.rhts.eng.pek2.redhat.com" [systype5]="prototype,prototype" [driver5]="cxgb4,cxgb4" [model5]="Chelsio-T422-CR_Unified_Wire_Ethernet_Controller,Chelsio-T580-CR_Unified_Wire_Ethernet_Controller"

	[machine6]="hp-dl380pg8-15.rhts.eng.pek2.redhat.com,hp-dl380g9-01.rhts.eng.pek2.redhat.com" [systype6]="machine,prototype" [driver6]="be2net,i40e" [model6]="Emulex-OneConnect_10Gb-be3,Intel-Ethernet_Controller_XL710_for_40Gb"
	[machine7]="hp-dl388g8-22.rhts.eng.pek2.redhat.com,dell-per730-25.rhts.eng.pek2.redhat.com" [systype7]="machine,machine" [driver7]="sfc,ixgbe" [model7]="Solarflare-SFC9120,Intel-Ethernet_10G_2P_X520_Adapter"

	[machine8]="hp-dl380pg8-15.rhts.eng.pek2.redhat.com,hp-dl380g9-01.rhts.eng.pek2.redhat.com" [systype8]="machine,prototype" [driver8]="be2net,sfc" [model8]="Emulex-OneConnect_10Gb-be3,Solarflare-SFC9140"
	[machine9]="hp-dl380pg8-15.rhts.eng.pek2.redhat.com,hp-dl380pg8-08.rhts.eng.pek2.redhat.com" [systype9]="machine" [driver9]="cxgb4,mlx4_en" [model9]="Chelsio-T520-CR_Unified_Wire_Ethernet_Controller,Mellanox-MT26448"

	[machine10]="netqe2.knqe.lab.eng.bos.redhat.com,netqe11.knqe.lab.eng.bos.redhat.com" [systype10]="machine,machine" [driver10]="mlx5_core,bnx2x" [model10]="Mellanox-MT27710_Family,Broadcom-NetXtreme_II_BCM57800_1-10_Gb"
	[machine11]="dell-per730-17.rhts.eng.pek2.redhat.com,dell-per730-16.rhts.eng.pek2.redhat.com" [systype11]="prototype" [driver11]="bnxt_en,mlx5_core" [model11]="Broadcom-BCM57304_NetXtreme-C_10Gb25Gb-40Gb-50Gb_Ethernet_Controller,Mellanox-MT27710_Family"

	[machine12]="dell-per730-16.rhts.eng.pek2.redhat.com,dell-per730-17.rhts.eng.pek2.redhat.com" [systype12]="prototype" [driver12]="mlx5_core,i40e" [model12]="Mellanox-MT27710_Family,Intel-Ethernet_Controller_XXV710_for_25Gb28"
	[machine13]="dell-per730-17.rhts.eng.pek2.redhat.com,dell-per730-16.rhts.eng.pek2.redhat.com" [systype13]="prototype" [driver13]="bnxt_en,bnxt_en" [model13]="Broadcom-BCM57304_NetXtreme-C_10Gb25Gb-40Gb-50Gb_Ethernet_Controller,Broadcom-BCM57414_NetXtreme-E_10Gb25Gb_RDMA_Ethernet_Controller"

	[machine14]="dell-per730-16.rhts.eng.pek2.redhat.com,dell-per730-17.rhts.eng.pek2.redhat.com" [systype14]="prototype" [driver14]="mlx5_core,bnxt_en" [model14]="Mellanox-MT27710_Family,Broadcom-BCM57304_NetXtreme-C_10Gb25Gb-40Gb-50Gb_Ethernet_Controller"
	[machine15]="hp-dl388g8-22.rhts.eng.pek2.redhat.com,dell-per730-14.rhts.eng.pek2.redhat.com" [systype15]="machine,prototype" [driver15]="sfc,mlx5_core" [model15]="Solarflare-SFC9120_10G_Ethernet_Controller,Mellanox-MT27700_Family"

	[machine16]="hp-dl388g8-22.rhts.eng.pek2.redhat.com,ibm-x3650m5-01.rhts.eng.pek2.redhat.com" [systype16]="machine,prototype" [driver16]="qlcnic,qede" [model16]="QLogic-ISP8324_1-10Gb,QLogic-FastLinQ_QL41000_Series_10-25-40-50Gb"

	[machine17]="hp-dl388g8-22.rhts.eng.pek2.redhat.com,hp-dl380g9-01.rhts.eng.pek2.redhat.com" [systype17]="machine,prototype" [driver17]="qlcnic,nfp" [model17]="QLogic-ISP8324_1-10Gb,Netronome-Device_4000"

)

origin_other_options="$other_options"
for ((i=0; i<$((${#test_pairs[*]}/4)); i++)); do
	test_driver=$driver
	if [ -z "$test_driver" ];then
		test_driver=$(echo ${test_pairs[driver$i]}|awk -F"," '{print $2}')
	fi

	#only run on those drivers
	TEST_DRIVERS="mlx5_core bnxt_en"
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
					--variant=Server \
					--ks-meta="beah_no_ipv6" \
					--machine=${test_pairs[machine${i}]} \
					--systype=${test_pairs[systype${i}]} \
					--param=image_name=${image_name} \
					--param=RPM_KERNEL=${RPM_KERNEL} \
					${other_options} \
					--param=mh-NIC_DRIVER=${test_pairs[driver${i}]} \
					--param=mh-NIC_MODEL=${test_pairs[model${i}]} \
					--param=NAY=yes
		else
			#lstest | grep sriov_all | sed 's/ssched=yes.longtime/ssched=no/' |
			lstest | grep -v $test_driver | runtest ${dryrun} ${distro} -  \
					--arch=x86_64 \
					--variant=Server \
					--ks-meta="beah_no_ipv6" \
					--machine=${test_pairs[machine${i}]} \
					--systype=${test_pairs[systype${i}]} \
					--param=image_name=${image_name} \
					--param=RPM_KERNEL=${RPM_KERNEL} \
					${other_options} \
					--param=mh-NIC_DRIVER=${test_pairs[driver${i}]} \
					--param=mh-NIC_MODEL=${test_pairs[model${i}]} \
					--param=NAY=yes
		fi
	fi
done
	
