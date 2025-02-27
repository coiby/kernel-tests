/*
 * source: https://developer.toradex.com/software/linux-resources/linux-features/watchdog-linux/#c-example
 */

#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/watchdog.h>

static int api_watchdog_fd = -1;

int api_watchdog_open(const char * watchdog_device)
{
    int ret = -1;
    if (api_watchdog_fd >= 0){
        fprintf(stderr, "watchdog already opened\n");
        return ret;
    }
    api_watchdog_fd = open(watchdog_device, O_RDWR);
    if (api_watchdog_fd < 0){
        fprintf(stderr, "Could not open %s: %s\n", watchdog_device, strerror(errno));
        return api_watchdog_fd;
    }
    return api_watchdog_fd;
}

int api_watchdog_hwfeed(void)
{
    int ret = -1;
    if (api_watchdog_fd < 0){
        fprintf(stderr, "watchdog must be opened first!\n");
        return ret;
    }
    ret = ioctl(api_watchdog_fd, WDIOC_KEEPALIVE, NULL);
    if (ret < 0){
        fprintf(stderr, "Could not pat watchdog: %s\n", strerror(errno));
    }
    return ret;
}

int api_watchdog_init(const char *pcDevice)
{
    printf("Open watchdog\n");
    int ret = 0;
    ret = api_watchdog_open("/dev/watchdog");
    if(ret < 0){
        return ret;
    }
    ret = api_watchdog_hwfeed();
    return ret;
}

int main(int argc, char **argv)
{
    int ret = 0;
    ret = api_watchdog_init("/dev/watchdog");
    if(ret < 0) {
        fprintf(stderr, "Could not init watchdog: %s\n", strerror(errno));
    }
    while(1)
    {
        ret = api_watchdog_hwfeed();
        if(ret < 0) {
            return ret;
        }
        sleep(1);
    }
}
