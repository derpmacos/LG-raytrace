
@import simd;
@import MetalKit;

#import "GGMTLRenderer.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
#import "AAPLShaderTypes.h"

// Main class performing the rendering
@implementation GGMTLRenderer
{
    // The device (aka GPU) we're using to render
    id<MTLDevice> _device;
    
    // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
    id<MTLRenderPipelineState> _pipelineState;
    
    // The command Queue from which we'll obtain command buffers
    id<MTLCommandQueue> _commandQueue;
    
    QuiltFragmentUniforms _uniforms;
    
    NSDate *_startTime;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView {
    if((self = [super init])) {
        _device = mtkView.device;
        
        NSLog(@"Metal: %@ (%s%s)", [_device name], ([_device isRemovable]?"external":([_device isLowPower]?"intergrated":"discrete")), ([_device isHeadless]?"headless":""));
        NSLog(@"Metal: Working size: %dMB", (int)([_device recommendedMaxWorkingSetSize]>>20));
        
        /// Create our render pipeline
        
        // Load all the shader files with a .metal file extension in the project
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        
        // Load the vertex function from the library
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        
        // Load the fragment function from the library
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];
        
        // Set up a descriptor for creating a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        
        NSError *error = NULL;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if (!_pipelineState) {
            // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
            //  If the Metal API validation is enabled, we can find out more information about what
            //  went wrong.  (Metal API validation is enabled by default when a debug build is run
            //  from Xcode)
            NSLog(@"Failed to created pipeline state, error %@", error);
        }
        
        // Create the command queue
        _commandQueue = [_device newCommandQueue];
        _commandQueue.label = @"quilter";
        
        _startTime = [NSDate date];
    }
    
    return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    _uniforms.size = vector2((float)size.width, (float)size.height);
}

- (void)loadCalibration:(NSDictionary*)dict {
    int screenW = [dict[@"screenW"][@"value"] intValue];
    int screenH = [dict[@"screenH"][@"value"] intValue];
    
    double DPI = [dict[@"DPI"][@"value"] floatValue];
    double size = sqrtf(screenW*screenW + screenH*screenH)/DPI; // diagonal size
    NSString *serial = dict[@"serial"];
    
    double center =  [dict[@"center"][@"value"] floatValue];
    double pitch =  [dict[@"pitch"][@"value"] floatValue];
    double slope =  [dict[@"slope"][@"value"] doubleValue];
    
    NSLog(@"screen size = %g\"", size);
    NSLog(@"serial = \"%@\"", serial);
    NSLog(@"Raw: %dx%d, dpi=%g, center = %g, pitch = %g, slope = %g", screenW, screenH, DPI, center, pitch, slope);
    
    double tilt = 1.0/slope;
    double pix = pitch/(DPI*sqrt(1+tilt*tilt));
    
    /*
    // old style:
    _uniforms.center = center;    // normalized forms are:
    _uniforms.pitch  = pix;       //  /screenW
    _uniforms.tilt   = tilt;      //  *screenW/screenH
    _uniforms.subp   = pix/3.0;   //  /screenW
    //float a = (uv.x + uv.y*uniforms.tilt)*uniforms.pitch - uniforms.center; // unlike the sdk we do it in pixel coords rather than in normalised
    */
    
    BOOL vflip = YES;
    BOOL hflip = NO;
    
    float a = pix;
    float b = pix*tilt;
    float c = -center;
    float d = pix/3.0; // subp
    // float a = x*a + y*b + c
    
    if(vflip) { // i.e. y = (h-y)
        c += b*screenH;
        b = -b;
    }
    if(hflip) { // i.e. x = (w-x)
        c += a*screenW;
        a = -a;
        d = -d;
    }
    
    // adjust c to ensure the smallest is +ve and in the range 0..1
    int x = (a<0)?screenW:0;
    int y = (b<0)?screenH:0;
    float smallest = a*x + b*y + c;
    if(smallest < 0) {
        c += 1+floor(-smallest);
    } else if(smallest > 1) {
        c -= floor(smallest);
    }
    
    // recalc to show result
    smallest = a*x + b*y + c;
    float largest  = a*(screenW-x) + b*(screenH-y) + c;
    NSLog(@"calib=%g*x + %g*y + %g => range=%g..%g", a, b, c, smallest, largest);
    
    _uniforms.calib = vector4(a, b, c, d);
    
    
    if(_uniforms.size.x != screenW || _uniforms.size.y != screenH) {
        NSLog(@"WARNING: screen using wrong resolution");
    }
}


/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view {
    
    // update uniforms
    _uniforms.time = -[_startTime timeIntervalSinceNow];
    

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if(renderPassDescriptor != nil) {
        renderPassDescriptor.colorAttachments[0].loadAction  = MTLLoadActionDontCare; // drawing a fullscreen quad
        renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _uniforms.size.x, _uniforms.size.y, -1.0, 1.0 }];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setFragmentBytes:&_uniforms length:sizeof(QuiltFragmentUniforms) atIndex:QuiltFragmentInputIndexUniforms];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [renderEncoder endEncoding];
        
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit];
}

@end
