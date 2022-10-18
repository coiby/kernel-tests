#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <arpa/inet.h>

/* usage: ./command srcaddr dstaddr file repeat */

unsigned short str2hexstr(char *src, char *dest)
{
    unsigned short i = 0; int j = 0; int idx = 0;
    char tmp;
    while ( i < strlen(src) )
    {
	if (src[i] >= '0' && src[i] <= '9') 
	{   
	    if (idx == 1)
            {   
		tmp = ((tmp&0xf)) << 4 | ((src[i]-'0')&0xf);
                idx = 0;
                dest[j++] = tmp;
                i++;
            }
            else
            {
                tmp = (src[i]-'0')&0xf;
                i++;
                idx++;
            }
        }
        else
        {
            if (src[i] >='A' && src[i] <= 'F')
            {
                if (idx == 1)
                {
                    tmp = ((tmp&0xf)) << 4 | ((src[i]-'A' + 10)&0xf);
                    idx = 0;
                    dest[j++] = tmp;
                    i++;
                }
                else
                {   
		    tmp = (src[i]-'A'+10)&0xf;
                    i++;
		    idx++;
                }
            }
            else
            {
                if (src[i] >= 'a' && src[i] <= 'f')
                {
                    if (idx == 1)
                    {
                        tmp = ((tmp&0xf)) << 4 | ((src[i]-'a' + 10)&0xf);
                        idx = 0;
                        dest[j++] = tmp;
                        i++;
                    }
                    else
                    {
                        tmp = (src[i]-'a'+10)&0xf;
                        i++;
                        idx++;
                    }

                }
		else
		{
		    i++;
		}
	    }
	}
    }
    return j;

}

int main(int argc, char **argv)
{
    struct sockaddr_in6 s_addr, d_addr;
	int sock;
	int addr_len;
	int len, isdnlen, ll, i;
	char buff[3000];
	char uastr[8000];
	FILE *file;

	if ((sock = socket(AF_INET6, SOCK_RAW, IPPROTO_SCTP)) == -1) 
	{
		perror("socket");
		exit(errno);
	} else
		printf("create socket.\n\r");

	bzero(&s_addr, sizeof(s_addr));
	s_addr.sin6_family = AF_INET6;
	s_addr.sin6_port = htons(0);

	if (argv[1])
		inet_pton(AF_INET6, argv[1], &s_addr.sin6_addr);
	else {
		printf("usage:./command srcaddr dstaddr file repeat\n");
		exit(0);
	}

	if (bind(sock, (struct sockaddr *) &s_addr, sizeof(struct sockaddr_in6))  // IPv6  
	    == -1) {  
	    perror("bind");  
	    exit(1);  
	} else  
	    printf("binded\n");  

	bzero(&d_addr, sizeof(d_addr));
	d_addr.sin6_family = AF_INET6;
	d_addr.sin6_port = htons(0);

	if (argv[2])
		inet_pton(AF_INET6, argv[2], &d_addr.sin6_addr);
	else {
		printf("usage:./command srcaddr dstaddr file repeat\n");
		exit(0);
	}
	file = fopen(argv[3], "r");
	if (!file) return 0;
	fgets(uastr, 8000, file);
	fclose(file);
	ll = strlen(uastr);
	if (uastr[ll-2] == 13)
	{
	    uastr[ll-2] = '\0';
	}
	else
	{
	    if (uastr[ll-1] == 10)
	    {
		uastr[ll - 1] = '\0';
	    }
	}
	isdnlen = str2hexstr(uastr, buff);
	

	addr_len = sizeof(d_addr);

	for (i = 0; i < atoi(argv[4]); i++)
	{
	    len = sendto(sock, buff, isdnlen, 0,
			 (struct sockaddr *) &d_addr, addr_len);
	    if (len < 0) {
		printf("\n\rsend error.\n\r");
		return 3;
	    }
	    printf("send success\n");
       usleep(1000);
	}
	return 0;
}
