#define _GNU_SOURCE
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(void)
{
    long ret;

    /* Direct getpid syscall (nr 39): deterministically enters the
       kernel so the seccomp filter rule is actually exercised,
       bypassing any libc PID caching. */
    errno = 0;
    ret = syscall(SYS_getpid);

    printf("getpid: return=%ld errno=%d\n", ret, errno);

    if (ret == -1 && errno == EPERM) {
        printf("getpid blocked\n");
        printf("errno = EPERM\n");
        printf("RESULT: PASS\n");
        return 0;
    }

    printf("getpid NOT blocked\n");
    printf("RESULT: FAIL\n");
    return 1;
}
