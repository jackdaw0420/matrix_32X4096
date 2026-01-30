`timescale 1ns/100ps

module systolic #(
    parameter ARRAY_SIZE = 32,             // Size of the array (32x32)
    parameter SRAM_DATA_WIDTH = 32,        // Data width for SRAM input
    parameter DATA_WIDTH = 8               // Data width for elements in the matrix
)(
    input wire clk,                             // Clock signal
    input wire rst_n,                           // Synchronous reset (active low)
    
    input wire alu_start,                       // Enable signal to start computation
    input wire  [20:0] cycle_num,                 // Current cycle number
    
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w0, // SRAM input for weight queue (32-bit)
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w1, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w2, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w3, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w4, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w5, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w6, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_w7, 
    
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d0, // SRAM input for data queue (32-bit)
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d1, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d2, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d3, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d4, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d5, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d6, 
    input wire  [SRAM_DATA_WIDTH-1:0] sram_rdata_d7, 
    
    input wire  [5:0] matrix_index,              // Index for selecting output matrix
    output reg signed [(ARRAY_SIZE*(DATA_WIDTH+DATA_WIDTH+12))-1:0] mul_outcome // Output of the multiplication result
);

// Local parameters for controlling matrix multiplication flow
localparam OUTCOME_WIDTH = DATA_WIDTH + DATA_WIDTH + 12; // 乘法结果位宽(8+8+12=28)

// Internal registers
reg signed [OUTCOME_WIDTH-1:0] matrix_mul_2D [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1]; // matrix_mul_2D_nx的回填结果矩阵，用于接收matrix_mul_2D_nx中的相乘数据
reg signed [OUTCOME_WIDTH-1:0] matrix_mul_2D_nx [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1]; //直接写入数据和权重相乘的结果（组合逻辑计算）
reg signed [DATA_WIDTH-1:0] data_queue [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];         //32 * 32矩阵 每个元素8位 Data queue for inputs
reg signed [DATA_WIDTH-1:0] weight_queue [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];       //32 * 32矩阵 每个元素8位 Weight queue for inputs
reg signed [DATA_WIDTH+DATA_WIDTH-1:0] mul_result;  // 16位输出数据 Temporary variable for holding multiplication result

// 清零控制寄存器
reg         clear_enable;                   // 清零使能信号
reg [5:0]   clear_diag;               // 需要清零的对角线编号
reg [6:0]   clear_cnt;

integer i, j;                        // Loop indices for iteration

/*每个SRAM输入32位，包含4个8位权重
8个SRAM输入共提供32个权重（8×4=32）
权重在阵列中沿行向下逐行移位*/
always @(posedge clk) begin
    if (~rst_n) begin // On reset, initialize the queues to 0
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                weight_queue[i][j] <= 0;
                data_queue[i][j] <= 0;
            end
        end
    end
    else if (alu_start) begin
        for (i = 0; i < 4; i = i + 1) begin  
            weight_queue[0][i] <= sram_rdata_w0[31-8*i-:8];//32位数据，包含4个8位的权重数据，第0行从输入加载权重  0-3列
            weight_queue[0][i+4] <= sram_rdata_w1[31-8*i-:8];// 4-7列
            weight_queue[0][i+8] <= sram_rdata_w2[31-8*i-:8];
            weight_queue[0][i+12] <= sram_rdata_w3[31-8*i-:8];
            weight_queue[0][i+16] <= sram_rdata_w4[31-8*i-:8];
            weight_queue[0][i+20] <= sram_rdata_w5[31-8*i-:8];
            weight_queue[0][i+24] <= sram_rdata_w6[31-8*i-:8];
            weight_queue[0][i+28] <= sram_rdata_w7[31-8*i-:8];
        end
        for (i = 1; i < ARRAY_SIZE; i = i + 1)// 第1-31行从上一行移位
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                weight_queue[i][j] <= weight_queue[i-1][j];//32个周期完全填充权重参数
                
        // Shift data queue
        /* 每个SRAM输入32位，包含4个8位数据
        8个SRAM输入共提供32个数据（8×4=32）
        数据在阵列中沿列向右逐列移位*/
        for (i = 0; i < 4; i = i + 1) begin  // 第0列从输入加载数据 0-3行
            data_queue[i][0] <= sram_rdata_d0[31-8*i-:8];
            data_queue[i+4][0] <= sram_rdata_d1[31-8*i-:8];
            data_queue[i+8][0] <= sram_rdata_d2[31-8*i-:8];
            data_queue[i+12][0] <= sram_rdata_d3[31-8*i-:8];
            data_queue[i+16][0] <= sram_rdata_d4[31-8*i-:8];
            data_queue[i+20][0] <= sram_rdata_d5[31-8*i-:8];
            data_queue[i+24][0] <= sram_rdata_d6[31-8*i-:8];
            data_queue[i+28][0] <= sram_rdata_d7[31-8*i-:8];
        end
        for (i = 0; i < ARRAY_SIZE; i = i + 1)// 第1-31列从左侧移位
            for (j = 1; j < ARRAY_SIZE; j = j + 1)
                data_queue[i][j] <= data_queue[i][j-1];//32个周期完全填充数据参数
    end
end

// Multiplication unit
always @(posedge clk) begin
    if (~rst_n) begin // Reset the matrix multiplication results to 0
        for (i = 0; i < ARRAY_SIZE; i = i + 1) 
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                matrix_mul_2D[i][j] <= 0;
    end
    else begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) 
            for (j = 0; j < ARRAY_SIZE; j = j + 1) 
                matrix_mul_2D[i][j] <= matrix_mul_2D_nx[i][j];
    end
end

// 更改了matrix_index计算逻辑，只在第一个数据进行过4096次计算完成后，才开始累加表示对角线数据的输出，范围：0-62
always@(*) begin
    if (alu_start) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                if (cycle_num >= 1 && (i + j) <= (cycle_num - 1)) begin
                    // 累加模式
                    mul_result = weight_queue[i][j] * data_queue[i][j];
                    matrix_mul_2D_nx[i][j] = matrix_mul_2D[i][j] + { {12{mul_result[15]}}, mul_result };
                end
                else if (cycle_num >= 21'd4096 && (i + j) == (cycle_num - 21'd4096)) begin
                    mul_result = weight_queue[i][j] * data_queue[i][j];
                    matrix_mul_2D_nx[i][j] = { {12{mul_result[15]}}, mul_result };
                end
                else begin
                    matrix_mul_2D_nx[i][j] = matrix_mul_2D[i][j];
                end
                // 进行清零
                if (clear_enable && cycle_num >= 21'd4097) begin
                    if (matrix_index < ARRAY_SIZE) begin
                        // 上三角清零条件
                        if (j < ARRAY_SIZE - i && (i + j) == clear_diag) begin
                            matrix_mul_2D_nx[i][j] = 0;
                        end
                    end
                    else begin
                        // 下三角清零条件
                        if (j >= ARRAY_SIZE - i - 1 && (i + j) == clear_diag) begin
                            matrix_mul_2D_nx[i][j] = 0;
                        end
                    end
                end
            end
        end
    end      
    else begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                matrix_mul_2D_nx[i][j] = matrix_mul_2D[i][j];
            end
        end
    end
end

//更改了matrix_index计算逻辑，只在第一个数据进行过4096次计算完成后，才开始累加表示对角线数据的输出，范围：0-62
always@(*) begin   
    // 初始化输出为0
    for (i = 0; i < ARRAY_SIZE * OUTCOME_WIDTH; i = i + 1)begin
        mul_outcome[i] = 0;   
    end
    if (matrix_index < ARRAY_SIZE) begin//当matrix_index < ARRAY_SIZE时，需要输出的是下三角的数据，需要映射到下三角
        // 输出上三角的对角线  
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE - i; j = j + 1) begin//只遍历上三角（包括主对角线）
                if (i + j == matrix_index) begin
                    mul_outcome[i* OUTCOME_WIDTH +: OUTCOME_WIDTH] = matrix_mul_2D[i][j];
                end
            end
        end
    end
    else if ((matrix_index >= ARRAY_SIZE)) begin//由仿真的到，当cycle_num为4097时，matrix_index为32，因此要映射到上三角输出
        // 输出下三角的对角线  
        for (i = 1; i < ARRAY_SIZE; i = i + 1) begin
            for (j = ARRAY_SIZE - i; j < ARRAY_SIZE; j = j + 1) begin//只遍历上三角（包括主对角线）
                if (i + j == matrix_index) begin
                    mul_outcome[i * OUTCOME_WIDTH +: OUTCOME_WIDTH] = matrix_mul_2D[i][j];
                end
            end
        end
    end
end

always@(*)begin
    if((cycle_num >= 21'd4097) && ((cycle_num - 21'd4097) % 21'd4096 <= 62))begin//clear_enable拉高的条件和systolli输出的条件是一样的，
        if(matrix_index < ARRAY_SIZE)begin
            clear_enable = 1;
            clear_diag = matrix_index;
        end
        else begin
            clear_enable = 1;
            clear_diag = matrix_index;
        end
    end
    else begin
        clear_diag = 0;
        clear_enable = 0;
    end
end      

endmodule
