#!/bin/bash
nfp_change_firmware()
{
	if ls -l /usr/lib/firmware/netronome/ | grep -e "^l.*" | grep -v '\-> nic-sriov/'
	then
		pushd /usr/lib/firmware/netronome/
			local FW=''
		for FW in *.nffw*; do
	  			if [ -L ${FW} ]; then
					ln -sf nic-sriov/${FW} ${FW}
	  			fi
			done
		popd
			# driver is loaded by initramfs
			dracut -f -v
			rhts-reboot
	fi
}

nfp_change_fw_sw()
{
	if ls -l /usr/lib/firmware/netronome/ |  grep -e "^l.*" | grep -v '\-> flower/'
	then
		echo "check fw ##########"
		pushd /usr/lib/firmware/netronome/
		local FW=''
		for FW in *.nffw*; do
			if [ -L ${FW} ]; then
				ln -sf flower/${FW} ${FW}
			fi
		done
		popd
		# driver is loaded by initramfs
		dracut -f -v
		rhts-reboot
	fi
}

