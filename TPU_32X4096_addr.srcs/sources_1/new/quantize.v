`timescale 1ns/100ps
/*本模块旨在对收缩阵列的输出数据进行量化处理。                  
1.  它将数据从较大的位宽格式（32位）转换为较小的位宽（16位）。
2.  输入数据包含16位整数部分和8位小数部分，           
3.  量化后整数部分为8位，小数部分为8位。若原始数据超出16位范围（[-32768, 32767]），则进行饱和处理。  */          

//该模块对收缩阵列的输出数据进行量化处理，以缩减数据体积并格式化数据以便后续处理或存储。
module quantize#(
    parameter ARRAY_SIZE = 32,               // The size of the systolic array (32x32).
    parameter SRAM_DATA_WIDTH = 32,          // Data width of SRAM.
    parameter DATA_WIDTH = 8,                // Data width of the input data.
    parameter OUTPUT_DATA_WIDTH = 16         // Data width of the output quantized data.
)
(
    input signed [ARRAY_SIZE*(DATA_WIDTH+DATA_WIDTH+12)-1:0] ori_data,  // Original data from systolic array.
    output reg signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data // Quantized output data.
);

// Define local parameters for saturation limits.
localparam max_val = 32767,                  // Maximum value for quantization.
          min_val = -32768;                  // Minimum value for quantization.
localparam ORI_WIDTH = DATA_WIDTH+DATA_WIDTH+12; // The bit-width of the original input data (21 bits).

// Intermediate register to hold shifted original data.
reg signed [ORI_WIDTH-1:0] ori_shifted_data;  

// Integer for loop iteration.
integer i;

//--------Quantization Process--------
/*输入数据通过检查是否超过最大值或最小值进行量化。
若超过，则饱和至相应边界值。
否则，直接作为16位量化值传递至输出端。*/
always @* begin
    for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
        ori_shifted_data = ori_data[i*ORI_WIDTH +: ORI_WIDTH];// 从ori_data中提取第i个28位数据
        if (ori_shifted_data >= max_val) // 2. 饱和判断和量化
            quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = max_val;
        else if (ori_shifted_data <= min_val)
            quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = min_val;
        else
            quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = ori_shifted_data[OUTPUT_DATA_WIDTH-1:0];
    end
end

endmodule
