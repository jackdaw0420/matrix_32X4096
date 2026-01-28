`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/17 17:51:21
// Design Name: 
// Module Name: write_out_new
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//双缓存存储计算好的32X32输出矩阵的数据，同时将顺序还原好的数据存放到uram中
//第一个32*32矩阵用于接收正在计算输出的数据，第二个用于存储上一个已经计算完成的数据。每一个备用矩阵中的数据全部输出后就直接清零

module write_out_new#(
    parameter ARRAY_SIZE = 32,
	parameter OUTPUT_DATA_WIDTH = 16
)(
    input clk,
	input srstn,
	input sram_write_enable,

	input [1:0] data_set,
	input [5:0] matrix_index,
	input [12:0]cycle_num,

	input signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data,
	
	input          uram_rd_en,
	input  [12:0]  uram_rd_addr,
	
	output signed  [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] uram_rd_data//未指定位宽
    );

localparam OUTCOME_WIDTH = 16;
localparam MAX_INDEX = ARRAY_SIZE - 1;
localparam DIOGONAL_NUM = 2*ARRAY_SIZE - 1;
//双缓存矩阵
reg signed [OUTPUT_DATA_WIDTH-1:0] temp_matrix         [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
reg signed [OUTPUT_DATA_WIDTH-1:0] temp_matrix_nx      [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]  r_quantized_data;

//uram控制信号
reg [5:0]                               uram_input_data_cnt;
reg                                     uram_write_enable;
reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]  uram_wdata;
reg [11:0]                              uram_wdata_addr;
reg [11:0]                              uram_wdata_addr_nx;

//要等待第一个矩阵完全输出后才能将完全重排的数据输入到uram中，quantized_data中
integer i,j;

assign r_quantized_data = quantized_data;

always@(posedge clk or negedge srstn)begin
    if (!srstn) begin // Reset the matrix multiplication results to 0
        for (i = 0; i < ARRAY_SIZE; i = i + 1) 
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                temp_matrix[i][j] <= 0;
    end
    else begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) 
            for (j = 0; j < ARRAY_SIZE; j = j + 1) 
                temp_matrix[i][j] <= temp_matrix_nx[i][j];
    end
end

//更改了matrix_index计算逻辑，只在第一个数据金鑫阁4096次计算完成后，才开始累加表示对角线数据的输出，范围：0-62
always@(*) begin   
    if (cycle_num < 21'd4097) begin // Reset the matrix multiplication results to 0
        for (i = 0; i < ARRAY_SIZE; i = i + 1) 
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                temp_matrix_nx[i][j] = 0;
    end
    else if ((matrix_index < ARRAY_SIZE) && ((cycle_num - 21'd1) % 21'd4096 <= 31)) begin
        // 还原上三角的对角线输出数据    
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE - i; j = j + 1) begin//只遍历上三角 （包括主对角线）
                if (i + j == matrix_index) begin
                    temp_matrix_nx [i][j] = r_quantized_data[i* OUTCOME_WIDTH +: OUTCOME_WIDTH];
                end
            end
        end
    end
    else if ((matrix_index >= ARRAY_SIZE) && ((cycle_num - 21'd1) % 21'd4096 > 31) && ((cycle_num - 21'd1) % 21'd4096 <= 62)) begin
        // 还原下三角的对角线输出数据  
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = ARRAY_SIZE -  i - 1; j < ARRAY_SIZE; j = j + 1) begin//确保只遍历下三角
                if (i + j == matrix_index) begin
                    temp_matrix_nx [i][j] = r_quantized_data[i* OUTCOME_WIDTH +: OUTCOME_WIDTH];
                end
            end
        end
    end
    else if((cycle_num - 21'd95) % 21'd4096 == 0)begin//当完成了32次的temp_matrix数据向uram中填充后，对temp_matrix进行清零
        for(i = 0;i < ARRAY_SIZE;i = i + 1)begin
            for(j = 0;j < ARRAY_SIZE;j = j + 1)begin
                temp_matrix_nx[i][j] = 0;
            end
        end    
    end
    else begin//在中间的计算的周期中保持为0
        for (i = 0; i < ARRAY_SIZE; i = i + 1) 
            for (j = 0; j < ARRAY_SIZE; j = j + 1) 
                temp_matrix_nx[i][j] = temp_matrix[i][j];
    end 
end

//当一个32*32部分的所有计算结果全部输出到temp_matrix中后，启动uram的写入，一行一行的输入矩阵数据
always@(posedge clk or negedge srstn)begin
    if(!srstn)
        uram_input_data_cnt <= 6'b0;
    else if(((cycle_num - 21'd64) % 21'd4096 <= 30) && cycle_num >= 21'd4096)//需要更改计算逻辑
        uram_input_data_cnt <= uram_input_data_cnt + 6'b1;
    else if(((cycle_num - 21'd64) % 21'd4096 >= 31) && ((cycle_num - 21'd64) % 21'd4096 <= 4095) && cycle_num >= 21'd4096)//需要更改计算逻辑
        uram_input_data_cnt <= 0;
    else 
        uram_input_data_cnt <= uram_input_data_cnt;
end

always@(posedge clk or negedge srstn)begin
    if(!srstn)begin
        uram_wdata_addr <= 0;
    end
    else begin
        uram_wdata_addr <= uram_wdata_addr_nx;
    end
end

//当temp_matrix中填充完数据后就启动uram的数据输入逻辑
always@(*)begin
    if(((cycle_num - 21'd64) % 21'd4096 <= 31) && cycle_num >= 21'd4096)begin
        uram_write_enable = 1'b1;
        uram_wdata_addr_nx = uram_wdata_addr + 12'b1;//每一个addr代表一行32个元素
        for (j = 0; j < ARRAY_SIZE; j = j + 1) 
            uram_wdata[(ARRAY_SIZE-1-j)*OUTPUT_DATA_WIDTH+:OUTPUT_DATA_WIDTH] = temp_matrix[uram_input_data_cnt][j];//将数据倒序重排，因为（0，0）会被存储在最低位
    end
    else if(((cycle_num - 21'd64) % 21'd4096 > 31) && ((cycle_num - 21'd64) % 21'd4096 <= 4095) && cycle_num >= 21'd4096)begin//需要更改计算逻辑
        uram_wdata_addr_nx = uram_wdata_addr;
        uram_write_enable = 1'b0;
    end
    else begin
        uram_wdata = 0;
        uram_write_enable = 1'b0;
        uram_wdata_addr_nx = uram_wdata_addr;
    end
end
    
xpm_memory_sdpram #(
    // 地址配置 - 需要能寻址4096个位置
    .ADDR_WIDTH_A(12),      // 端口A地址线宽度：12位，可寻址0-4095
    .ADDR_WIDTH_B(12),      // 端口B地址线宽度：12位，可寻址0-4095
    
    // 性能与功耗
    .AUTO_SLEEP_TIME(0),    // 禁用自动休眠
    
    // 字节写配置 - 重要！因为URAM不支持真正的字节写
    .BYTE_WRITE_WIDTH_A(512), // 设为与写数据宽度相同，表示按字（512位）写入
    
    // 架构配置
    .CASCADE_HEIGHT(0),     // 不级联多个URAM
    .CLOCKING_MODE("common_clock"), // 公共时钟模式
    
    // 纠错功能
    .ECC_MODE("no_ecc"),    // 不启用ECC（URAM本身有校验位，但这里不启用ECC功能）
    
    // 初始化配置
    .MEMORY_INIT_FILE("none"),  // 无初始化文件
    .MEMORY_INIT_PARAM("0"),    // 无初始化参数
    
    // 优化选项
    .MEMORY_OPTIMIZATION("true"), // 启用内存优化
    .MEMORY_PRIMITIVE("ultra"),   // 必须设为"ultra"以使用URAM
    
    // 容量配置 - 关键修改！
    .MEMORY_SIZE(2097152),  // 总存储容量：4096 × 512 = 2,097,152位
    
    // 控制与消息
    .MESSAGE_CONTROL(0),    // 禁用碰撞警告
    
    // 端口B读取配置
    .READ_DATA_WIDTH_B(512),  // 读取数据宽度：512位
    .READ_LATENCY_B(2),      // 读取延迟：URAM通常是2个时钟周期
    .READ_RESET_VALUE_B("0"), // 读取复位值
    
    // 复位模式
    .RST_MODE_A("SYNC"),    // 同步复位
    .RST_MODE_B("SYNC"),    // 同步复位
    
    // 仿真与验证
    .SIM_ASSERT_CHK(0),     // 禁用仿真断言
    .USE_EMBEDDED_CONSTRAINT(0), // 禁用嵌入式约束
    
    // 初始化相关
    .USE_MEM_INIT(1),       // 启用内存初始化
    .USE_MEM_INIT_MMI(0),   // 禁用MMI文件
    
    // 功耗管理
    .WAKEUP_TIME("disable_sleep"), // 禁用休眠
    
    // 端口A写入配置
    .WRITE_DATA_WIDTH_A(512),  // 写入数据宽度：512位
    .WRITE_MODE_B("read_first"), // 写模式："read_first"表示写时先读取旧值
    .WRITE_PROTECT(1)         // 写保护：通过EN和WEA信号控制
)
xpm_memory_sdpram_inst (
    // 输出端口
    .dbiterrb(),           // 未使用
    .sbiterrb(),           // 未使用
    .doutb(uram_rd_data),  // 读取数据输出：512位
    
    // 输入端口
    .addra(uram_wdata_addr), // 写入地址：12位
    .addrb(rd_addr),       // 读取地址：12位
    .clka(clk),          // 时钟
    .clkb(clk),          // 时钟（公共时钟模式）
    .dina(uram_wdata),           // 写入数据输入：512位
    
    // 使能信号
    .ena(uram_write_enable),            // 端口A使能
    .enb(uram_rd_en),            // 端口B使能
    
    // ECC错误注入
    .injectdbiterra(1'b0), // 禁用
    .injectsbiterra(1'b0), // 禁用
    
    // 输出寄存器控制
    .regceb(1'b1),         // 输出寄存器使能
    
    // 复位信号
    .rstb(!srstn),       // 复位
    
    // 低功耗控制
    .sleep(1'b0),          // 注意：必须为0，否则URAM进入休眠状态！
    
    // 写使能信号
    .wea(uram_write_enable)              // 写使能：1位宽，控制整个512位写入
);

endmodule
