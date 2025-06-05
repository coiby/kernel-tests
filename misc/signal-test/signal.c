#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <sys/resource.h>

typedef struct {
    int signum;
    const char *signame;
    const char *expected_action;
    int should_terminate;
    int should_core;
    int should_stop;
    int can_be_ignored;
} signal_desc;

signal_desc test_cases[] = {
    {SIGHUP,    "SIGHUP",    "Term",         1, 0, 0, 1},
    {SIGINT,    "SIGINT",    "Term",         1, 0, 0, 1},
    {SIGQUIT,   "SIGQUIT",   "Core",         1, 1, 0, 1},
    {SIGILL,    "SIGILL",    "Core",         1, 1, 0, 1},
    {SIGTRAP,   "SIGTRAP",   "Core",         1, 1, 0, 1},
    {SIGABRT,   "SIGABRT",   "Core",         1, 1, 0, 1},
    {SIGBUS,    "SIGBUS",    "Core",         1, 1, 0, 1},
    {SIGFPE,    "SIGFPE",    "Core",         1, 1, 0, 1},
    {SIGKILL,   "SIGKILL",   "Term",         1, 0, 0, 0},
    {SIGUSR1,   "SIGUSR1",   "Term",         1, 0, 0, 1},
    {SIGSEGV,   "SIGSEGV",   "Core",         1, 1, 0, 1},
    {SIGUSR2,   "SIGUSR2",   "Term",         1, 0, 0, 1},
    {SIGPIPE,   "SIGPIPE",   "Term",         1, 0, 0, 1},
    {SIGALRM,   "SIGALRM",   "Term",         1, 0, 0, 1},
    {SIGTERM,   "SIGTERM",   "Term",         1, 0, 0, 1},
    {SIGSTKFLT, "SIGSTKFLT", "Term",         1, 0, 0, 1},
    {SIGCHLD,   "SIGCHLD",   "Ign",          0, 0, 0, 1},
    {SIGCONT,   "SIGCONT",   "Cont",         0, 0, 0, 1},
    {SIGSTOP,   "SIGSTOP",   "Stop",         0, 0, 1, 0},
    {SIGTSTP,   "SIGTSTP",   "Stop",         0, 0, 1, 1},
    {SIGTTIN,   "SIGTTIN",   "Stop",         0, 0, 1, 1},
    {SIGTTOU,   "SIGTTOU",   "Stop",         0, 0, 1, 1},
    {SIGURG,    "SIGURG",    "Ign",          0, 0, 0, 1},
    {SIGXCPU,   "SIGXCPU",   "Core",         1, 1, 0, 1},
    {SIGXFSZ,   "SIGXFSZ",   "Core",         1, 1, 0, 1},
    {SIGVTALRM, "SIGVTALRM", "Term",         1, 0, 0, 1},
    {SIGPROF,   "SIGPROF",   "Term",         1, 0, 0, 1},
    {SIGWINCH,  "SIGWINCH",  "Ign",          0, 0, 0, 1},
    {SIGIO,     "SIGIO",     "Term",         1, 0, 0, 1},
    {SIGPWR,    "SIGPWR",    "Term",         1, 0, 0, 1},
    {SIGSYS,    "SIGSYS",    "Core",         1, 1, 0, 1},
    {0, NULL, NULL, 0, 0, 0, 0}
};

int tests_passed = 0;
int tests_failed = 0;
int tests_skipped = 0;

void test_signal(signal_desc sig){
    pid_t pid;
    int status;

    printf("Testing %-10s (%2d): Expected %-10s ",
           sig.signame, sig.signum, sig.expected_action);
    fflush(stdout);
    
    pid = fork();
    if (pid == -1){
        perror("fork failed, failing the test");
        exit(1);
    } 

    if (pid == 0){
        /* child */
        sleep(1);
        raise(sig.signum);
        sleep(1);
        exit(0);
    } else {
        /* parent */
        int passed = 0;
        int skipped = 0;
        int options = WUNTRACED | WCONTINUED;
        waitpid(pid, &status, options);
    
        if (WIFSIGNALED(status)) {
            int term_sig = WTERMSIG(status);
            if (term_sig == sig.signum) {
                if (sig.should_terminate){
                    #ifdef WCOREDUMP
                    int core_dumped = !!WCOREDUMP(status);
                    if (core_dumped == sig.should_core){
                        passed = 1;
                    }
                    #else
                    skipped = 1;
                    #endif
                }
            }
        } else if (WIFSTOPPED(status)) {
            passed = !sig.should_terminate && 
                (strstr(sig.expected_action, "Stop") != NULL);
        } else if (WIFEXITED(status)) {
            passed = !sig.should_terminate && sig.can_be_ignored;
        }

        if (skipped) {
            printf("[SKIP] Core dump check not available\n");
            tests_skipped++;
        } else if (passed) {
            printf("[PASS]\n");
            tests_passed++;
        } else {
            printf("[FAIL] ");
            if (WIFSIGNALED(status)) {
                printf("Term by sig %d", WTERMSIG(status));
                #ifdef WCOREDUMP
                printf(" (core=%d)", WCOREDUMP(status));
                #endif
            } else if (WIFSTOPPED(status)) {
                printf("Stopped by sig %d", WSTOPSIG(status));
            } else {
                printf("Exit status %d", WEXITSTATUS(status));
            }
            printf("\n");
            tests_failed++;
        }
    }
}

int main() {
    for (int i = 0; test_cases[i].signame != NULL; i++){
        test_signal (test_cases[i]);
    }
    printf("\n=== Results ===\n");
    printf("Passed: %d\nFailed: %d\nSkipped: %d\n", tests_passed, tests_failed, tests_skipped);
    return tests_failed ? EXIT_FAILURE : EXIT_SUCCESS;
}
