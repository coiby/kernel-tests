#include <time.h>
#include <stdio.h>
#include <sys/time.h>


int main (void)
{
  int i;

  printf("Start of time test.\n");

  for (i = 0; i < 100000000; i++)
  {
    time_t time_before, time_after, curtime;
    struct timeval tv;
	
    time_before = time ((time_t *) 0);
    //    printf("time_before = %ld\n", time_before);

    gettimeofday(&tv, NULL);
    curtime=tv.tv_sec;
    //    printf("curtime = %ld\n", curtime); 

    time_after = time ((time_t *) 0);
    //    printf("time_after = %ld\n", time_after);
      
    if (curtime < time_before || curtime > time_after)
    {
      fprintf (stderr, "curtime %ld time_before %ld time_after %ld\n",
	       curtime, time_before, time_after);
      fprintf (stderr, "Failed:\n");
      return 1;
    }
    if ((!(i == 0)) && (!(i % 10000000))) printf("Count=%i\n", i);
  }
  printf("Passed:\n");
  return 0;
}

