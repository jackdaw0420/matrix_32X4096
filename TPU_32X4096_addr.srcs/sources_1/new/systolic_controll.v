//-----controller for systolic array----

module systolic_controll#(
	parameter ARRAY_SIZE = 32
)
(
	input clk,
	input srstn,
	input tpu_start,																//total enable signal
	
	output reg sram_write_enable,

	//addr_sel
	output reg [6:0] addr_serial_num,

	//systolic array
	output reg alu_start,																//shift & multiplcation start
	output reg [20:0] cycle_num,													//for systolic.v
	output reg [5:0] matrix_index,													//index for write-out SRAM data
	output reg [1:0] data_set,

	output reg tpu_done														//done signal
);
localparam DIAGONAL_NUM = 2*ARRAY_SIZE -1;
localparam IDLE = 3'd0, LOAD_DATA = 3'd1, WAIT1 = 3'd2, ROLLING = 3'd3;

//----general variable----
reg [2:0] state;
reg [2:0] state_nx;

reg [1:0] data_set_nx;

reg tpu_done_nx;

//----addr_sel----
reg [6:0] addr_serial_num_nx;

//----systolic array----
reg [20:0] cycle_num_nx;
reg [5:0] matrix_index_nx;

//----initialization----
always@(posedge clk) begin
	if(~srstn) begin
		state <= IDLE;
		data_set <= 0;
		cycle_num <= 0;
		matrix_index <= 0;
		addr_serial_num <= 0;
		tpu_done <= 0;
	end
	else begin
		state <= state_nx;
		data_set <= data_set_nx;
		cycle_num <= cycle_num_nx;
		matrix_index <= matrix_index_nx;
		addr_serial_num <= addr_serial_num_nx;
		tpu_done <= tpu_done_nx;
	end
end

//----state transition, tpu_done signal----
always@(*) begin
	case(state) 
		IDLE:	 begin
			if(tpu_start)
				state_nx = LOAD_DATA;
			else
				state_nx = IDLE;
			tpu_done_nx = 0;
		end

		LOAD_DATA: begin
			state_nx = WAIT1;
			tpu_done_nx = 0;
		end

		WAIT1: begin
			state_nx = ROLLING;
			tpu_done_nx = 0;
		end

		ROLLING: begin
			if(cycle_num == 21'd524350) begin
			    //cycle_num_nx = 13'd0;
				state_nx = IDLE;
				tpu_done_nx = 1;
			end
			else begin
				state_nx = ROLLING;
				tpu_done_nx = 0;
			end
		end
		default: begin
			state_nx = IDLE;
			tpu_done_nx = 0;
		end
	endcase
end

//-----addr_sel: addr_serial_num-----
always@(*) begin
	case(state)
		IDLE: begin
			if(tpu_start)
				addr_serial_num_nx = 0;
			else
				addr_serial_num_nx = addr_serial_num;
		end
		LOAD_DATA:
			addr_serial_num_nx = 1;
		WAIT1: 
			addr_serial_num_nx = 2;
		ROLLING: begin
			if(addr_serial_num == 127)
				addr_serial_num_nx = addr_serial_num;
			else
				addr_serial_num_nx = addr_serial_num + 1;
		end
		default:
			addr_serial_num_nx = 0;
	endcase
end

//------systolic: alu_start, cycle_num, matrix_index, data_set,
//sram_write_enable------
always@(*) begin
	case(state)
		IDLE: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end
		LOAD_DATA: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end
		WAIT1: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end
		ROLLING: begin
			alu_start = 1;
			cycle_num_nx = cycle_num + 1;
			if(cycle_num >= ARRAY_SIZE+1) begin
				if(matrix_index == DIAGONAL_NUM-1) begin
					matrix_index_nx = 0;
				end
				else if(cycle_num == 21'd524350)//524350 = 4096 *128 + 62. 当cycle_num等于4096时，第一个数据（0，0）在matrix_mul_2D_nx中计算完成
			        cycle_num_nx = 21'd0;
				else if((cycle_num >= 21'd4097) && ((cycle_num - 21'd4097) % 21'd4096 >= 0) && ((cycle_num - 21'd4097) % 21'd4096 <= DIAGONAL_NUM-1))begin
				    matrix_index_nx = matrix_index + 1;
				end
				sram_write_enable = 1;
			end
			else begin
				matrix_index_nx = 0;
				data_set_nx = data_set;
				sram_write_enable = 0;
			end
		end
		default: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end
		
	endcase
end

endmodule

