#!/bin/bash

function bz1804092()
{
    rlRun "insmod ${DIR_MODULE}/${FUNCNAME}.ko"
    sleep 5
    rlRun "rmmod ${FUNCNAME}"
}
