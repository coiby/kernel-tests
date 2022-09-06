/*	copied from /kernel/memory/Fujitsu-oom-kill-bz222492	*/

/* oomtest.c    COPYRIGHT FUJITSU LIMITED 2009			*/
/*		Copyright Red Hat 2011				*/
/* test program for triggering the kernels oom_kill function	*/
#define __USE_BSD
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <syslog.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <errno.h>
#include <getopt.h>
#include <sys/time.h>
#include <sys/stat.h>
// globals
#define SLEEP_SEC    1200
volatile int	nextchild=1;
volatile int	killed=0;
volatile int	nextsig=0;
volatile pid_t	lastpid=0;
int		lastsig=0;
int		lastchild=0;
size_t		allocsize=1314324480;
size_t		total=0;
int		waittime=SLEEP_SEC;
pid_t		pgpid=0;	// pid of the mempress leader
size_t		page=0;
int		compat=0;	// use traditional oom_adj 
// adjust oom_adj in /proc/self/oom_adj
int do_oom(const char *procfile,const char *adj){
    FILE		*fp;
    if( (fp = fopen(procfile,"w")) == NULL ){
	perror("fopen");
	return(1);
    }
    fwrite(adj, sizeof(char), strlen(adj), fp);
    fclose(fp);
    return(0);
}
int adj2score(int adj){
  return(2000*(adj+17)/32-1000);
}
// oom_disable - set oom_adj to OOM_DISABLE(-17) in /proc/self/oom_adj
// or set oom_score_adj to OOM_DISABLE(-1000) in /proc/self/oom_score__adj
void oom_disable(){
int ret;
  if((compat<2) && (ret=do_oom("/proc/self/oom_adj","-17"))!=0 && (compat>0))
    ret=do_oom("/proc/self/oom_score_adj","-1000");
  if(ret){
    syslog(LOG_ERR,"failed to set both oom_adj and oom_score_adj");
    exit(1);
  }
}
oom_adj(int adj){
char adjbuf[6];
int ret;
  if(adj<-17) adj=-17;
  else if(adj>15) adj=15;
  sprintf(adjbuf,"%d",adj);
  if((compat<2) && (ret=do_oom("/proc/self/oom_adj",adjbuf))!=0 && (compat>0)){
    sprintf(adjbuf,"%d",adj2score(adj));
    ret=do_oom("/proc/self/oom_score_adj",adjbuf);
  }
  if(ret){
    syslog(LOG_ERR,"failed to set both oom_adj and/or oom_score_adj");
    exit(1);
  }
}
// take_mem: allocate the requested amount of memory, use it and then lock it
// do some logging too
void take_mem(const size_t amount,const char *where){
char *p,*q;
FILE		*fp;
char		buf[256];
long		score,rc;
  syslog(LOG_INFO,"%3d %-20.20s started, requesting %15ld, total %15ld\n",lastchild,where,amount,amount+total);
  if(amount){
    if((p=malloc(amount))==NULL){
      sprintf(buf,"%-.20s: %s",where,"malloc");
      perror(buf);
      exit(1);
    }
    if(page==0) page=getpagesize();
    for(q=p;q<p+amount;q+=page) 
    {
      *q=1;
      if(mlock(q,page)==-1){	// mlock by page, less thrashing
	if(q!=p || strcmp(where,"fork_child")!=0) break; 			// gracefully bail out, the other processes will take the rest anyway
	/* but die on first mlock in fork_child */
        sprintf(buf,"%-.20s: %s",where,"mlock");
	perror(buf);
	exit(1);
      }
    }
    if(kill(getppid(),SIGUSR1)) // notify the mempress leader, I am done
      syslog(LOG_ERR,"kill(%d): %s",getppid(),strerror(errno));
  }
}
// the child process taking 1/3 of ram, should be killed by oom_kill
void fork_child(){
  oom_adj(12);
  if(setpgid(0,0)!=0) {
    syslog(LOG_ERR,"setpgid failed: %s",strerror(errno));
  }
  take_mem(allocsize,"fork_child");
  if(setpgrp()!=0)
    syslog(LOG_ERR,"setpgrp failed: %s",strerror(errno));
  sleep(waittime);
  exit(0);
}
// memory hog II
void mempress(){
  oom_adj(10);
  take_mem(allocsize,"mempress");
  if(setpgid(0,pgpid)!=0) {
    syslog(LOG_ERR,"setpgid failed: %s",strerror(errno));
  }
  sleep(waittime);
  exit(0);
}
// to catch SIGUSR1
void reaperusr(int sig){
  signal(SIGUSR1,&reaperusr);
  nextchild++;
  lastpid=0;
}
// to catch SIGCHLD
void reaperchild(int sig){
  signal(SIGCHLD,&reaperchild);
  nextsig++;
}
// group leader for mempress processes
void group_lead(){
  FILE	*fp;
  pid_t	wpid=1;
  int	rc;
  int	status;
  sigset_t childmask;
  char	*p;
  char	buf[2048];

  oom_disable();		// we want to survive to report success/failure
  take_mem(0,"oomtest lead");
  sigemptyset(&childmask);
  sigaddset(&childmask,SIGCHLD);
  sigprocmask(SIG_UNBLOCK,&childmask,0);
  signal(SIGCHLD,&reaperchild);
  signal(SIGUSR1,&reaperusr);
  mlockall(MCL_CURRENT); // to avoid futher trashing
  if(page==0) page=getpagesize();
  while((killed==0) && (allocsize >= page) && (lastchild<nextchild)){
    lastchild++;
    if((rc=fork())==0){		// succesfully forked, child
      sigprocmask(SIG_BLOCK,&childmask,0); // just to be sure children will be caught here
      if(pgpid==0)			// first child - this will change in the parent only, and will be inherited thereafter only
	fork_child();		 	// never returns
      mempress();			// never returns
    } else if(rc==-1){
      perror("trouble forking under pressure");
    } else {				// succesfully forked, parent
      total+=allocsize;
      lastpid=rc;
      if(pgpid==0){
	pgpid=rc;			// from now forking mempress childs
	allocsize/=2;
      } else if(setpgid (rc,pgpid)!=0) syslog(LOG_ERR,"setpgid failed: %s",strerror(errno));
      if(nextsig>lastsig) { 
	wpid=wait4(-1,&status,WNOHANG,0);
	if(wpid==-1) if(errno!=ECHILD) perror("wait4");
	if(wpid>0){
	  lastsig++;
	  if(WIFSIGNALED(status))
	    if(WTERMSIG(status)==SIGKILL){
	      syslog(LOG_INFO,"ended %ld sig %d",wpid,WTERMSIG(status));
	      killed=1;
	    }
	    if(WIFEXITED(status)){
	      syslog(LOG_INFO,"ended %ld status %d",wpid,WEXITSTATUS(status));
	      if(WEXITSTATUS(status))// the exited child complained, backoff
		allocsize/=2;
	    }
	  }	// end if(wpid>0)
      }	// activity in parent after fork done
    }
/* the following events can happen:
 * a) a child successfully mlock'd the requested memory and sent a SIGUSR1
 * b) a child experienced some error, and exited with a non-0 status
 *   - mainly a coding error, in theory maybe some resource temporarily unavailable, so backoff
 * c) a child got killed by oom_kill, GOOD
 * d) a child finished its waiting, exited with a 0 status, BAD
 */
    pause(); // waiting to something to happen
  } // killed || allocsz < page || lostchild , stop forking
  while((wpid=wait4(-1,&status,WNOHANG,0))>0){
    lastsig++;
    syslog(LOG_INFO,"%ld ended with %s %d",wpid, WIFSIGNALED(status)?"sig":"status", WIFSIGNALED(status)?WTERMSIG(status):WEXITSTATUS(status));
    if((WIFSIGNALED(status)) && (WTERMSIG(status)==SIGKILL)) killed=1;
    if(pgpid) {
      syslog(LOG_INFO,"killpg %ld",pgpid);
      killpg(pgpid,SIGKILL);
      if(lastpid>0) kill(lastpid,SIGKILL);
    }
    if(killed){
      // report success
      syslog(LOG_INFO,"oomtest PASSED");
      exit(0);
    }
    if(lastsig<lastchild) pause(); // waiting to something to happen, but only if we not finished already
  } // while(wpid...
  if(killed){ //fix a race that child maybe oom killed before the last mempress
    // report success
    syslog(LOG_INFO,"oomtest PASSED, oom kill before the last mempress");
    exit(0);
  }
  // report failure
  syslog(LOG_INFO,"oomtest FAILED");
  killpg(pgpid,SIGKILL);
  if(lastpid>0) kill(lastpid,SIGKILL);
  exit(1); // no child was killed, failed to trigger oom_kill or an innocent victim sacrified
}
/* the programs main function					*/
int main(int argc, char **argv)
{
  int	rc,status;
  pid_t	pid,wpid;
 
  openlog("oomtest",LOG_PERROR|LOG_PID,LOG_USER);
  while( (rc = getopt(argc, argv, "s:t:c:")) != -1 ){
    switch( rc ) {
    case    's':
      allocsize = atol( optarg );
      break;
    case    't':
      waittime = atoi( optarg );
      break;
    case    'c':
      compat = atoi( optarg );
      // the compatitility levels:
      // 0 - oom_adj
      // 1 - both
      // 2 oom_score_adj
      if((compat<0)||(compat>2)){
	syslog(LOG_ERR,"unimplemeted (yet)");
	exit(2);
      }
      break;
    default:
USAGE:
      fprintf(stderr,
	"USAGE: %s [-s memory_allocation_size(byte)] [-t waiting_time(sec)] [-c compatibility]\n",
	argv[0]);
      exit(1);
    }
  }
  if(allocsize==0) goto USAGE;
  group_lead();		// never returns
}
