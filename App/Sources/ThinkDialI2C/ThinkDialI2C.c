#include "ThinkDialI2C.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/i2c/IOI2CInterface.h>
#include <stdlib.h>
#include <string.h>

#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

static uint32_t numberForKey(CFDictionaryRef dict, CFStringRef key) {
    if (dict == NULL || key == NULL) {
        return 0;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int32_t number = 0;
    CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &number);
    return (uint32_t)number;
}

int TDDisplayIsBuiltin(uint32_t displayID) {
    return CGDisplayIsBuiltin((CGDirectDisplayID)displayID) ? 1 : 0;
}

void TDReleaseService(uint32_t service) {
    if (service != 0) {
        IOObjectRelease((io_service_t)service);
    }
}

uint32_t TDCopyFramebuffer(uint32_t vendor, uint32_t model, uint32_t serial, uint32_t unit) {
    io_iterator_t iterator = 0;
    CFMutableDictionaryRef matching = IOServiceMatching("IOFramebuffer");
    if (matching == NULL) {
        return 0;
    }
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
        return 0;
    }

    io_service_t service = 0;
    while ((service = IOIteratorNext(iterator)) != 0) {
        CFDictionaryRef info = IODisplayCreateInfoDictionary(service, kIODisplayOnlyPreferredName);
        if (info == NULL) {
            IOObjectRelease(service);
            continue;
        }
        uint32_t portVendor = numberForKey(info, CFSTR(kDisplayVendorID));
        uint32_t portModel = numberForKey(info, CFSTR(kDisplayProductID));
        uint32_t portSerial = numberForKey(info, CFSTR(kDisplaySerialNumber));
        int matches = portVendor == vendor && portModel == model && portSerial == serial;
        CFTypeRef locationValue = CFDictionaryGetValue(info, CFSTR(kIODisplayLocationKey));
        if (matches && locationValue != NULL && CFGetTypeID(locationValue) == CFStringGetTypeID()) {
            char location[256];
            if (CFStringGetCString((CFStringRef)locationValue, location, (CFIndex)sizeof(location), kCFStringEncodingUTF8)) {
                char *at = strrchr(location, '@');
                if (at != NULL && at[1] >= '0' && at[1] <= '9') {
                    unsigned long parsed = strtoul(at + 1, NULL, 10);
                    if ((uint32_t)parsed != unit) {
                        matches = 0;
                    }
                }
            }
        }
        IOItemCount buses = 0;
        int hasBus = matches && IOFBGetI2CInterfaceCount(service, &buses) == KERN_SUCCESS && buses > 0;
        CFRelease(info);
        if (hasBus) {
            IOObjectRelease(iterator);
            return (uint32_t)service;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return 0;
}

int TDCopyProductName(uint32_t framebuffer, char *buffer, int capacity) {
    if (buffer == NULL || capacity <= 0 || framebuffer == 0) {
        return 0;
    }
    buffer[0] = 0;
    CFDictionaryRef info = IODisplayCreateInfoDictionary((io_service_t)framebuffer, kIODisplayOnlyPreferredName);
    if (info == NULL) {
        return 0;
    }
    int ok = 0;
    CFTypeRef namesValue = CFDictionaryGetValue(info, CFSTR("DisplayProductName"));
    if (namesValue != NULL && CFGetTypeID(namesValue) == CFDictionaryGetTypeID()) {
        CFDictionaryRef names = (CFDictionaryRef)namesValue;
        CFTypeRef englishValue = CFDictionaryGetValue(names, CFSTR("en_US"));
        if (englishValue == NULL || CFGetTypeID(englishValue) != CFStringGetTypeID()) {
            CFIndex count = CFDictionaryGetCount(names);
            if (count > 0 && count <= 16) {
                const void *values[16] = {0};
                CFDictionaryGetKeysAndValues(names, NULL, values);
                if (values[0] != NULL && CFGetTypeID(values[0]) == CFStringGetTypeID()) {
                    englishValue = values[0];
                }
            }
        }
        if (englishValue != NULL && CFGetTypeID(englishValue) == CFStringGetTypeID()) {
            ok = CFStringGetCString((CFStringRef)englishValue, buffer, (CFIndex)capacity, kCFStringEncodingUTF8) ? 1 : 0;
        }
    }
    CFRelease(info);
    return ok;
}

int TDFramebufferDDC(uint32_t framebuffer, const uint8_t *send, uint32_t sendLength, uint8_t *reply, uint32_t replyLength) {
    if (framebuffer == 0 || send == NULL || sendLength == 0) {
        return 1;
    }
    if (replyLength > 0 && reply == NULL) {
        return 1;
    }
    IOItemCount busCount = 0;
    if (IOFBGetI2CInterfaceCount((io_service_t)framebuffer, &busCount) != KERN_SUCCESS || busCount == 0) {
        return 2;
    }
    for (IOItemCount bus = 0; bus < busCount; bus++) {
        io_service_t interface = 0;
        if (IOFBCopyI2CInterfaceForBus((io_service_t)framebuffer, (IOOptionBits)bus, &interface) != KERN_SUCCESS || interface == 0) {
            continue;
        }
        IOI2CConnectRef connect = NULL;
        if (IOI2CInterfaceOpen(interface, kNilOptions, &connect) != KERN_SUCCESS || connect == NULL) {
            IOObjectRelease(interface);
            continue;
        }

        IOI2CRequest request;
        memset(&request, 0, sizeof(request));
        request.sendAddress = 0x6E;
        request.sendTransactionType = kIOI2CSimpleTransactionType;
        request.sendBuffer = (vm_address_t)(uintptr_t)send;
        request.sendBytes = sendLength;
        request.minReplyDelay = 10;
        if (replyLength == 0) {
            request.replyTransactionType = kIOI2CNoTransactionType;
            request.replyBytes = 0;
        } else {
            request.replyAddress = 0x6F;
            request.replySubAddress = 0x51;
            request.replyTransactionType = kIOI2CDDCciReplyTransactionType;
            request.replyBuffer = (vm_address_t)(uintptr_t)reply;
            request.replyBytes = replyLength;
        }

        IOReturn result = IOI2CSendRequest(connect, kNilOptions, &request);
        int ok = result == kIOReturnSuccess && request.result == kIOReturnSuccess;
        IOI2CInterfaceClose(connect, kNilOptions);
        IOObjectRelease(interface);
        if (ok) {
            return 0;
        }
    }
    return 3;
}
