/* Copyright (c) 2018 PaddlePaddle Authors. All Rights Reserved.
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License. */

#include <metal_stdlib>
#include "Common.metal"
using namespace metal;

// conv
#pragma mark -- conv
kernel void conv_3x3(texture2d_array<float, access::sample> inTexture [[texture(0)]],
                     texture2d_array<float, access::write> outTexture [[texture(1)]],
                     constant MetalConvParam &param [[buffer(0)]],
                     const device float4 *weights [[buffer(1)]],
                     uint3 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() ||
        gid.y >= outTexture.get_height() ||
        gid.z >= outTexture.get_array_size()) {
        return;
    }
    
    ushort2 stride = ushort2(param.strideX, param.strideY);
    const ushort2 posInInput = ushort2(gid.xy) * stride + ushort2(param.offsetX, param.offsetY);
    
    constexpr sampler sample(coord::pixel, filter::nearest, address::clamp_to_zero);
    const uint kernelHXW = 9;
    uint input_arr_size = inTexture.get_array_size();
    uint weithTo = gid.z * kernelHXW * input_arr_size * 4;
    
    float4 output = float4(0.0);
    
    float4 input[9];
    for (uint i = 0; i < input_arr_size; ++i) {
        input[0] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y - 1), i);
        input[1] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y - 1), i);
        input[2] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y - 1), i);
        input[3] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y), i);
        input[4] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y), i);
        input[5] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y), i);
        input[6] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y + 1), i);
        input[7] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y + 1), i);
        input[8] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y + 1), i);
        for (int j = 0; j < 9; ++j) {
            float4 weight_x = weights[weithTo + 0 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.x += dot(input[j], weight_x);
            
            float4 weight_y = weights[weithTo + 1 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.y += dot(input[j], weight_y);
            
            float4 weight_z = weights[weithTo + 2 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.z += dot(input[j], weight_z);
            
            float4 weight_w = weights[weithTo + 3 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.w += dot(input[j], weight_w);
        }
    }
    outTexture.write(output, gid.xy, gid.z);
}

kernel void depthwise_conv_3x3(texture2d_array<float, access::sample> inTexture [[texture(0)]],
                               texture2d_array<float, access::write> outTexture [[texture(1)]],
                               constant MetalConvParam &param [[buffer(0)]],
                               const device float *weights [[buffer(1)]],
                               uint3 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() ||
        gid.y >= outTexture.get_height() ||
        gid.z >= outTexture.get_array_size()) {
        return;
    }
    uint output_slice = gid.z;
    ushort2 stride = ushort2(param.strideX, param.strideY);
    ushort2 posInInput = ushort2(gid.xy) * stride + ushort2(param.offsetX, param.offsetY);
    constexpr sampler sample(coord::pixel, filter::nearest, address::clamp_to_zero);
    const uint kernelHXW = 9;
    uint weithTo = gid.z * kernelHXW * 4;
    float4 output = float4(0.0);
    float4 inputs[9];
    inputs[0] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y - 1), output_slice);
    inputs[1] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y - 1), output_slice);
    inputs[2] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y - 1), output_slice);
    inputs[3] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y), output_slice);
    inputs[4] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y), output_slice);
    inputs[5] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y), output_slice);
    inputs[6] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y + 1), output_slice);
    inputs[7] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y + 1), output_slice);
    inputs[8] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y + 1), output_slice);
    for (int j = 0; j < 9; ++j) {
        float4 input = inputs[j];
        output.x += input.x * weights[weithTo + 0 * kernelHXW + j];
        output.y += input.y * weights[weithTo + 1 * kernelHXW + j];
        output.z += input.z * weights[weithTo + 2 * kernelHXW + j];
        output.w += input.w * weights[weithTo + 3 * kernelHXW + j];
    }
    outTexture.write(output, gid.xy, gid.z);
}

kernel void conv_1x1(texture2d_array<float, access::sample> inTexture [[texture(0)]],
                     texture2d_array<float, access::write> outTexture [[texture(1)]],
                     constant MetalConvParam &param [[buffer(0)]],
                     const device float4 *weights [[buffer(1)]],
                     uint3 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() ||
        gid.y >= outTexture.get_height() ||
        gid.z >= outTexture.get_array_size()) {
        return;
    }
    
    ushort2 stride = ushort2(param.strideX, param.strideY);
    ushort2 posInInput = ushort2(gid.xy) * stride + ushort2(param.offsetX, param.offsetY);
    
    constexpr sampler sample(coord::pixel, filter::nearest, address::clamp_to_zero);
    const uint kernelHXW = 1;
    
    uint input_arr_size = inTexture.get_array_size();
    uint weithTo = gid.z * kernelHXW * input_arr_size * 4;
    
    float4 output = float4(0.0);
    
    float4 input;
    for (uint i = 0; i < input_arr_size; ++i) {
        input = inTexture.sample(sample, float2(posInInput.x, posInInput.y), i);
        float4 weight_x = weights[weithTo + 0 * kernelHXW * input_arr_size  + i];
        output.x += dot(input, weight_x);
        
        float4 weight_y = weights[weithTo + 1 * kernelHXW * input_arr_size  + i];
        output.y += dot(input, weight_y);
        
        float4 weight_z = weights[weithTo + 2 * kernelHXW * input_arr_size  + i];
        output.z += dot(input, weight_z);
        
        float4 weight_w = weights[weithTo + 3 * kernelHXW * input_arr_size + i];
        output.w += dot(input, weight_w);
    }
    outTexture.write(output, gid.xy, gid.z);
}


kernel void conv_3x3_half(texture2d_array<half, access::sample> inTexture [[texture(0)]],
                          texture2d_array<half, access::write> outTexture [[texture(1)]],
                          constant MetalConvParam &param [[buffer(0)]],
                          const device half4 *weights [[buffer(1)]],
                          uint3 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() ||
        gid.y >= outTexture.get_height() ||
        gid.z >= outTexture.get_array_size()) {
        return;
    }
    
    ushort2 stride = ushort2(param.strideX, param.strideY);
    const ushort2 posInInput = ushort2(gid.xy) * stride + ushort2(param.offsetX, param.offsetY);
    
    constexpr sampler sample(coord::pixel, filter::nearest, address::clamp_to_zero);
    const uint kernelHXW = 9;
    uint input_arr_size = inTexture.get_array_size();
    uint weithTo = gid.z * kernelHXW * input_arr_size * 4;
    
    float4 output = float4(0.0);
    
    half4 input[9];
    for (uint i = 0; i < input_arr_size; ++i) {
        input[0] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y - 1), i);
        input[1] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y - 1), i);
        input[2] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y - 1), i);
        input[3] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y), i);
        input[4] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y), i);
        input[5] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y), i);
        input[6] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y + 1), i);
        input[7] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y + 1), i);
        input[8] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y + 1), i);
        for (int j = 0; j < 9; ++j) {
            half4 weight_x = weights[weithTo + 0 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.x += dot(float4(input[j]), float4(weight_x));
            
            half4 weight_y = weights[weithTo + 1 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.y += dot(float4(input[j]), float4(weight_y));
            
            half4 weight_z = weights[weithTo + 2 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.z += dot(float4(input[j]), float4(weight_z));
            
            half4 weight_w = weights[weithTo + 3 * kernelHXW * input_arr_size + j * input_arr_size + i];
            output.w += dot(float4(input[j]), float4(weight_w));
        }
    }
    outTexture.write(half4(output), gid.xy, gid.z);
}

kernel void depthwise_conv_3x3_half(texture2d_array<half, access::sample> inTexture [[texture(0)]],
                                    texture2d_array<half, access::write> outTexture [[texture(1)]],
                                    constant MetalConvParam &param [[buffer(0)]],
                                    const device half *weights [[buffer(1)]],
                                    uint3 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() ||
        gid.y >= outTexture.get_height() ||
        gid.z >= outTexture.get_array_size()) {
        return;
    }
    uint output_slice = gid.z;
    ushort2 stride = ushort2(param.strideX, param.strideY);
    ushort2 posInInput = ushort2(gid.xy) * stride + ushort2(param.offsetX, param.offsetY);
    constexpr sampler sample(coord::pixel, filter::nearest, address::clamp_to_zero);
    const uint kernelHXW = 9;
    uint weithTo = gid.z * kernelHXW * 4;
    float4 output = float4(0.0);
    half4 inputs[9];
    inputs[0] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y - 1), output_slice);
    inputs[1] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y - 1), output_slice);
    inputs[2] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y - 1), output_slice);
    inputs[3] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y), output_slice);
    inputs[4] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y), output_slice);
    inputs[5] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y), output_slice);
    inputs[6] = inTexture.sample(sample, float2(posInInput.x - 1,    posInInput.y + 1), output_slice);
    inputs[7] = inTexture.sample(sample, float2(posInInput.x,        posInInput.y + 1), output_slice);
    inputs[8] = inTexture.sample(sample, float2(posInInput.x + 1,    posInInput.y + 1), output_slice);
    for (int j = 0; j < 9; ++j) {
        half4 input = inputs[j];
        output.x += float(input.x) * float(weights[weithTo + 0 * kernelHXW + j]);
        output.y += float(input.y) * float(weights[weithTo + 1 * kernelHXW + j]);
        output.z += float(input.z) * float(weights[weithTo + 2 * kernelHXW + j]);
        output.w += float(input.w) * float(weights[weithTo + 3 * kernelHXW + j]);
    }
    outTexture.write(half4(output), gid.xy, gid.z);
}

kernel void conv_1x1_half(texture2d_array<half, access::sample> inTexture [[texture(0)]],
                          texture2d_array<half, access::write> outTexture [[texture(1)]],
                          constant MetalConvParam &param [[buffer(0)]],
                          const device half4 *weights [[buffer(1)]],
                          uint3 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() ||
        gid.y >= outTexture.get_height() ||
        gid.z >= outTexture.get_array_size()) {
        return;
    }
    
    ushort2 stride = ushort2(param.strideX, param.strideY);
    ushort2 posInInput = ushort2(gid.xy) * stride + ushort2(param.offsetX, param.offsetY);
    
    constexpr sampler sample(coord::pixel, filter::nearest, address::clamp_to_zero);
    const uint kernelHXW = 1;
    
    uint input_arr_size = inTexture.get_array_size();
    uint weithTo = gid.z * kernelHXW * input_arr_size * 4;
    
    float4 output = float4(0.0);
    
    half4 input;
    for (uint i = 0; i < input_arr_size; ++i) {
        input = inTexture.sample(sample, float2(posInInput.x, posInInput.y), i);
        half4 weight_x = weights[weithTo + 0 * kernelHXW * input_arr_size  + i];
        output.x += dot(float4(input), float4(weight_x));
        
        half4 weight_y = weights[weithTo + 1 * kernelHXW * input_arr_size  + i];
        output.y += dot(float4(input), float4(weight_y));
        
        half4 weight_z = weights[weithTo + 2 * kernelHXW * input_arr_size  + i];
        output.z += dot(float4(input), float4(weight_z));
        
        half4 weight_w = weights[weithTo + 3 * kernelHXW * input_arr_size + i];
        output.w += dot(float4(input), float4(weight_w));
    }
    outTexture.write(half4(output), gid.xy, gid.z);
}


