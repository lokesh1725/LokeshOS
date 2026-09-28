#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <grp.h>
#include <errno.h>

/*
 * LokeshOS helper: drop root privileges and exec.
 * Usage: runas <uid> <gid> <command> [args...]
 * Must be started with real root privileges (e.g. from /init).
 */
int main(int argc, char *argv[])
{
    uid_t uid;
    gid_t gid;
    char *end;

    if (argc < 4) {
        fprintf(stderr, "Usage: %s <uid> <gid> <command> [args...]\n", argv[0]);
        return 1;
    }

    errno = 0;
    uid = (uid_t)strtoul(argv[1], &end, 10);
    if (errno || end == argv[1] || *end != '\0') {
        fprintf(stderr, "invalid uid\n");
        return 1;
    }

    errno = 0;
    gid = (gid_t)strtoul(argv[2], &end, 10);
    if (errno || end == argv[2] || *end != '\0') {
        fprintf(stderr, "invalid gid\n");
        return 1;
    }

    /*
     * Clear supplementary groups when possible. BusyBox su fails hard on
     * initgroups/setgroups in this initramfs environment; do not abort
     * privilege drop if clearing groups is rejected.
     */
    if (setgroups(0, NULL) != 0)
        perror("setgroups");

    if (setgid(gid) != 0) {
        perror("setgid");
        return 1;
    }

    if (setuid(uid) != 0) {
        perror("setuid");
        return 1;
    }

    execvp(argv[3], &argv[3]);
    perror("execvp");
    return 1;
}
