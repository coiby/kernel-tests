#!/bin/bash

FILE=$(readlink -f ${BASH_SOURCE[0]})
CDIR=$(dirname $FILE)

run_qat()
{
	python3 "$CDIR"/qat ${1}
}
