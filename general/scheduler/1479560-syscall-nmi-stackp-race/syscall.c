#include <unistd.h>
#include <stdio.h>

int main()
{
	while (1) syscall(400);
	return 0;
}
