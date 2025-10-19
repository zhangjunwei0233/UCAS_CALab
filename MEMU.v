`include "macros.h"
module MEMU(
    input  wire        clk,
    input  wire        resetn,

    // Pipeline interface with EXE stage
    output wire        mem_allowin,
    input  wire        exe_to_mem_valid,
    input  wire [`EXE2MEM_LEN - 1:0] exe_to_mem_zip,

    // Pipeline interface with WB stage
    input  wire        wb_allowin,
    output wire        mem_to_wb_valid,
    output wire [`MEM2WB_LEN - 1:0] mem_to_wb_zip,

    // Data SRAM interface
    input  wire [31:0] data_sram_rdata,

    // Data forwarding to ID stage
    output wire [37:0] mem_rf_zip
);
    // Pipeline control
    wire        mem_ready_go;
    reg         mem_valid;
    
    reg  [31:0] mem_pc;
    reg         mem_res_from_mem;
    reg         mem_rf_we;
    reg  [3 :0] mem_mem_op;
    reg  [4 :0] mem_rf_waddr;
    reg  [31:0] mem_alu_result;

    wire [31:0] mem_rf_wdata;

    // Pipeline state control
    assign mem_ready_go = 1'b1;
    assign mem_allowin = ~mem_valid | (mem_ready_go & wb_allowin);
    assign mem_to_wb_valid = mem_valid & mem_ready_go;

    always @(posedge clk) begin
        if (~resetn)
            mem_valid <= 1'b0;
        else
            mem_valid <= exe_to_mem_valid & mem_allowin;
    end

    // Pipeline register updates
    always @(posedge clk) begin
        if (exe_to_mem_valid & mem_allowin) begin
            {mem_res_from_mem, mem_rf_we, mem_rf_waddr, mem_alu_result, mem_mem_op, mem_pc} <= exe_to_mem_zip;
        end
    end

    // Output assignment
    wire addr0 = (mem_alu_result[1:0] == 2'd0);
    wire addr1 = (mem_alu_result[1:0] == 2'd1);
    wire addr2 = (mem_alu_result[1:0] == 2'd2);
    wire addr3 = (mem_alu_result[1:0] == 2'd3);
    wire [31:0] mem_data =
                // ld.b
                (mem_mem_op == 0) ?
                ( addr0 ? {{24{data_sram_rdata[ 7]}}, data_sram_rdata[ 7: 0]} :
                  addr1 ? {{24{data_sram_rdata[15]}}, data_sram_rdata[15: 8]} :
                  addr2 ? {{24{data_sram_rdata[23]}}, data_sram_rdata[23:16]} :
                  addr3 ? {{24{data_sram_rdata[31]}}, data_sram_rdata[31:24]} :
                  32'd0 ) :
                // ld.h
                (mem_mem_op == 1) ?
                ( (addr0 | addr1) ? {{16{data_sram_rdata[15]}}, data_sram_rdata[15: 0]} :
                  (addr2 | addr3) ? {{16{data_sram_rdata[31]}}, data_sram_rdata[31:16]} :
                  32'd0 ) :
                // ld.w
                (mem_mem_op == 2) ?
                ( data_sram_rdata ) :
                // ld.bu
                (mem_mem_op == 8) ?
                ( addr0 ? {24'd0, data_sram_rdata[ 7: 0]} :
                  addr1 ? {24'd0, data_sram_rdata[15: 8]} :
                  addr2 ? {24'd0, data_sram_rdata[23:16]} :
                  addr3 ? {24'd0, data_sram_rdata[31:24]} :
                  32'd0 ) :
                // ld.hu
                (mem_mem_op == 9) ?
                ( (addr0 | addr1) ? {16'd0, data_sram_rdata[15: 0]} :
                  (addr2 | addr3) ? {16'd0, data_sram_rdata[31:16]} :
                  32'd0 ) :
                // default
                32'd0;
    assign mem_rf_wdata = mem_res_from_mem ? mem_data : mem_alu_result;

    // Data forwarding
    assign mem_rf_zip = {mem_valid ? mem_rf_we : 0, mem_rf_waddr, mem_rf_wdata};

    // Pipeline output to WB stage
    assign mem_to_wb_zip = {mem_rf_we, mem_rf_waddr, mem_rf_wdata, mem_pc};

endmodule
