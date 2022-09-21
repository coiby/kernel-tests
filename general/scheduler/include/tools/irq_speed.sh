#!/bin/bash

loop=${1:-1}
irq=${2:-Function}
int=${3:-5}
awk -v cpu=$(nproc --all) -v loop=$loop -v irq="$irq" -v interval=$int -F' ' 'BEGIN {
	interval=interval? interval : 5
	irq_type=irq? irq: "Function"
	print "irq:"irq_type
	for (j=0; j<loop; j++)
	{
		print "loop "j" ...."
		sample()
	}
}

function sample(l)
{
	while ((getline l < "/proc/interrupts") > 0) {
		if (l ~ irq_type) {
			$0 = l
			for (i=2; i<=cpu+1; i++) {
				a[i]=$i
				a[0]+=$i
			}
			close("/proc/interrupts")
			break
		}
	}
	system("sleep "interval)
	while ((getline l < "/proc/interrupts") > 0) {
		if (l ~ irq_type) {
			$0 = l
			for (i=2; i<=cpu+1; i++) {
				b[i]=$i
				b[0]+=$i
			}
			close("/proc/interrupts")
			break
		}
	}

	for (i=2; i<=cpu+1; i++) {
		printf("%-20d\t%20d\t%20d\t%20d/s\n", a[i],b[i],b[i]-a[i],(b[i]-a[i])/5)
	}
	printf "Summary:"
	print b[0]-a[0],(b[0]-a[0])/(interval)"/s"
	delete a
	delete b
}

END {}' /proc/interrupts

