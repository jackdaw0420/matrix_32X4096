`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/02 00:02:45
// Design Name: 
// Module Name: temp_matrix_uram_32X32
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


module temp_matrix_uram_32X32#(
    parameter ARRAY_SIZE = 32,
	parameter OUTPUT_DATA_WIDTH = 16
)(
    input                                       i_clk,
    input                                       i_rst_n,
    input                                       wr_en,
    input                                       rd_en,
    input [8:0]                                 wr_addr,
    input [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]    i_wr_data,
    
    output[ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]    o_rd_data,
    output[8:0]                                 o_rd_addr
    );


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
    .doutb(doutb),         // 读取数据输出：512位
    
    // 输入端口
    .addra(wr_addr),       // 写入地址：12位
    .addrb(rd_addr),       // 读取地址：12位
    .clka(i_clk),          // 时钟
    .clkb(i_clk),          // 时钟（公共时钟模式）
    .dina(dina),           // 写入数据输入：512位
    
    // 使能信号
    .ena(1'b1),            // 端口A使能
    .enb(1'b1),            // 端口B使能
    
    // ECC错误注入
    .injectdbiterra(1'b0), // 禁用
    .injectsbiterra(1'b0), // 禁用
    
    // 输出寄存器控制
    .regceb(1'b1),         // 输出寄存器使能
    
    // 复位信号
    .rstb(!i_rst_n),       // 复位
    
    // 低功耗控制
    .sleep(1'b0),          // 注意：必须为0，否则URAM进入休眠状态！
    
    // 写使能信号
    .wea(wea)              // 写使能：1位宽，控制整个512位写入
);
				
endmodule
