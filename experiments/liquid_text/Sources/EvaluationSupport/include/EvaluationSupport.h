#pragma once
#include <stdbool.h>
#include <stdint.h>

// Single-process, single-generation evaluation support; not an app adapter.
void evaluation_install_signal_handler(void);
void evaluation_reset_cancel(void);
void evaluation_request_cancel(void);
bool evaluation_cancelled(void * ignored);
uint64_t evaluation_footprint_bytes(void);
uint64_t evaluation_peak_rss_bytes(void);
