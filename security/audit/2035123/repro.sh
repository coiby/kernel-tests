#!/bin/bash
i=0
while [ $i -le 66 ]
do
	touch /root/aaa
	(( i++ )) || true
done