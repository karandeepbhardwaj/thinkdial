#ifndef THINKDIAL_I2C_H
#define THINKDIAL_I2C_H

#include <stdint.h>

// Framebuffer I2C for the Intel fallback. IOI2CRequest stays in this C file so Swift
// never depends on the imported struct layout. Apple Silicon does not use these calls;
// it uses AppleSiliconDDC's public get/set VCP API.

uint32_t TDCopyFramebuffer(uint32_t vendor, uint32_t model, uint32_t serial, uint32_t unit);
void TDReleaseService(uint32_t service);
int TDCopyProductName(uint32_t framebuffer, char *buffer, int capacity);
int TDDisplayIsBuiltin(uint32_t displayID);

// 0 on success. reply may be NULL when replyLength is 0 (a write).
int TDFramebufferDDC(uint32_t framebuffer, const uint8_t *send, uint32_t sendLength, uint8_t *reply, uint32_t replyLength);

#endif
