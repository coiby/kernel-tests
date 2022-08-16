#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include<string.h>
#include<strings.h>

int main(int argc,char** argv){

    int fstatus=-1;
    /* options processing variables */
    char* progname;
    char* optstring="ds:n:iD:";
    char* short_options_desc="\nUsage : %s [-h] [-s size] [-n chunk_nb]\n\n";
    char* addon_options_desc="\
                              \t-h\t\tshow this message\n\
                              \t-s size\t\tsize of each allocated chunk in Ko\n\
                              \t-nchunk_nb\t\tnumbre of chunk to allocate\n\n";
    int  option;
    int i,j;
    char* tbuffer=NULL;
    char** pbuffer;
    int chunk_nb=1;
    int  chunk_size=1024;
    long int  size,tsize; 
    time_t etime,atime,btime;
    double   dtime_mpi,ftime_mpi ;
    double   max_ftime_mpi,min_ftime_mpi ;
    long int time1,time2; 
    struct timespec tp,tp2;
    /* get current program name */
    progname=rindex(argv[0],'/');
    if(progname==NULL)
        progname=argv[0];
    else
        progname++;
    /* process options */
    while((option = getopt(argc,argv,optstring)) != -1)
    {
        switch(option)
        {
            case 's' :
                chunk_size*=strtol(optarg,NULL,10);
                break;
            case 'n' :
                chunk_nb=strtol(optarg,NULL,10);
                break;
            case 'h' :
            default :
                fprintf(stdout,short_options_desc,progname);
                fprintf(stdout,"%s\n",addon_options_desc);
                exit(0);
                break;
        }
    }
    /* on cree le buffer de remplissage */
    tbuffer=(char *)malloc(1024*sizeof(char));
    if( tbuffer == NULL ){
        fprintf(stderr,"unable to allocate filling buffer");
    }
    else {
        for(i=0;i<1024;i++){
            tbuffer[i]='a';
        }
    }
    /* on cree le tableau de buffer */
    clock_gettime(CLOCK_REALTIME,&tp);
    //time1=1e+9*tp.tv_sec+tp.tv_nsec;
    pbuffer=(char**)malloc(chunk_nb*sizeof(char*));
    for(i=0;i<chunk_nb;i++) {
        pbuffer[i]=(char*)malloc(chunk_size*sizeof(char));
        for(j=0;j<chunk_size-1;j+=1024){
            memcpy(&pbuffer[i][j],tbuffer,1024);
            pbuffer[i][0]='a';
        }

    }
    clock_gettime(CLOCK_REALTIME,&tp2);
    //time2=(1e+9*tp2.tv_sec+tp2.tv_nsec)-time1;
    time2=(1e+9*(tp2.tv_sec-tp.tv_sec) + tp2.tv_nsec - tp.tv_nsec);
    // fprintf(stdout,"Time for rank %d  for Allocating Buffers : %f second(s)  \n",myrank,ftime_mpi);
    time(&btime);
    size= chunk_size * chunk_nb /1024 /1024 ;
    //fprintf(stdout,"Total Buffers Size %ld Mo \n",size);
    ftime_mpi = time2 * 1e-9; 
    //fprintf(stdout,"Time for Allocating Buffers : %f second(s)  \n",ftime_mpi);
    fprintf(stdout,"%f\n",ftime_mpi);
    // if(myrank==npes-1)   fprintf(stdout,"Buffer[%d] : \t%u Ko allocated in less than %d second(s) by rank %d \n",i,chunk_size/1024,btime-atime+1,myrank);
    free(tbuffer);
    free(pbuffer);
    // fprintf(stdout,"Minimum time over ranks for Freeing Buffers : %f second(s)  \n",min_ftime_mpi);
    // fprintf(stdout,"Maximum time over ranks for Freeing Buffers : %f second(s)  \n",max_ftime_mpi);
    return 0;
}
