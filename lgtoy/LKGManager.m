//
//  LKGManager.m
//  lgtoy
//
//

#import "LKGManager.h"

#import <IOKit/hid/IOHIDLib.h>

/*
 // https://github.com/signal11/hidapi/blob/master/mac/hid.c
 static void hid_send_feature_report(IOHIDDeviceRef dev, const unsigned char *data, size_t length) {
 const IOHIDReportType type = kIOHIDReportTypeFeature;
 // set_report()
 const unsigned char *data_to_send;
 size_t length_to_send;
 if (data[0] == 0x0) { //Not using numbered Reports. Don't send the report number.
 data_to_send = data+1;
 length_to_send = length-1;
 }
 else { // Using numbered Reports. Send the Report Number
 data_to_send = data;
 length_to_send = length;
 }
 kern_return_t ret = IOHIDDeviceSetReport(dev, type, data[0], data_to_send, length_to_send);
 NSLog(@"setReport() = %08x", ret);
 
 // e0005000 = kUSBHostReturnPipeStalled;
 
 // e00002bc = kIOReturnError (generic)
 
 }
 */


static const int kHidPageSize = 64;

@implementation LKGManager {
    id<LKGManagerProtocol> _delegate;
    
    IOHIDManagerRef _manager;
    IOHIDDeviceRef _device;
    uint8_t _inputBuffer[kHidPageSize+4];
    
    uint8_t _buttons;
    
    // when loading calibration
    NSMutableData *_jsonData;
    int _page; // -1 when none
}

- (instancetype)initWithDelegate:(nonnull id<LKGManagerProtocol>)delegate {
    if((self = [super init])) {
        _delegate = delegate;
        
        // monitor for HID device
        _manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        IOHIDManagerRegisterDeviceMatchingCallback(_manager, Handle_DeviceMatchingCallback, (__bridge void*)self);
        IOHIDManagerRegisterDeviceRemovalCallback(_manager, Handle_DeviceRemovalCallback, (__bridge void*)self);
        NSDictionary *matching = @{(NSString*)CFSTR(kIOHIDVendorIDKey):@(0x04d8),
                                   (NSString*)CFSTR(kIOHIDProductIDKey):@(0xef7e)
                                   };
        IOHIDManagerSetDeviceMatching(_manager, (CFDictionaryRef)matching);
        IOHIDManagerScheduleWithRunLoop(_manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        
        // callbacks don't report if no device, so probe to detect this case immediately
        CFIndex deviceCount = 0;
        CFSetRef devices = IOHIDManagerCopyDevices(_manager);
        if(devices) {
            deviceCount = CFSetGetCount(devices);
            CFRelease(devices);
        }
        if(!_device && deviceCount == 0) {
            [_delegate LKGManager:self calibration:nil];
            [_delegate LKGManager:self buttons:0x00];
        }
        
        // monitor for the screen connect/disconnect
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screensDidChange:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
        [self screensDidChange:nil]; // initial detect
    }
    return self;
}

- (void)dealloc {
    [self setDevice:NULL];
    IOHIDManagerUnscheduleFromRunLoop(_manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    CFRelease(_manager);
    _manager = NULL;
}

static void Handle_DeviceRemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    LKGManager *dm = (__bridge LKGManager*)context;
    if([dm device] == device) [dm setDevice:NULL];
}

static void Handle_DeviceMatchingCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    LKGManager *dm = (__bridge LKGManager*)context;
    [dm setDevice:device];
}

static void Handle_DeviceReportCallback(void * context, IOReturn result, void *sender, IOHIDReportType type, uint32_t reportID, uint8_t *report, CFIndex reportLength) {
    LKGManager *dm = (__bridge LKGManager*)context;
    [dm handleReport];
}

- (void)requestPage:(int)page {
    _inputBuffer[0] = 0x00;
    _inputBuffer[1] = 0x00;
    _inputBuffer[2] = 0x00;
    _inputBuffer[3] = page;
    _page = page;
    IOHIDDeviceSetReport(_device, kIOHIDReportTypeFeature, _inputBuffer[0], _inputBuffer+1, sizeof(_inputBuffer)-1);
}

- (void)handleReport {
    if(_inputBuffer[1] == 0x00 && _inputBuffer[2] == 0x00 && _inputBuffer[3] == _page) {
        if(_page == 0) {
            const int jsonlength = (_inputBuffer[4] << 24) | (_inputBuffer[5] << 16) | (_inputBuffer[6] << 8) | _inputBuffer[7];
            _jsonData = [NSMutableData dataWithLength:jsonlength];
        }
        const int jsonLength  = (int)[_jsonData length];
        const int readOffset  = (_page==0)?4:0; // page zero has additional 4 byte header
        const int readLen     = kHidPageSize - readOffset;
        const int writeOffset = _page*kHidPageSize - (4-readOffset);
        const int writeLen    = MIN(readLen, jsonLength - writeOffset);
        [_jsonData replaceBytesInRange:NSMakeRange(writeOffset, writeLen) withBytes:_inputBuffer+4+readOffset]; // +4 to skip buffer header
        
        if(writeOffset+writeLen < jsonLength) {
            [self requestPage:_page+1];
        } else {
            _page = -1; // mark as done
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:_jsonData options:0 error:NULL];
            [_delegate LKGManager:self calibration:dict];
        }
    }
    
    const uint8_t buttons = _inputBuffer[0];
    if(buttons != _buttons) {
        _buttons = buttons;
        [_delegate LKGManager:self buttons:_buttons];
    }
}

- (IOHIDDeviceRef)device { return _device; }
- (void)setDevice:(IOHIDDeviceRef)device {
    // Assume there is only one looking glass USB device
    if(_device) {
        _buttons = 0x00;
        _jsonData = nil;
        [_delegate LKGManager:self calibration:nil];
        [_delegate LKGManager:self buttons:0x00];
        
        IOHIDDeviceClose(_device, kIOHIDOptionsTypeNone); // don't care if it fails
        CFRelease(_device);
        _device = NULL;
    }
    if(device) {
        _device = (IOHIDDeviceRef)CFRetain(device);
        if(IOHIDDeviceOpen(_device, kIOHIDOptionsTypeSeizeDevice) == kIOReturnSuccess) {
            IOHIDDeviceRegisterInputReportCallback(_device, _inputBuffer, sizeof(_inputBuffer), Handle_DeviceReportCallback, (__bridge void*)self);
            [self requestPage:0]; 
        }
    }
}

- (void)screensDidChange:(id)obj {
    // Assume there is only one looking glass screen
    NSScreen *foundScreen = nil;
    for(NSScreen *screen in [NSScreen screens]) {
        CGDirectDisplayID display = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // WTF Apple - deprecated but replaced by what??
        io_service_t service = CGDisplayIOServicePort(display);
#pragma clang diagnostic pop
        CFDictionaryRef info = IODisplayCreateInfoDictionary(service, kIODisplayOnlyPreferredName);
        if(info) {
            NSString *name = [[((__bridge NSDictionary*)info)[(NSString*)CFSTR(kDisplayProductName)] objectEnumerator] nextObject];
            if([name hasPrefix:@"LKG01"]) {
                NSLog(@"screen name = \"%@\"", name);
                foundScreen = screen;
            }
            
            CFRelease(info);
        }
        if(foundScreen) break;
    }
    
    [_delegate LKGManager:self screen:foundScreen];
    if(foundScreen && _page == -1 && _jsonData) { // in case it found the calibration BEFORE the screen
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:_jsonData options:0 error:NULL];
        [_delegate LKGManager:self calibration:dict];
    }
}

@end
