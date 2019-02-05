/*
Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/

#ifndef AAPLShaderTypes_h
#define AAPLShaderTypes_h

#include <simd/simd.h>

typedef enum {
    QuiltFragmentInputIndexUniforms = 0
} QuiltFragmentInputIndex;

typedef struct {
    vector_float4 calib;
    vector_float2 size;
    float time;
} QuiltFragmentUniforms;


#endif /* AAPLShaderTypes_h */
