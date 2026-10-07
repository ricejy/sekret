#pragma once
#include <stdbool.h>
#include <stdint.h>
void sekret_reset_cancel(void);
void sekret_request_cancel(void);
bool sekret_cancelled(void * ignored);
uint64_t sekret_footprint_bytes(void);
uint64_t sekret_peak_rss_bytes(void);
uint64_t sekret_available_memory_bytes(void);
