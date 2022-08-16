/***********************************************************************************************
*
* Copyright (c) 2010 Morgan Stanley & Co. Incorporated, All Rights Reserved
*
* Unpublished copyright.  All rights reserved.  This material contains
* proprietary information that shall be used or copied only within Morgan
* Stanley, except with written permission of Morgan Stanley.
*
***********************************************************************************************/

# include <stdint.h>
# include <unistd.h>
# include <sys/mman.h>
# include <sys/fcntl.h>
# include <memory.h>
# include <stdio.h>
# include <stdlib.h>
# include <dlfcn.h>
# include <sys/syscall.h>
# include <sys/types.h>
# include <sys/shm.h>

/*
 * This code provides a preinitializer for the executable it is linked into.
 * The preinitializer is run as (almost) the first thing during initialization and
 * remaps the code marked by symbols injected via a linker script to use large pages
 * via files mmapped from a hugetlbfs.
 *
 */

# define FIXME(comment)

//# if !defined __GXX_EXPERIMENTAL_CXX0X__ && !__GNUC_PREREQ(4,7)
#define decltype(x) __typeof(x)
//# endif

// The following symbols are provided by the linker script
extern "C" const uint8_t __text_hot_begin __attribute__((weakref));
extern "C" const uint8_t __text_hot_data_end __attribute__((weakref));
extern "C" const uint8_t __text_hot_end __attribute__((weakref));

// support code goes to the '.hottext_support' input section
// this will be placed outside the code that will be temporarily relocated
static void initialize_hot_text(int argc, char** argv, char** envp ) __attribute__((section(".hottext_support")));

/*
 * We try to run as early as possible -- LD_PRELOAD can't be used to achieve that.
 * Functions in .preinit_array are executed before all dependencies. Unfortunately,
 * this includes libc. So we need to be careful what we do in init.
 *
 * The linker will automatically generate the proper tags for a section called ".preinit_array"
 */
extern "C" void (* const hottext_preinitializers[])(int,char**,char**) __attribute__((section(".preinit_array"),visibility("hidden"))) =
{
    &initialize_hot_text
};

const size_t large_page_size = 2 * 1024 * 1024;

# define MERGE_TOKENS(left,right)			MERGE_TOKENS_EXPANDED(left,right) /**/
# define MERGE_TOKENS_EXPANDED(left,right)	left ## right /**/

# define STRINGIZE(pptoken)					STRINGIZE_EXPANDED(pptoken)
# define STRINGIZE_EXPANDED(pptoken)		# pptoken

/***********************************************************************************************
*
* Minimal syscall abstractions -- we're running before libc is initialized, so we need to be
* be careful with libc calls
*
* This code assumes that
*  mmap
*  mremap
*  munmap
*  write
*  abort
*
* are handled by an uninitialized libc. It would not be too hard to do the corresponding
* syscalls directly.
*
* Further
*  strlen
*  strncmp
*  memcpy
*  snprintf
*
* are assumed to be handled correctly.
*
* We specifically avoid getenv, however, because this would required an initialized libc
*
***********************************************************************************************/

/***********************************************************************************************
* Implementation
***********************************************************************************************/

# define HUGEPAGE_TEXT_ENV_VAR_NAME "HUGEPAGE_TEXT"

static void bail_with_error(const char* msg, decltype(write)* pwrite, decltype(abort)* pabort ) __attribute__((section(".hottext_support")));
static void bail_with_error(const char* msg, decltype(write)* pwrite = &write, decltype(abort)* pabort = &abort )
{
    # define ERROR_MESSAGE																	\
            "Rewrite me: "																	\
            /**/

    pwrite( STDERR_FILENO, ERROR_MESSAGE, sizeof(ERROR_MESSAGE)-sizeof("") );
    pwrite( STDERR_FILENO, msg, strlen(msg) );
    pwrite( STDERR_FILENO, "\n", 1 );
    pabort();
}

static void* resolve_symbol(const char* name) __attribute__((section(".hottext_support")));
static void* resolve_symbol(const char* name)
{
    void* func = dlsym(RTLD_DEFAULT, name);
    Dl_info shared_object;

    if (dladdr(func,&shared_object) == 0)
       bail_with_error("Failed to resolve definining module");

    const char* filename = strrchr(shared_object.dli_fname,'/');

    if (filename == NULL)
        filename = shared_object.dli_fname;
    else
        ++filename;

    const uint8_t* func_addr = static_cast<uint8_t*>(func);

    if (strcmp(filename,"libc.so.6") != 0)
    {
        // if overridden in the executable or libonload.so -- get the overridden definition and hope the best
        func = dlsym(RTLD_NEXT, name);
    }

    if (func == NULL)
        bail_with_error("Could not obtain function pointers");

    return func;
}

static void initialize_hot_text(int argc, char** argv, char** envp ) __attribute__((section(".hottext_support")));
static void initialize_hot_text(int argc, char** argv, char** envp)
{
    if (&__text_hot_begin == 0)
        return;

    // !!! CAREFUL !!!
    // we are about to unmap the executable's code
    // so get pointers to functions we can call without the need for our PLT slots
    # define CAPTURE_FUNCTION(func)												\
        decltype(func)* MERGE_TOKENS(p,func) =									\
            reinterpret_cast<decltype(func)*>(									\
                resolve_symbol( STRINGIZE(func) ) );							\
            /**/

    CAPTURE_FUNCTION(mmap);
    CAPTURE_FUNCTION(munmap);
    CAPTURE_FUNCTION(mremap);
    CAPTURE_FUNCTION(mprotect);
    CAPTURE_FUNCTION(memcpy);
    CAPTURE_FUNCTION(write);
    CAPTURE_FUNCTION(abort);
    CAPTURE_FUNCTION(open);
    CAPTURE_FUNCTION(shmat);

    const size_t envvar_name_len = sizeof(HUGEPAGE_TEXT_ENV_VAR_NAME "=") - sizeof("");

    // libc is not initalized yet -- can't use getenv
    for (;*envp != 0; ++envp)
    {
        if (strncmp(*envp,HUGEPAGE_TEXT_ENV_VAR_NAME "=",envvar_name_len) == 0)
            break;
    }

    if ( *envp == 0 )
        return;

    size_t len = &__text_hot_end - &__text_hot_begin;

    int seg_id = shmget( IPC_PRIVATE, len, SHM_HUGETLB|SHM_R|SHM_W);
    if ( seg_id == -1 )
        bail_with_error( "Failed to shmget huge pages" );

    class cleanup
    {
    public:
        explicit cleanup(int seg_id)
            : seg_id(seg_id)
        {}
        ~cleanup()
        {
            // mark our shared memory segment for deletion as soon as our process dies
            shmctl(seg_id, IPC_RMID, NULL);
        }
    private:
        cleanup( const cleanup& );
        cleanup& operator=( const cleanup& );
    private:
        int seg_id;
    } ensure_cleanup ( seg_id );

    void * placeholder = mmap( NULL
                             , len
                             , PROT_READ|PROT_EXEC
                             , MAP_ANONYMOUS | MAP_PRIVATE | MAP_NORESERVE
                             , -1 /* file descriptor */
                             , 0 /* offset */ );

    if ( placeholder == MAP_FAILED )
    {
        bail_with_error( "Could not allocate temporary mapping" );
    }

    void * new_address =
        pmremap( const_cast<uint8_t*>(&__text_hot_begin)
               , len
               , len
               , MREMAP_MAYMOVE | MREMAP_FIXED
               , placeholder );

    if ( new_address == MAP_FAILED )
        bail_with_error("Could not remap code section");

    void * old_address = pshmat( seg_id
                               , const_cast<uint8_t*>(&__text_hot_begin)
                               , 0);

    if ( old_address == MAP_FAILED )
        bail_with_error("Could not allocate new mapping",pwrite,pabort);

    // and copy over the bits
    pmemcpy( old_address, new_address, len );

    // readjust protection
    if ( pmprotect( old_address, len, PROT_READ|PROT_EXEC ) != 0 )
        bail_with_error("Could not make new mapping executable",pwrite,pabort);

    // discard the temporary section
    if ( pmunmap(new_address,len) != 0 )
        bail_with_error("Could not unmap old loader allocated text mapping");

}
