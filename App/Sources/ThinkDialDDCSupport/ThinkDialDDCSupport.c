#include "ThinkDialDDCSupport.h"

#include <CoreFoundation/CoreFoundation.h>

typedef CFTypeRef TDIOAVService;

extern int IOAVServiceReadI2C(TDIOAVService service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern int IOAVServiceWriteI2C(TDIOAVService service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

int TDWriteI2C(void *service, uint32_t chipAddress, uint32_t dataAddress, const uint8_t *bytes, uint32_t length) {
    if (service == NULL || bytes == NULL || length == 0) {
        return 1;
    }
    return IOAVServiceWriteI2C((TDIOAVService)service, chipAddress, dataAddress, (void *)bytes, length) == 0 ? 0 : 2;
}

int TDReadI2C(void *service, uint32_t chipAddress, uint32_t offset, uint8_t *bytes, uint32_t length) {
    if (service == NULL || bytes == NULL || length == 0) {
        return 1;
    }
    return IOAVServiceReadI2C((TDIOAVService)service, chipAddress, offset, bytes, length) == 0 ? 0 : 2;
}
