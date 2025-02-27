#!/bin/bash

function upstream_knownissue_filter()
{
	# http://lists.linux.it/pipermail/ltp/2017-January/003424.html
	kernel_in_range "4.8.0-rc6" "4.12" && tskip "utimensat01.*" unfix
	# http://lists.linux.it/pipermail/ltp/2019-March/011231.html
	kernel_in_range "5.0.0" "5.2.0" && tskip "mount02" unfix
	# https://lore.kernel.org/linux-fsdevel/7854000d2ce5ac32b75782a7c4574f25a11b573d.1689757133.git.jstancek@redhat.com/
	kernel_in_range "6.5.0" "6.6.0" && tskip "sendfile07" unfix
	# https://lore.kernel.org/linux-fsdevel/20230714085124.548920-1-hch@lst.de/
	# commit 20c64ec83a9f779a750bbbcc1d07d065702313a5
	kernel_in_range "6.5.0" "6.5.0-rc3" && tskip "writev07" unfix
}
