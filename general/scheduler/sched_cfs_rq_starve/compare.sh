#!/bin/bash
awk 'BEGIN{i=0; a[i][0]=0; procs[i]=0;}
	{procs[i]=procs[i]+1; a[i][procs[i]]=$6"\t"$7;} ENDFILE{procs[i]=NR;i=i+1;procs[i]=0}
	END{ for(j=1;j<=procs[0];j++)
	     {
		printf ("%-24s\t%-24s", a[0][j],a[1][j]);
		if (a[0][j] == a[1][j])
		{
			printf "%s\n", " *starved"
		}
		else
		{
			printf "\n"
		}
	     }
	}' old new
