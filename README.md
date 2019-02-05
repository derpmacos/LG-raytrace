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

In this example we reuse the code from https://www.shadertoy.com/view/XsjXRm 
- 2014: Plasma Globe by nimitz (twitter: @stormoid)



