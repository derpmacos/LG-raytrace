//
//  LKGManager.h
//  lgtoy
//
//

#import <Cocoa/Cocoa.h>

@class LKGManager;

@protocol LKGManagerProtocol
- (void)LKGManager:(LKGManager*)manager screen:(NSScreen*)screen; // then calibration will be resent if it was found BEFORE the screen
- (void)LKGManager:(LKGManager*)manager calibration:(NSDictionary*)dict;
- (void)LKGManager:(LKGManager*)manager buttons:(uint8_t)buttons;
@end

@interface LKGManager : NSObject
- (instancetype)initWithDelegate:(nonnull id<LKGManagerProtocol>)delegate;
@end
