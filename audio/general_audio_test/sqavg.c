#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/****************************************
 * Console audio manipulation utilities *
 * Author: Erik Hamera                  *
 * Licence: GNU GPLv2                   *
 ****************************************/


int main(int argc, char **argv){
        int64_t i, j, x, l, reslen, *res, filesize;
        int16_t *buf;
        FILE *fptr;
        int64_t buf_sum, buf_avg, buf_sq, res_avg_min, res_avg_max, res_sq_min, res_sq_max;
        int samplesize, n;


// arguments
        printf("args=%d\n", argc);
        printf("ARG0=%s\n",argv[0]);
        if(argc>1){
                printf("ARG1=%s\n",argv[1]);
        }else{
                printf("The first argument should be a filename\n");
                exit(1);
        }
        if(argc>2){
                printf("ARG2=%s\n",argv[2]);
                samplesize=atoi(argv[2]);
                if(samplesize==0){
                        printf("The second argument is sample size. Sample of 0 size is nonsense, setting 44050\n");
                        samplesize=44050;
                }else{
                        printf("Sample size=%d\n",samplesize);
                }
        }else{
                printf("Setting default sample size to 44050\n");
                samplesize=44050;
        }


// file
        fptr = fopen(argv[1],"rb");

        if(fptr == NULL){
                printf("Error reading file %s\n", argv[1]);
                exit(1);
        }

        fseek(fptr, 0L, SEEK_END);
        filesize = ftell(fptr);
        l=filesize/sizeof(int16_t);
        printf("File size=%ld\n",filesize);
        rewind(fptr);

        buf=malloc(l*sizeof(int16_t));

        if(buf == NULL){
                printf("Error allocating memory\n");
                exit(1);
        }

        fread(buf, sizeof(int16_t), l, fptr);

        if(l>=0x7FFFFFFFFFFFFFFF){
        printf("Error, file too big for this algorithm\n");
        exit(1);
        /* 2^47-1 signed 16-bit numbers can be added safely to the signed 64-bit number */
        }

// computations
        buf_sum=0;
        for(i=0; i<l; i++){
                buf_sum+=buf[i];
        }
        buf_avg=buf_sum/l;
        printf("integer SUM=%ld, AVG=%ld\n", buf_sum, buf_avg);

        //Allocate buffer for partial results
        //There will be l/samplesize parts with n 64-bit results
        n=2;
        // 0 = average
        // 1 = SUM i=0..samplesize ( xi - xavg )^2

        reslen=(l+(samplesize-1))/samplesize;
        res=malloc(reslen*n*sizeof(int64_t));

        //debug
        printf("samplesize\t%d, l\t%ld, n\t%d, reslen\t%ld\n", samplesize, l, n, reslen);

        if(res == NULL){
                printf("Error allocating memory\n");
                exit(1);
        }

        for(i=0; i<reslen; i++){
                buf_sum=0;
                for(j=0; j<samplesize; j++)
                        buf_sum+=buf[i*samplesize+j];
                buf_avg=buf_sum/samplesize;
                buf_sq=0;
                for(j=0; j<samplesize; j++){
                        x=(buf[i*samplesize+j]-buf_avg);
                        buf_sq+=x*x;
                }
                printf("Sample\t%ld, AVG\t%ld, sqavg\t%ld\n", i, buf_avg, buf_sq/samplesize);
                res[i*n+0]=buf_avg;
                res[i*n+1]=buf_sq/samplesize;
        }
        res_avg_min=0x7FFFFFFFFFFFFFFF;
        res_avg_max=-0x7FFFFFFFFFFFFFFF;
        res_sq_min=0x7FFFFFFFFFFFFFFF;
        res_sq_max=-0x7FFFFFFFFFFFFFFF;
        for(i=0; i<reslen; i++){
                if(res[i*n+0]<res_avg_min)
                        res_avg_min=res[i*n+0];
                if(res[i*n+0]>res_avg_max)
                        res_avg_max=res[i*n+0];
                if(res[i*n+1]<res_sq_min)
                        res_sq_min=res[i*n+1];
                if(res[i*n+1]>res_sq_max)
                        res_sq_max=res[i*n+1];
        }
        printf("AVG min\t%ld, max\t%ld, SQAVG min\t%ld, max\t%ld\n", res_avg_min, res_avg_max, res_sq_min, res_sq_max);

// cleanup
        free(res);
        free(buf);
        fclose(fptr);
        return 0;
}
