#ifndef THINKDIAL_DDC_SUPPORT_H
#define THINKDIAL_DDC_SUPPORT_H

#include <stdint.h>

// IOAVService is private. AppleSiliconDDC declares the same symbols for VCP read/write
// and does not expose the DDC/CI capabilities request (opcode 0xF3). These two calls
// let ThinkDial page that request on the service pointer the library already matched.
int TDWriteI2C(void *service, uint32_t chipAddress, uint32_t dataAddress, const uint8_t *bytes, uint32_t length);
int TDReadI2C(void *service, uint32_t chipAddress, uint32_t offset, uint8_t *bytes, uint32_t length);

#endif
