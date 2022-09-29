
bugid=$1
sub_type=${2:-fork_migration}

path=tests/${sub_type}/${bugid}
shf=$path/bz${bugid}.sh

mkdir -p $path
touch $shf

printf "#!/bin/bash\n\n" > $shf
printf "function bz${bugid}()\n" >> $shf
printf "{\n" >> $shf
printf "\t"'local binary_name=${1:-${FUNCNAME}}'"\n" >> $shf
printf "\tKILL_PIDS+=\" \$!\"\n" >> $shf
printf "\tKILL_NAMES+=\" \${binary_name}\"\n" >> $shf
printf "}\n" >> $shf
printf "\n" >> $shf
printf "function bz${bugid}_cleanup()\n" >> $shf
printf "{\n" >> $shf
printf "\treturn 0\n" >> $shf
printf "}\n" >> $shf

cp tests/fork_migration/bz1738415/load.c tests/${sub_type}/${bugid}/load.c
