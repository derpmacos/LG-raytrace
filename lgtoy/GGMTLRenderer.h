@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

@interface GGMTLRenderer : NSObject<MTKViewDelegate>
- (nonnull instancetype)initWithMetalKitView:(MTKView *)mtkView;

- (void)loadCalibration:(NSDictionary*)dict;

@end

NS_ASSUME_NONNULL_END
