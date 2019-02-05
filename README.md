# LookingGlass raytracing

Require macos 10.14 and a Looking Glass screen (https://lookingglassfactory.com)

This contains a macos native code (LKGManager) for interfacing with the Looking Glass Display 
In particular this deals with:
- Hotplug detection of the screen.
- Hotplug detection of the USB HID device (i.e. calibration info)

Furthermore this code demonstrates how to set up a Metal renderer.

## Approach

Rather than rendering some 45 distinct views, this code instead raytraces the scene based on the angle of the particular (sub)pixel, for every pixel.  This may or may not be more performant based on the nature of the scene that is being rendered.

Note that the "maths" for the exact angle calculation is done by tweaking until it felt about right (in terms of fov and position), so this could certainly be improved based on the Looking Glass documentation.

The ShaderToy (https://www.shadertoy.com) approach of rendering a fullscreen quad is used (though in this case we use Metal rather than Open/WebGL).

In this example we port a Metalized version of the code from https://www.shadertoy.com/view/XsjXRm, that is: Plasma Globe by nimitz (twitter: @stormoid), 2014.

## Maths

Some differences to the unity SDK shader code are:
- we pass the calibration as 4 terms (a,b,c,d), so that the angle code is fract(a.x * a.y + c + i.d), where i is the subpixel 0/1/2 (see AAPLShaders.metal).
- we do the calculation in screen coords rather than in normalized coords.
- h-flip and v-flip issues are handled by suitably massaging the above parameters rather than adding more complexity to the shader. (see GGMTLRenderer.m) In addition we ensure the numbers are in a suitably 'nice' +ve range.

