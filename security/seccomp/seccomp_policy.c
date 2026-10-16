/*
 * LokeshOS production seccomp policy.
 *
 * Allowlist model (fail closed):
 *   - Default action for every syscall is SCMP_ACT_ERRNO(EPERM).
 *   - Only the syscalls listed below are explicitly allowed.
 *   - The policy is loaded, then the target program is exec'd.
 *
 * The allowlist was derived from the syscall traces in this directory
 * (sandbox-syscalls.log, python-syscalls.log) and the sandboxed
 * security test application (security/sandbox/apps/test_app.py).
 *
 * NOTE: getpid() is intentionally ALLOWED here. Python's runtime calls
 * getpid/getppid during interpreter start-up, so denying it prevents the
 * sandboxed app from running at all. The separate seccomp_launcher binary
 * (see getpid_test) demonstrates and verifies that denying getpid() works.
 * A locked-down per-application profile may deny it once an application
 * does not require it.
 *
 * Usage: seccomp_policy <program> [args...]
 */

#include <seccomp.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

static void allow(scmp_filter_ctx ctx, int syscall)
{
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall, 0) < 0)
        fprintf(stderr, "seccomp_policy: warning: could not allow syscall %d\n",
                syscall);
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <program> [args...]\n", argv[0]);
        return 1;
    }

    /* Fail closed: anything not explicitly allowed returns EPERM. */
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ERRNO(EPERM));
    if (ctx == NULL) {
        fprintf(stderr, "seccomp_policy: seccomp_init failed\n");
        return 1;
    }

    /* --- Basic process / memory runtime ------------------------------- */
    allow(ctx, SCMP_SYS(arch_prctl));
    allow(ctx, SCMP_SYS(brk));
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mprotect), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(munmap), 0);
    allow(ctx, SCMP_SYS(rseq));
    allow(ctx, SCMP_SYS(set_robust_list));
    allow(ctx, SCMP_SYS(set_tid_address));

    /* Execution and process lifecycle. */
    allow(ctx, SCMP_SYS(execve));
    allow(ctx, SCMP_SYS(exit_group));
    allow(ctx, SCMP_SYS(vfork));
    allow(ctx, SCMP_SYS(wait4));
    allow(ctx, SCMP_SYS(prlimit64));

    /* Synchronization. */
    allow(ctx, SCMP_SYS(futex));

    /* Filesystem. */
    allow(ctx, SCMP_SYS(access));
    allow(ctx, SCMP_SYS(faccessat));
    allow(ctx, SCMP_SYS(fstat));
    allow(ctx, SCMP_SYS(getcwd));
    allow(ctx, SCMP_SYS(getdents64));
    allow(ctx, SCMP_SYS(mkdir));
    allow(ctx, SCMP_SYS(newfstatat));
    allow(ctx, SCMP_SYS(open));
    allow(ctx, SCMP_SYS(openat));
    allow(ctx, SCMP_SYS(pread64));
    allow(ctx, SCMP_SYS(read));
    allow(ctx, SCMP_SYS(readlink));
    allow(ctx, SCMP_SYS(readlinkat));
    allow(ctx, SCMP_SYS(statx));

    /* I/O. */
    allow(ctx, SCMP_SYS(close));
    allow(ctx, SCMP_SYS(fcntl));
    allow(ctx, SCMP_SYS(ioctl));
    allow(ctx, SCMP_SYS(lseek));
    allow(ctx, SCMP_SYS(poll));
    allow(ctx, SCMP_SYS(write));
    allow(ctx, SCMP_SYS(writev));

    /* Process identity / randomness. */
    allow(ctx, SCMP_SYS(getegid));
    allow(ctx, SCMP_SYS(geteuid));
    allow(ctx, SCMP_SYS(getgid));
    allow(ctx, SCMP_SYS(getgroups));
    allow(ctx, SCMP_SYS(getpid));
    allow(ctx, SCMP_SYS(getppid));
    allow(ctx, SCMP_SYS(getrandom));
    allow(ctx, SCMP_SYS(gettid));
    allow(ctx, SCMP_SYS(getuid));
    allow(ctx, SCMP_SYS(uname));

    /* Signal handling. */
    allow(ctx, SCMP_SYS(rt_sigaction));
    allow(ctx, SCMP_SYS(rt_sigprocmask));
    allow(ctx, SCMP_SYS(rt_sigreturn));
    allow(ctx, SCMP_SYS(sigaltstack));

    /* CPU / scheduler information. */
    allow(ctx, SCMP_SYS(sched_getaffinity));

    /* Process termination / error handling. */
    allow(ctx, SCMP_SYS(tgkill));

    if (seccomp_load(ctx) != 0) {
        fprintf(stderr, "seccomp_policy: seccomp_load failed\n");
        seccomp_release(ctx);
        return 1;
    }

    seccomp_release(ctx);

    execvp(argv[1], &argv[1]);

    /* execvp() only returns on failure. */
    perror("execvp");
    return 1;
}
