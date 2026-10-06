#include "EvaluationSupport.h"
#include <mach/mach.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/resource.h>
#include <os/proc.h>
#include <TargetConditionals.h>

uint64_t evaluation_available_memory_bytes(void) {
#if TARGET_OS_IOS
    return os_proc_available_memory();
#else
    return 0; // Unknown on macOS; admission guard is iOS-harness-only.
#endif
}

static volatile sig_atomic_t signal_cancelled = 0;
static atomic_bool requested_cancel = false;
static void on_signal(int value) { (void)value; signal_cancelled = 1; }
void evaluation_install_signal_handler(void) { signal(SIGINT, on_signal); }
void evaluation_reset_cancel(void) {
    signal_cancelled = 0;
    atomic_store(&requested_cancel, false);
}
void evaluation_request_cancel(void) { atomic_store(&requested_cancel, true); }
bool evaluation_cancelled(void * ignored) {
    (void)ignored;
    return signal_cancelled != 0 || atomic_load(&requested_cancel);
}

uint64_t evaluation_footprint_bytes(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO,
        (task_info_t)&info, &count);
    return result == KERN_SUCCESS ? info.phys_footprint : 0;
}

uint64_t evaluation_peak_rss_bytes(void) {
    struct rusage usage;
    return getrusage(RUSAGE_SELF, &usage) == 0 ? (uint64_t)usage.ru_maxrss : 0;
}
