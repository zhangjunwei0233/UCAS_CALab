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
            {mem_res_from_mem, mem_rf_we, mem_rf_waddr, mem_alu_result, mem_pc} <= exe_to_mem_zip;
        end
    end

    // Output assignment
    assign mem_rf_wdata = mem_res_from_mem ? data_sram_rdata : mem_alu_result;

    // Data forwarding
    assign mem_rf_zip = {mem_rf_we, mem_rf_waddr, mem_rf_wdata};

    // Pipeline output to WB stage
    assign mem_to_wb_zip = {mem_rf_we, mem_rf_waddr, mem_rf_wdata, mem_pc};

endmodule
