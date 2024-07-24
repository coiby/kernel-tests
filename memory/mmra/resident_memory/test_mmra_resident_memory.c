#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdbool.h>

#define BUFFER_SIZE         (1UL<<20) // 1MiB
#define BUFFER_SIZE_KIB     BUFFER_SIZE / 1024
#define LINELEN             256

/**
 * utility function used to retrieve the resident size set and
 * the amount of locked KiB for a specific memory mapping
 * from /proc/self/smaps. Returns an error flag when errors arise.
 * @param desired_mapping_address used to read the desired information from the specified mapping
 * @param Rss used to return the Rss value (if found) for the specified mapping
 * @param Locked used to return the Locked value (if found) for the specified mapping
 * @param err_flag set to true if an error occurs, false otherwise.
*/
static void get_proc_smaps_info(unsigned long desired_mapping_address, unsigned long *Rss, unsigned long *Locked, bool *err_flag)
{
    bool mapping_found = false;
    bool Locked_found = false;
    bool Rss_found = false;
    char buffer[LINELEN] = "";
    FILE *fp = NULL;
    int ret = 0;

    fp = fopen("/proc/self/smaps", "r");
    if (fp == NULL) {
        perror("cannot find file proc/self/smaps\n");
        *err_flag = true;
        return;
    }

    while (fgets(buffer, LINELEN, fp) != NULL) {
        unsigned long mapping_address;

        // find the desired mapping
        ret = sscanf(buffer, "%lx[^-]", &mapping_address);
        if ((ret == 1) && (mapping_address == desired_mapping_address)) {
            mapping_found = true;
            break;
        }
    }

    if (!mapping_found) {
        fprintf(stderr, "Mapping %lx not found in /proc/self/smaps\n", desired_mapping_address);
        goto err;
    }

    while (fgets(buffer, LINELEN, fp) != NULL) {
        unsigned long possible_starting_mapping;
        unsigned long possible_ending_mapping;

        // check if the mapping section ended
        ret = sscanf(buffer, "%lx-%lx", &possible_starting_mapping, &possible_ending_mapping);
        if (ret == 2)
            break;

        // check if the current field is Rss
        if (strncmp(buffer, "Rss", strlen("Rss")) == 0) {
            ret = sscanf(buffer, "%*[^:]:%lu kB", Rss);
            if (ret != 1) {
                fprintf(stderr, "failure occurred while reading field Rss");
                goto err;
            }

            Rss_found = true;
        }

        // check if the current field is Locked
        if (strncmp(buffer, "Locked", strlen("Locked")) == 0) {
            ret = sscanf(buffer, "%*[^:]:%lu kB", Locked);
            if (ret != 1) {
                fprintf(stderr, "failure occurred while reading field Locked");
                goto err;
            }

            Locked_found =  true;
        }

        if (Rss_found && Locked_found) {
            fclose(fp);
            *err_flag = false;
            return;
        }
    }

    fprintf(stderr, "cannot find both Rss and Locked in mapping %lx", desired_mapping_address);

err:
    *err_flag = true;
    fclose(fp);
    return;
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
    unsigned long Rss = 0;
    unsigned long Locked = 0;
    bool err_flag = false;

    buff = (uint8_t*)mmap(NULL, BUFFER_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buff == MAP_FAILED) {
        perror("Memory has not been allocated");
        return false;
    }

    mlock_ret = mlock(buff, BUFFER_SIZE);
    if (mlock_ret != 0) {
        perror("cannot lock memory");
        goto err1;
    }

    get_proc_smaps_info((unsigned long)buff, &Rss, &Locked, &err_flag);
    if (err_flag)
        return false;

    // we expect the buffer to be loaded in physical memory
    if (Rss != BUFFER_SIZE_KIB) {
        fprintf(stderr, "Pre-allocation of PTEs failed: requested %lu KiB, pre-allocated %lu KiB\n", BUFFER_SIZE_KIB, Rss);
        goto err0;
    }

     // we expect the buffer to be locked in physical memory
    if (Locked != BUFFER_SIZE_KIB) {
        fprintf(stderr, "Buffer is not locked in memory: requested %lu KiB, locked %lu KiB\n", BUFFER_SIZE_KIB, Locked);
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

    printf("SUCCESS: requested %lu KiB, pre-allocated %lu KiB, locked %lu KiB\n", BUFFER_SIZE_KIB, Rss, Locked);
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

    if (ret)
        return EXIT_SUCCESS;
    return EXIT_FAILURE;
}
