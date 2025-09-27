`include "macros.h"
module EXEU(
    input  wire        clk,
    input  wire        resetn,

    // Pipeline interface with ID stage
    output wire        exe_allowin,
    input  wire        id_to_exe_valid,
    input  wire [`ID2EXE_LEN - 1:0] id_to_exe_zip,

    // Pipeline interface with MEM stage
    input  wire        mem_allowin,
    output wire        exe_to_mem_valid,
    output wire [`EXE2MEM_LEN - 1:0] exe_to_mem_zip,

    // TODO: move data sram interface to exe stage
    // Data SRAM interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,

    // Data forwarding to ID stage
    output wire [38:0] exe_rf_zip      // {exe_res_from_mem, exe_rf_we, exe_rf_waddr, exe_alu_result}
);

    // Pipeline control
    wire        exe_ready_go;
    reg         exe_valid;

    reg  [31:0] exe_pc;
    reg  [11:0] exe_alu_op;
    reg  [31:0] exe_alu_src1;
    reg  [31:0] exe_alu_src2;
    reg         exe_res_from_mem;
    reg         exe_mem_we;
    reg  [31:0] exe_rkd_value;
    reg         exe_rf_we;
    reg  [ 4:0] exe_rf_waddr;

    wire [31:0] exe_alu_result;

    // Pipeline state control
    assign exe_ready_go = 1'b1;
    assign exe_allowin = ~exe_valid | (exe_ready_go & mem_allowin);
    assign exe_to_mem_valid = exe_valid & exe_ready_go;

    always @(posedge clk) begin
        if (~resetn)
            exe_valid <= 1'b0;
        else
            exe_valid <= id_to_exe_valid & exe_allowin;
    end

    // Pipeline register updates
    always @(posedge clk) begin
        if (id_to_exe_valid & exe_allowin) begin
            {exe_alu_op, exe_res_from_mem, exe_alu_src1, exe_alu_src2, exe_mem_we, exe_rf_we, exe_rf_waddr, exe_rkd_value, exe_pc} <= id_to_exe_zip;
        end
    end

    // ALU instantiation
    alu u_alu(
        .alu_op     (exe_alu_op),
        .alu_src1   (exe_alu_src1),
        .alu_src2   (exe_alu_src2),
        .alu_result (exe_alu_result)
    );

    // TODO: migrate Data SRAM interface
    // Data SRAM interface
    assign data_sram_en     = (exe_res_from_mem | exe_mem_we) & exe_valid;
    assign data_sram_we     = {4{exe_mem_we & exe_valid}};
    assign data_sram_addr   = exe_alu_result;
    assign data_sram_wdata  = exe_rkd_value;

    // TODO: Forward data to IDU
    assign exe_rf_zip = {exe_res_from_mem & exe_valid, exe_rf_we & exe_valid, exe_rf_waddr, exe_alu_result};

    // Output assignment
    assign exe_to_mem_zip = {exe_rf_zip, exe_pc};

endmodule
