#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <sys/resource.h>

#define BEHAVIOR_IGNORE 0x01
#define BEHAVIOR_CORE   0x02
#define BEHAVIOR_TERM   0x04
#define BEHAVIOR_STOP   0x08

typedef struct {
    int signum;
    char signame[10];
    char expected_action[10];
    int action_flags;
} signal_desc;

#define GET_SIGNAL_NUM(sig_name) \
    (strcmp(sig_name, "SIGABRT") == 0 ? SIGABRT : \
    (strcmp(sig_name, "SIGALRM") == 0 ? SIGALRM : \
    (strcmp(sig_name, "SIGBUS") == 0 ? SIGBUS : \
    (strcmp(sig_name, "SIGCHLD") == 0 ? SIGCHLD : \
    (strcmp(sig_name, "SIGCONT") == 0 ? SIGCONT : \
    (strcmp(sig_name, "SIGFPE") == 0 ? SIGFPE : \
    (strcmp(sig_name, "SIGHUP") == 0 ? SIGHUP : \
    (strcmp(sig_name, "SIGILL") == 0 ? SIGILL : \
    (strcmp(sig_name, "SIGINT") == 0 ? SIGINT : \
    (strcmp(sig_name, "SIGIO") == 0 ? SIGIO : \
    (strcmp(sig_name, "SIGKILL") == 0 ? SIGKILL : \
    (strcmp(sig_name, "SIGPIPE") == 0 ? SIGPIPE : \
    (strcmp(sig_name, "SIGPROF") == 0 ? SIGPROF : \
    (strcmp(sig_name, "SIGPWR") == 0 ? SIGPWR : \
    (strcmp(sig_name, "SIGQUIT") == 0 ? SIGQUIT : \
    (strcmp(sig_name, "SIGSEGV") == 0 ? SIGSEGV : \
    (strcmp(sig_name, "SIGSTKFLT") == 0 ? SIGSTKFLT : \
    (strcmp(sig_name, "SIGSTOP") == 0 ? SIGSTOP : \
    (strcmp(sig_name, "SIGTSTP") == 0 ? SIGTSTP : \
    (strcmp(sig_name, "SIGSYS") == 0 ? SIGSYS : \
    (strcmp(sig_name, "SIGTERM") == 0 ? SIGTERM : \
    (strcmp(sig_name, "SIGTRAP") == 0 ? SIGTRAP : \
    (strcmp(sig_name, "SIGTTIN") == 0 ? SIGTTIN : \
    (strcmp(sig_name, "SIGTTOU") == 0 ? SIGTTOU : \
    (strcmp(sig_name, "SIGURG") == 0 ? SIGURG : \
    (strcmp(sig_name, "SIGUSR1") == 0 ? SIGUSR1 : \
    (strcmp(sig_name, "SIGUSR2") == 0 ? SIGUSR2 : \
    (strcmp(sig_name, "SIGVTALRM") == 0 ? SIGVTALRM : \
    (strcmp(sig_name, "SIGXCPU") == 0 ? SIGXCPU : \
    (strcmp(sig_name, "SIGXFSZ") == 0 ? SIGXFSZ : \
    (strcmp(sig_name, "SIGWINCH") == 0 ? SIGWINCH : \
    -1 )))))))))))))))))))))))))))))))

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
                if (sig.action_flags & BEHAVIOR_TERM){
                    #ifdef WCOREDUMP
                    int core_dumped = !!WCOREDUMP(status);
                    if (core_dumped == !!(sig.action_flags & BEHAVIOR_CORE)){
                        passed = 1;
                    }
                    #else
                    skipped = 1;
                    #endif
                }
            }
        } else if (WIFSTOPPED(status)) {
            passed = !(sig.action_flags & BEHAVIOR_TERM) &&
                (strstr(sig.expected_action, "Stop") != NULL);
        } else if (WIFEXITED(status)) {
            passed = !(sig.action_flags & BEHAVIOR_TERM) && (sig.action_flags & BEHAVIOR_IGNORE);
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
    char input[80];
    signal_desc items[60];
    int count = 0;

    while (fgets(input, sizeof(input), stdin)){
        input[strcspn(input, "\n")] = 0;
        if (sscanf(input, "%s %s", items[count].signame, items[count].expected_action) == 2){
            if (strcmp(items[count].expected_action, "Term") == 0){
                if (strcmp(items[count].signame, "SIGKILL") == 0)
                    items[count].action_flags = BEHAVIOR_TERM;
                else
                    items[count].action_flags = BEHAVIOR_TERM | BEHAVIOR_IGNORE;
            } else if (strcmp(items[count].expected_action, "Core") == 0) {
                items[count].action_flags = BEHAVIOR_TERM | BEHAVIOR_CORE | BEHAVIOR_IGNORE;
            } else if (strcmp(items[count].expected_action, "Stop") == 0){
                if (strcmp(items[count].signame, "SIGSTOP") == 0)
                    items[count].action_flags = BEHAVIOR_STOP;
                else
                    items[count].action_flags = BEHAVIOR_STOP | BEHAVIOR_IGNORE; 
            } else if (strcmp(items[count].expected_action, "Ign") == 0){
                items[count].action_flags = BEHAVIOR_IGNORE;
            } else if (strcmp(items[count].expected_action, "Cont") == 0){
                items[count].action_flags = BEHAVIOR_IGNORE;
            } else {
                printf("Unknown action: %s", items[count].expected_action);
            }
            items[count].signum = GET_SIGNAL_NUM(items[count].signame);
            count++;
        }
    }

    for (int i = 0; i < count; i++){
        test_signal (items[i]);
    }

    printf("\n=== Results ===\n");
    printf("Passed: %d\nFailed: %d\nSkipped: %d\n", tests_passed, tests_failed, tests_skipped);
    return tests_failed ? EXIT_FAILURE : EXIT_SUCCESS;
}
