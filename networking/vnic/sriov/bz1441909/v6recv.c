#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <errno.h>
#include <signal.h>
#include <sys/select.h>
#include <unistd.h>
#include <strings.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>
#include <netinet/in.h>


int exitFlag = 0;


void exit_handler(int signo)
{
    exitFlag = 1;
    printf("Catch signal %d\n", signo);
}


int main(int argc, char *argv[])
{
    int sockFd = 0;
    fd_set       sockFdSet;
    int ret;
    struct timeval timeOut;
    struct sockaddr_in6 addr6;
    struct sockaddr_in6 srcAddr6;
    int dataLen;
    char recvBuf[3000];
    int recvSize;
    int msgLen;
    int msgCount;
    int i;

    if (argc != 2)
    {
        printf("Usage: v6recv <bound IPv6 addr>\n");
        return -1;
    }

    sockFd = socket(AF_INET6, SOCK_RAW, IPPROTO_SCTP);
    if (sockFd < 0)
    {
        printf("socket() failed, errno: %d\n", errno);
        return -1;
    }

    bzero(&addr6, sizeof(addr6));
    addr6.sin6_family = AF_INET6;
    addr6.sin6_port = 0;
    inet_pton(AF_INET6, argv[1], (struct sockaddr *)&addr6.sin6_addr);

    if (bind(sockFd, (struct sockaddr *)&addr6, sizeof(addr6)) < 0)
    {
        printf("bind() faild, errno: %d\n", errno);
        close(sockFd);
        return -1;
    }

    timeOut.tv_sec = 0;
    timeOut.tv_usec = 0;

    msgCount = 0;
    while (1)
    {
        if (exitFlag)
        {
            printf("exit from while loop\n");
            break;
        }

        FD_ZERO(&sockFdSet);
        FD_SET(sockFd, &sockFdSet);

        ret = select(sockFd+1, &sockFdSet, NULL, NULL, &timeOut);
        if (ret < 0)
        {
            printf("select() failed, ret: %d, errno: %d\n", ret, errno);
            continue;
        }

        if (ret == 0)
        {
            /* nothing arrived */
            continue;
        }

        if (FD_ISSET(sockFd, &sockFdSet))
        {
	    fflush(stdout);
            ret = ioctl(sockFd, FIONREAD, (void *)&dataLen);
            if (ret != 0)
            {
                printf("ioctl() failed, errno: %d\n", errno);
                break;
            }

            if (dataLen == 0)
            {
                printf("ioctl() FIONREAD read 0 bytes ready\n");
                continue;
            }
            
            recvSize = recvfrom(sockFd, recvBuf, 2048, 0, (struct sockaddr *)&srcAddr6, &msgLen);            
            if (recvSize < 0)
            {
                printf("recvfrom() failed, errno: %d\n", errno);
                continue;
            }

            if (recvSize == 0)
            {
                printf("recvSize is 0\n");
                continue;
            }

            printf("%d bytes received\n", recvSize);
            if (recvSize > 16)
                recvSize = 16;

            printf("First 16 bytes of received msg:\n");
            for (i = 0; i < recvSize; i++)
            {
                printf("%02x ", (unsigned char)recvBuf[i]);
            }
            printf("\n======= end =======\n\n");
        }

    }

    close(sockFd);
    return 0;
}
