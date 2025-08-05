/*
==============================================================
PRISM Downloadable Configuration

Input:    chroma_spislave.sv
Config:   tinyqv.cfg
==============================================================
*/

#include <stdint.h>

const uint32_t chroma_spislave[] =
{
   0x000003c0, 0x08000000, 
   0x00000380, 0x08010000, 
   0x00000141, 0x08012003, 
   0x000003f8, 0x0800a000, 
   0x00000140, 0x0801a01d, 
   0x00000380, 0x08010000, 
   0x00000282, 0x08016003, 
   0x00000041, 0x08012000, 

};
const uint32_t chroma_spislave_count   = 8;
const uint32_t chroma_spislave_width   = 44;
const uint32_t chroma_spislave_ctrlReg = 0x00002912;
