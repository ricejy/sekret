#include "RuntimeSupport.h"
#include <mach/mach.h>
#include <stdatomic.h>
#include <sys/resource.h>
#include <os/proc.h>
#include <TargetConditionals.h>

// One native operation at a time. Cancellation is safe from the main thread
// while llama.cpp is decoding on its serial worker, including Metal aborts.
static atomic_bool requested_cancel = false;
void sekret_reset_cancel(void) { atomic_store(&requested_cancel, false); }
void sekret_request_cancel(void) { atomic_store(&requested_cancel, true); }
bool sekret_cancelled(void * ignored) {
    (void)ignored;
    return atomic_load(&requested_cancel);
}
uint64_t sekret_available_memory_bytes(void) {
#if TARGET_OS_IOS
    return os_proc_available_memory();
#else
    return 0;
#endif
}
uint64_t sekret_footprint_bytes(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO,
        (task_info_t)&info, &count);
    return result == KERN_SUCCESS ? info.phys_footprint : 0;
}
uint64_t sekret_peak_rss_bytes(void) {
    struct rusage usage;
    return getrusage(RUSAGE_SELF, &usage) == 0 ? (uint64_t)usage.ru_maxrss : 0;
}
