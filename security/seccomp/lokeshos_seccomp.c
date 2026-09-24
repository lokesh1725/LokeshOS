#include <seccomp.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <program> [args...]\n", argv[0]);
        return 1;
    }

    scmp_filter_ctx ctx;

    /*
     * Start with a filter that allows system calls.
     */
    ctx = seccomp_init(SCMP_ACT_ALLOW);

    if (ctx == NULL) {
        fprintf(stderr, "seccomp_init failed\n");
        return 1;
    }

    /*
     * Test restriction:
     * Block getpid() with EPERM.
     */
    if (seccomp_rule_add(
            ctx,
            SCMP_ACT_ERRNO(EPERM),
            SCMP_SYS(getpid),
            0) != 0) {

        fprintf(stderr, "Failed to add getpid rule\n");
        seccomp_release(ctx);
        return 1;
    }

    /*
     * Load the seccomp filter into the kernel.
     */
    if (seccomp_load(ctx) != 0) {
        fprintf(stderr, "seccomp_load failed\n");
        seccomp_release(ctx);
        return 1;
    }

    seccomp_release(ctx);

    /*
     * Execute the requested application.
     */
    execvp(argv[1], &argv[1]);

    perror("execvp");
    return 1;
}
