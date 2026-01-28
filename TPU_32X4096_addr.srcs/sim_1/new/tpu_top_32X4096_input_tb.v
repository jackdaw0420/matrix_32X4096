`timescale 1ns/100ps

module tpu_top_32X4096_input_tb();

// 参数定义
parameter ARRAY_SIZE = 32;
parameter SRAM_DATA_WIDTH = 32;
parameter DATA_WIDTH = 8;
parameter OUTPUT_DATA_WIDTH = 16;
parameter WEIGHT_MATRIX_WIDTH = 4096;
parameter DATA_ROWS = 32;
parameter DATA_COLS = 16415;//4127
parameter WEIGHT_ROWS = 16415;//4127
parameter WEIGHT_COLS = 32;

// 时钟和复位
reg clk;
reg srstn;
reg tpu_start;

// SRAM输入数据
reg [SRAM_DATA_WIDTH-1:0] sram_rdata_w0, sram_rdata_w1, sram_rdata_w2, sram_rdata_w3;
reg [SRAM_DATA_WIDTH-1:0] sram_rdata_w4, sram_rdata_w5, sram_rdata_w6, sram_rdata_w7;
reg [SRAM_DATA_WIDTH-1:0] sram_rdata_d0, sram_rdata_d1, sram_rdata_d2, sram_rdata_d3;
reg [SRAM_DATA_WIDTH-1:0] sram_rdata_d4, sram_rdata_d5, sram_rdata_d6, sram_rdata_d7;

// 内部信号
reg [20:0] weight_row_counter;  // 权重行计数器
reg [20:0] data_col_counter;    // 数据列计数器
reg [15:0] total_cycles;        // 总周期计数器
reg tpu_active;                 // TPU激活标志
reg done_detected;              // 完成信号检测标志
reg input_complete;             // 输入完成标志

// 测试矩阵
reg signed [DATA_WIDTH-1:0] matrix_A [0:DATA_ROWS-1][0:DATA_COLS-1];
reg signed [DATA_WIDTH-1:0] matrix_B [0:WEIGHT_ROWS-1][0:WEIGHT_COLS-1];

// 结果矩阵
reg signed [OUTPUT_DATA_WIDTH-1:0] result_matrix [0:31][0:31];

// 文件句柄
integer file_handle_A, file_handle_B, result_file, debug_file;
integer i, j;

// URAM写控制输出
wire uram_write_enable;
wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] uram_wdata;
wire [11:0] uram_wdata_addr;

// 控制信号输出
wire tpu_done;
wire [20:0] cycle_num;  // 改为13位以匹配主模块
wire [5:0] matrix_index;

// 时钟生成
always #5 clk = ~clk;  // 100MHz时钟

// 读取二进制文件任务
task read_bin_file;
    input integer file;
    input integer is_matrix_A;
    
    integer i, j, k, ch, bit_count;
    reg [7:0] char, bin_val;
    integer total_rows, total_cols;
    
begin
    if (is_matrix_A) begin
        total_rows = DATA_ROWS;
        total_cols = DATA_COLS;
    end else begin
        total_rows = WEIGHT_ROWS;
        total_cols = WEIGHT_COLS;
    end
    
    $display("  读取%s矩阵，大小: %d × %d", is_matrix_A ? "A" : "B", total_rows, total_cols);
    
    for (i = 0; i < total_rows; i = i + 1) begin
        for (j = 0; j < total_cols; j = j + 1) begin
            ch = $fgetc(file);
            while (ch == " " || ch == "\n" || ch == "\r" || ch == "\t") begin
                ch = $fgetc(file);
                if (ch == -1) begin
                    $display("错误: 文件过早结束");
                    $finish;
                end
            end
            
            bin_val = 0;
            for (bit_count = 0; bit_count < 8; bit_count = bit_count + 1) begin
                if (ch < 0) begin
                    $display("错误: 读取二进制位时文件结束");
                    $finish;
                end
                char = ch;
                
                if (char == "0" || char == "1") begin
                    bin_val = (bin_val << 1) | (char == "1" ? 1'b1 : 1'b0);
                end else begin
                    $display("错误: 期望二进制位，得到字符 '%c' (ASCII %0d)", char, char);
                    $finish;
                end
                
                if (bit_count < 7) begin
                    ch = $fgetc(file);
                end
            end
            
            if (is_matrix_A) begin
                if (bin_val[7]) begin
                    matrix_A[i][j] = -128 + (bin_val & 8'h7F);
                end else begin
                    matrix_A[i][j] = bin_val;
                end
            end
            else begin
                if (bin_val[7]) begin
                    matrix_B[i][j] = -128 + (bin_val & 8'h7F);
                end else begin
                    matrix_B[i][j] = bin_val;
                end
            end
            
            if (j < total_cols - 1) begin
                ch = $fgetc(file);
                while (ch == " ") begin
                    ch = $fgetc(file);
                end
                $ungetc(ch, file);
            end
        end
        
        ch = $fgetc(file);
        while (ch == "\n" || ch == "\r") begin
            ch = $fgetc(file);
        end
        if (ch != -1) begin
            $ungetc(ch, file);
        end
        
        if (i < 3) begin
            $display("  已完成第%d行读取", i+1);
        end
    end
    $display("  √ 成功读取%d×%d矩阵", total_rows, total_cols);
end
endtask

// 保存结果到文件的任务
task save_result_to_file;
    integer i, j;
begin
    $display("\n保存计算结果到文件...");
    result_file = $fopen("tpu_result_32x4096.txt", "w");
    if (result_file == 0) begin
        $display("错误: 无法创建结果文件 tpu_result_32x4096.txt");
    end
    
    // 写入文件头
    $fdisplay(result_file, "// TPU 32×4096矩阵乘法计算结果");
    $fdisplay(result_file, "// 时间: %t", $time);
    $fdisplay(result_file, "// 总计算周期: %d", total_cycles);
    $fdisplay(result_file, "// 格式: 元素索引, 十进制值, 十六进制值, 二进制值");
    $fdisplay(result_file, "");
    
    // 保存输出矩阵
    for (i = 0; i < 32; i = i + 1) begin
        for (j = 0; j < 32; j = j + 1) begin
            $fdisplay(result_file, "元素[%2d][%2d]: %6d, 0x%04X, %016b", 
                     i, j, result_matrix[i][j], result_matrix[i][j], result_matrix[i][j]);
        end
    end
    
    $fclose(result_file);
    $display("\n√ 结果已保存到文件: tpu_result_32x4096.txt");
end
endtask

initial begin
    $display("TPU 32x4096矩阵乘法测试");
    
    // 打开调试文件
    debug_file = $fopen("debug_output.txt", "w");
    
    // 初始化
    clk = 0;
    srstn = 0;
    tpu_start = 0;
    tpu_active = 0;
    done_detected = 0;
    total_cycles = 0;
    weight_row_counter = 0;
    data_col_counter = 0;
    input_complete = 0;
    
    // 1. 读取测试矩阵A
    $display("\n1. 读取测试矩阵A...");
    file_handle_A = $fopen("delay_data_input_matrix_bin_32X8192_small.txt", "r");
    if (file_handle_A == 0) begin
        $display("错误: 无法打开文件 delay_data_input_matrix_bin_32X8192_small.txt");
        $finish;
    end
    read_bin_file(file_handle_A, 1);
    $fclose(file_handle_A);
    
    // 显示矩阵A前3x3
    $display("矩阵A前3x3:");
    for (i = 0; i < 3; i = i + 1) begin
        $write("  ");
        for (j = 0; j < 3; j = j + 1) begin
            $write("%d ", matrix_A[i][j]);
        end
        $display("");
    end
    
    // 2. 读取测试矩阵B
    $display("\n2. 读取测试矩阵B...");
    file_handle_B = $fopen("delay_weight_input_matrix_bin_32X8192_small.txt", "r");
    if (file_handle_B == 0) begin
        $display("错误: 无法打开文件 delay_weight_input_matrix_bin_32X8192_small.txt");
        $finish;
    end
    read_bin_file(file_handle_B, 0);
    $fclose(file_handle_B);
    
    $display("矩阵B前3x3:");
    for (i = 0; i < 3; i = i + 1) begin
        $write("  ");
        for (j = 0; j < 3; j = j + 1) begin
            $write("%d ", matrix_B[i][j]);
        end
        $display("");
    end
    
    // 3. 启动测试
    $display("\n3. 启动测试...");
    
    // 复位
    srstn = 0;
    #20 srstn = 1;
    #10;
    
    // 启动计算
    tpu_start = 1;
    #10 tpu_start = 0;
    
    #10 
    tpu_active = 1;
    
    $display("4. TPU已启动，等待计算完成...");
    
    // 7. 设置超时保护
    #10000000;  // 10ms超时保护
    if (!tpu_done) begin
        $display("\n错误: 仿真超时! 在10ms内未完成计算");
        $display("当前周期: %d", total_cycles);
        $display("权重行计数器: %d/%d", weight_row_counter, WEIGHT_ROWS);
        $display("数据列计数器: %d/%d", data_col_counter, DATA_COLS);
    end
    
    $fclose(debug_file);
    $finish;
end

// 总周期计数器
always @(posedge clk) begin
    if (!srstn) begin
        total_cycles <= 0;
    end else if (tpu_active) begin
        total_cycles <= total_cycles + 1;
        
        // 每100个周期显示进度
        if (total_cycles % 100 == 0 && total_cycles > 0) begin
            $display("时间 %0t ns: 已运行 %d 个周期, cycle_num = %d", 
                    $time, total_cycles, cycle_num);
        end
    end
end

// 检测输入完成
always @(posedge clk) begin
    if (!srstn) begin
        input_complete <= 0;
    end 
    // 当两个计数器都达到最大值时，设置输入完成标志
    else if (weight_row_counter >= WEIGHT_ROWS && data_col_counter >= DATA_COLS) begin
        input_complete <= 1;
        $display("时间 %0t ns: 输入完成，权重行数: %d/%d, 数据列数: %d/%d", 
                $time, weight_row_counter, WEIGHT_ROWS, data_col_counter, DATA_COLS);
    end
end

// 权重矩阵输入逻辑
always @(posedge clk) begin
    if (!srstn) begin
        weight_row_counter <= 0;
        sram_rdata_w0 <= 0; sram_rdata_w1 <= 0; sram_rdata_w2 <= 0; sram_rdata_w3 <= 0;
        sram_rdata_w4 <= 0; sram_rdata_w5 <= 0; sram_rdata_w6 <= 0; sram_rdata_w7 <= 0;
    end 
    // 修改：移除对alu_start的依赖，只依赖tpu_active
    else if (tpu_active && !input_complete && weight_row_counter < WEIGHT_ROWS) begin
        // 从矩阵B读取一行权重
        sram_rdata_w0 <= {matrix_B[weight_row_counter][0],  matrix_B[weight_row_counter][1],  
                         matrix_B[weight_row_counter][2],  matrix_B[weight_row_counter][3]};
        sram_rdata_w1 <= {matrix_B[weight_row_counter][4],  matrix_B[weight_row_counter][5],  
                         matrix_B[weight_row_counter][6],  matrix_B[weight_row_counter][7]};
        sram_rdata_w2 <= {matrix_B[weight_row_counter][8],  matrix_B[weight_row_counter][9],  
                         matrix_B[weight_row_counter][10], matrix_B[weight_row_counter][11]};
        sram_rdata_w3 <= {matrix_B[weight_row_counter][12], matrix_B[weight_row_counter][13], 
                         matrix_B[weight_row_counter][14], matrix_B[weight_row_counter][15]};
        sram_rdata_w4 <= {matrix_B[weight_row_counter][16], matrix_B[weight_row_counter][17], 
                         matrix_B[weight_row_counter][18], matrix_B[weight_row_counter][19]};
        sram_rdata_w5 <= {matrix_B[weight_row_counter][20], matrix_B[weight_row_counter][21], 
                         matrix_B[weight_row_counter][22], matrix_B[weight_row_counter][23]};
        sram_rdata_w6 <= {matrix_B[weight_row_counter][24], matrix_B[weight_row_counter][25], 
                         matrix_B[weight_row_counter][26], matrix_B[weight_row_counter][27]};
        sram_rdata_w7 <= {matrix_B[weight_row_counter][28], matrix_B[weight_row_counter][29], 
                         matrix_B[weight_row_counter][30], matrix_B[weight_row_counter][31]};
        
        // 调试输出
        if (weight_row_counter < 5) begin
            $display("时间 %0t ns: 周期 %d, cycle_num = %d, 输入权重行 %d, 前4个权重: %d, %d, %d, %d", 
                    $time, total_cycles, cycle_num, weight_row_counter,
                    matrix_B[weight_row_counter][0], matrix_B[weight_row_counter][1],
                    matrix_B[weight_row_counter][2], matrix_B[weight_row_counter][3]);
            $fdisplay(debug_file, "时间 %0t ns: 周期 %d, cycle_num = %d, 输入权重行 %d, 前4个权重: %d, %d, %d, %d", 
                    $time, total_cycles, cycle_num, weight_row_counter,
                    matrix_B[weight_row_counter][0], matrix_B[weight_row_counter][1],
                    matrix_B[weight_row_counter][2], matrix_B[weight_row_counter][3]);
        end
        
        weight_row_counter <= weight_row_counter + 1;
    end 
    // 当计数器达到最大值后，输入变为0
    else if (tpu_active && weight_row_counter >= WEIGHT_ROWS) begin
        sram_rdata_w0 <= 0; sram_rdata_w1 <= 0; sram_rdata_w2 <= 0; sram_rdata_w3 <= 0;
        sram_rdata_w4 <= 0; sram_rdata_w5 <= 0; sram_rdata_w6 <= 0; sram_rdata_w7 <= 0;
    end
    // 当TPU不激活时，输入为0
    else if (!tpu_active) begin
        sram_rdata_w0 <= 0; sram_rdata_w1 <= 0; sram_rdata_w2 <= 0; sram_rdata_w3 <= 0;
        sram_rdata_w4 <= 0; sram_rdata_w5 <= 0; sram_rdata_w6 <= 0; sram_rdata_w7 <= 0;
    end
    // 新增：输入完成后，保持当前值不变，不再输入新数据
    else if (input_complete) begin
        // 什么都不做，保持当前值
    end
end

// 数据矩阵输入逻辑
always @(posedge clk) begin
    if (!srstn) begin
        data_col_counter <= 0;
        sram_rdata_d0 <= 0; sram_rdata_d1 <= 0; sram_rdata_d2 <= 0; sram_rdata_d3 <= 0;
        sram_rdata_d4 <= 0; sram_rdata_d5 <= 0; sram_rdata_d6 <= 0; sram_rdata_d7 <= 0;
    end 
    // 修改：移除对alu_start的依赖，只依赖tpu_active
    else if (tpu_active && !input_complete && data_col_counter < DATA_COLS) begin
        // 从矩阵A读取一列数据
        sram_rdata_d0 <= {matrix_A[0][data_col_counter],  matrix_A[1][data_col_counter],  
                         matrix_A[2][data_col_counter],  matrix_A[3][data_col_counter]};
        sram_rdata_d1 <= {matrix_A[4][data_col_counter],  matrix_A[5][data_col_counter],  
                         matrix_A[6][data_col_counter],  matrix_A[7][data_col_counter]};
        sram_rdata_d2 <= {matrix_A[8][data_col_counter],  matrix_A[9][data_col_counter],  
                         matrix_A[10][data_col_counter], matrix_A[11][data_col_counter]};
        sram_rdata_d3 <= {matrix_A[12][data_col_counter], matrix_A[13][data_col_counter], 
                         matrix_A[14][data_col_counter], matrix_A[15][data_col_counter]};
        sram_rdata_d4 <= {matrix_A[16][data_col_counter], matrix_A[17][data_col_counter], 
                         matrix_A[18][data_col_counter], matrix_A[19][data_col_counter]};
        sram_rdata_d5 <= {matrix_A[20][data_col_counter], matrix_A[21][data_col_counter], 
                         matrix_A[22][data_col_counter], matrix_A[23][data_col_counter]};
        sram_rdata_d6 <= {matrix_A[24][data_col_counter], matrix_A[25][data_col_counter], 
                         matrix_A[26][data_col_counter], matrix_A[27][data_col_counter]};
        sram_rdata_d7 <= {matrix_A[28][data_col_counter], matrix_A[29][data_col_counter], 
                         matrix_A[30][data_col_counter], matrix_A[31][data_col_counter]};
        
        // 调试输出
        if (data_col_counter < 5) begin
            $display("时间 %0t ns: 周期 %d, cycle_num = %d, 输入数据列 %d, 前4个数据: %d, %d, %d, %d", 
                    $time, total_cycles, cycle_num, data_col_counter,
                    matrix_A[0][data_col_counter], matrix_A[1][data_col_counter],
                    matrix_A[2][data_col_counter], matrix_A[3][data_col_counter]);
            $fdisplay(debug_file, "时间 %0t ns: 周期 %d, cycle_num = %d, 输入数据列 %d, 前4个数据: %d, %d, %d, %d", 
                    $time, total_cycles, cycle_num, data_col_counter,
                    matrix_A[0][data_col_counter], matrix_A[1][data_col_counter],
                    matrix_A[2][data_col_counter], matrix_A[3][data_col_counter]);
        end
        
        data_col_counter <= data_col_counter + 1;
    end else if (tpu_active && data_col_counter >= DATA_COLS) begin
        sram_rdata_d0 <= 0; sram_rdata_d1 <= 0; sram_rdata_d2 <= 0; sram_rdata_d3 <= 0;
        sram_rdata_d4 <= 0; sram_rdata_d5 <= 0; sram_rdata_d6 <= 0; sram_rdata_d7 <= 0;
    end
    else if (!tpu_active) begin
        sram_rdata_d0 <= 0; sram_rdata_d1 <= 0; sram_rdata_d2 <= 0; sram_rdata_d3 <= 0;
        sram_rdata_d4 <= 0; sram_rdata_d5 <= 0; sram_rdata_d6 <= 0; sram_rdata_d7 <= 0;
    end
    // 新增：输入完成后，保持当前值不变，不再输入新数据
    else if (input_complete) begin
        // 什么都不做，保持当前值
    end
end

// 保存URAM输出
always @(posedge clk) begin
    if (srstn && uram_write_enable) begin
        save_uram_result(uram_wdata_addr, uram_wdata);
    end
end

task save_uram_result;
    input [5:0] addr;
    input [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] data;
    
    integer i;
    integer row;
    reg [OUTPUT_DATA_WIDTH-1:0] element;
    reg signed [OUTPUT_DATA_WIDTH-1:0] signed_data;
begin
    // 计算行号
    row = addr;
    
    if (row < 32) begin
        for (i = 0; i < 32; i = i + 1) begin
            element = data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
            signed_data = $signed(element);
            result_matrix[row][i] = signed_data;
        end
        
        if (row < 3) begin
            $display("时间%0tns: 保存行 %d, 元素[0-2]: %d, %d, %d", 
                    $time, row, result_matrix[row][0], result_matrix[row][1], result_matrix[row][2]);
        end
    end
end
endtask

// 检测计算完成信号并保存结果
always @(posedge clk) begin
    if (!srstn) begin
        done_detected <= 0;
    end else if (tpu_done && !done_detected) begin
        done_detected <= 1;
        $display("\n==========================================");
        $display("TPU计算完成信号检测到!");
        $display("完成时间: %t ns", $time);
        $display("总计算周期: %d", total_cycles);
        $display("总输入权重行数: %d/%d", weight_row_counter, WEIGHT_ROWS);
        $display("总输入数据列数: %d/%d", data_col_counter, DATA_COLS);
        $display("TPU内部cycle_num: %d", cycle_num);
        $display("==========================================");
        
        // 等待几个周期确保结果稳定
        #200;
        
        // 保存结果到文件
        save_result_to_file();
        
        // 等待一些周期后结束仿真
        #100;
        $display("\n=============== 测试完成 ===============");
        $finish;
    end
end

wire [12:0]uram_rd_addr;
wire uram_rd_en;
// 实例化TPU
tpu_top_32X32 uut (
    .clk(clk),
    .srstn(srstn),
    .tpu_start(tpu_start),
    .uram_rd_en(uram_rd_en),
    .uram_rd_addr(uram_rd_addr),
    
    .sram_rdata_w0(sram_rdata_w0), .sram_rdata_w1(sram_rdata_w1),
    .sram_rdata_w2(sram_rdata_w2), .sram_rdata_w3(sram_rdata_w3),
    .sram_rdata_w4(sram_rdata_w4), .sram_rdata_w5(sram_rdata_w5),
    .sram_rdata_w6(sram_rdata_w6), .sram_rdata_w7(sram_rdata_w7),
    
    .sram_rdata_d0(sram_rdata_d0), .sram_rdata_d1(sram_rdata_d1),
    .sram_rdata_d2(sram_rdata_d2), .sram_rdata_d3(sram_rdata_d3),
    .sram_rdata_d4(sram_rdata_d4), .sram_rdata_d5(sram_rdata_d5),
    .sram_rdata_d6(sram_rdata_d6), .sram_rdata_d7(sram_rdata_d7),
    
    .uram_write_enable(uram_write_enable),
    .uram_wdata(uram_wdata),
    .uram_wdata_addr(uram_wdata_addr),
    
    .tpu_done(tpu_done),
    .cycle_num(cycle_num),  // 13位信号
    .matrix_index(matrix_index)
);



endmodule