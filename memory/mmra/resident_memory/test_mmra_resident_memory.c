#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdbool.h>

#define BUFFER_SIZE     (1UL<<20) // 1MiB
#define LINELEN         256

/**
 * utility function used to retrieve the resident size set of the current process
 * from /proc/self/status. Exit the process when errors arise.
 * @param field_name used to request a field to read
 * @param err_flag set to true if an error occurs, false otherwise.
 * @return returns the requested value. Meaningful when err_flag is set to false
 */
unsigned long get_proc_status_field(const char *field_name, bool *err_flag)
{
    char buffer[LINELEN] = "";
    int ret = 0;
    FILE* file = NULL;
    unsigned long field_value = 0;

    *err_flag = false;

    file = fopen("/proc/self/status", "r");
    if (file == NULL) {
        perror("cannot find file proc/self/status\n");
        *err_flag = true;
        return 0;
    }

    while (fgets(buffer, LINELEN, file) != NULL) {
        // find the line that contains the requested field
        if (strstr(buffer, field_name) != NULL) {

            // extract the value for the requested field
            ret = sscanf(buffer, "%*[^0-9]%lu%*[^0-9]", &field_value);
            if (ret != 1) {
                fprintf(stderr, "%s: read %s failed\n", strerror(errno), field_name);
                *err_flag = true;
            }

            fclose(file);

            // convert kB to bytes
            return field_value * 1024;
        }
    }

    // field requested could not be found
    fprintf(stderr, "cannot find field %s in /proc/pid/status\n", field_name);
    *err_flag = true;

    fclose(file);

    return 0;
}

/**
 * this function tests that mlock API pre-allocates and locks a memory allocation in physical memory.
 * this check is performed by ensuring that the VmRSS field in /proc/self/status is at least
 * as big as the allocated buffer size
 * @return true if no errors occur, false otherwise
 */
bool test_resident_memory(void)
{
    int mlock_ret = 0;
    int munlock_ret = 0;
    uint8_t* buff = NULL;
    unsigned long VmRSS_before_mlock = 0;
    unsigned long VmRSS_after_mlock = 0;
    unsigned long VmLck_before_mlock = 0;
    unsigned long VmLck_after_mlock = 0;
    bool err_flag = false;

    buff = (uint8_t*)mmap(NULL, BUFFER_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buff == MAP_FAILED) {
        perror("Memory has not been allocated");
        return false;
    }

    VmRSS_before_mlock = get_proc_status_field("VmRSS", &err_flag);
    if (err_flag){
        fprintf(stderr, "an error occured in get_proc_status_field\n");
        goto err1;
    }

    VmLck_before_mlock = get_proc_status_field("VmLck", &err_flag);
    if (err_flag){
        fprintf(stderr, "an error occured in get_proc_status_field\n");
        goto err1;
    }

    mlock_ret = mlock(buff, BUFFER_SIZE);
    if (mlock_ret != 0) {
        perror("cannot lock memory");
        goto err1;
    }

    VmRSS_after_mlock = get_proc_status_field("VmRSS", &err_flag);
    if (err_flag){
        fprintf(stderr, "an error occured in get_proc_status_field\n");
        goto err0;
    }

    VmLck_after_mlock = get_proc_status_field("VmLck", &err_flag);
    if (err_flag){
        fprintf(stderr, "an error occured in get_proc_status_field\n");
        goto err0;
    }

    // we expect the buffer to be loaded in physical memory
    if (VmRSS_after_mlock - VmRSS_before_mlock < BUFFER_SIZE) {
        fprintf(stderr, "Pre-allocation of PTEs failed\n");
        goto err0;
    }

    // we expect the buffer to be locked in physical memory
    if (VmLck_after_mlock - VmLck_before_mlock < BUFFER_SIZE) {
        fprintf(stderr, "Buffer is not locked in memory\n");
        goto err0;
    }

    munlock_ret = munlock(buff, BUFFER_SIZE);
    if (munlock_ret != 0) {
        perror("munlock failed");
        goto err1;
    }

    if (munmap(buff, BUFFER_SIZE) != 0) {
        perror("munmap failed");
        return false;
    }

    return true;

err0:
    munlock(buff, BUFFER_SIZE);
err1:
    munmap(buff, BUFFER_SIZE);
    return false;
}

int main()
{
    bool ret = false;
    ret = test_resident_memory();

    if (ret) {
        printf("Success\n");
        return EXIT_SUCCESS;
    } else {
        printf("Failure\n");
        return EXIT_FAILURE;
    }
}
