
// gcc -o tester tester.c -ludev
// You need the systemd-devel package for libudev.h

#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <libudev.h>


#define OFFLINE "echo 0 >  /sys/devices/system/cpu/cpu1/online"
#define ONLINE "echo 1 >  /sys/devices/system/cpu/cpu1/online"

#define EVENT_ONLINE 1
#define EVENT_OFFLINE 0

int wait_for_udev_event(struct udev *udev, struct udev_monitor *mon, int fd) {
	struct udev_device *dev;
	int event;
	while(1) {
	      fd_set fds;
	      struct timeval tv;
	      int ret;

	      event = -1;
	      
	      FD_ZERO(&fds);
	      FD_SET(fd, &fds);
	      tv.tv_sec = 0;
	      tv.tv_usec = 0;
	      
	      ret = select(fd+1, &fds, NULL, NULL, &tv);
	      if (ret > 0 && FD_ISSET(fd, &fds)) {
		      dev = udev_monitor_receive_device(mon);
		      if (dev) {
			      const char * action = udev_device_get_action(dev);
			      printf("I: ACTION=%s\n", action);
			      if (!strcmp(action, "online")) event=EVENT_ONLINE;
			      if (!strcmp(action, "offline")) event=EVENT_OFFLINE;
			      
			      /* free dev */
			      udev_device_unref(dev); 
		      }
		      if (event != -1) break;
	      }
	      /* 500 milliseconds */
	      //	usleep(500*1000);
	 }

	 return event;
	
}



int main (void) {

        /* setup cpu "online" and "offline" events receiving */
        // prepare_to_receive_events_from_udev()
      struct udev *udev;
      struct udev_device *dev;
      struct udev_monitor *mon;
      cpu_set_t mask;
      int fd;
      int event;
      int ret;
      int count = 0;
      int pid = getpid();
      
      /* create udev object */
      udev = udev_new();
      if (!udev) {
	      fprintf(stderr, "Can't create udev\n");
	      return 1;
      }
      
      mon = udev_monitor_new_from_netlink(udev, "udev");
      udev_monitor_filter_add_match_subsystem_devtype(mon, "cpu", NULL);
      udev_monitor_enable_receiving(mon);
      fd = udev_monitor_get_fd(mon);
      CPU_ZERO(&mask);
      CPU_SET(1, &mask);
      
      // Run for 1000 cycles, which is ~2 minutes
      while(count<1000) {
	     	
	      /* offline the cpu */
	      system(OFFLINE);
	      /* get the event */
	      //wait_for_udev();
	      event = wait_for_udev_event(udev, mon, fd);
	      printf (" Got event %d\n", event);
	      
	      /* online the cpu */
	      system(ONLINE);
                /* get the event */
	      //wait_for_udev();
	      event = wait_for_udev_event(udev, mon, fd);
	      printf (" Got event %d\n", event);

	      count ++;
	      
	      /* CPU is online, let's move to that CPU */
	      while ((ret = sched_setaffinity(pid, sizeof(mask), &mask)) != 0) {
	            fprintf(stderr, "set affinity failed ret: %d after %d iterations\n", ret, count);
	            return 1;
	      }
      }
      return 0;
}


