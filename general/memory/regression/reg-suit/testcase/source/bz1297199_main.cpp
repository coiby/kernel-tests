# include <stdio.h>
# include <stdlib.h>
# include <unistd.h>
# include <sys/mman.h>

int main()
{
    puts("In main\n");
    /*  getchar();
        int ret = mlockall(MCL_CURRENT | MCL_FUTURE);
        printf("mlockall(MCL_CURRENT | MCL_FUTURE) returns %i\n", ret);
        getchar();
        puts("Fork & Exec\n");
        system("uname -a");
        getchar();
        puts("Done\n");
        */
    return 0;
}
