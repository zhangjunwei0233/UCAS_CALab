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
    reg  [ 3:0] exe_mem_op;
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
            {exe_alu_op, exe_res_from_mem, exe_alu_src1, exe_alu_src2, exe_mem_op, exe_rf_we, exe_rf_waddr, exe_rkd_value, exe_pc} <= id_to_exe_zip;
        end
    end

    // ALU instantiation
    alu u_alu(
        .alu_op     (exe_alu_op),
        .alu_src1   (exe_alu_src1),
        .alu_src2   (exe_alu_src2),
        .alu_result (exe_alu_result)
    );

    // Data SRAM interface
    wire addr0 = (exe_alu_result[1:0] == 2'd0);
    wire addr1 = (exe_alu_result[1:0] == 2'd1);
    wire addr2 = (exe_alu_result[1:0] == 2'd2);
    wire addr3 = (exe_alu_result[1:0] == 2'd3);
    assign data_sram_en     = (exe_res_from_mem | exe_mem_op[2]) & exe_valid;
    assign data_sram_we     = // st.b
                              (exe_mem_op == 4) ?
                              ( addr0 ? 4'b0001 :
                                addr1 ? 4'b0010 :
                                addr2 ? 4'b0100 :
                                addr3 ? 4'b1000 :
                                4'b0000) :
                              // st.h
                              (exe_mem_op == 5) ?
                              ( (addr0 | addr1) ? 4'b0011 :
                                (addr2 | addr3) ? 4'b1100 :
                                4'b0000 ) :
                              // st.w
                              (exe_mem_op == 6) ?
                              ( 4'b1111 ) :
                              4'b0;
    assign data_sram_addr   = exe_alu_result & ~32'd3; // Alignment
    assign data_sram_wdata  = // st.b
                              (exe_mem_op == 4) ?
                              ( addr0 ? {24'd0, exe_rkd_value[7:0]       } :
                                addr1 ? {16'd0, exe_rkd_value[7:0],  8'd0} :
                                addr2 ? { 8'd0, exe_rkd_value[7:0], 16'd0} :
                                addr3 ? {       exe_rkd_value[7:0], 24'd0} :
                                32'd0 ) :
                              // st.h
                              (exe_mem_op == 5) ?
                              ( (addr0 | addr1) ? {16'd0, exe_rkd_value[15:0]} :
                                (addr2 | addr3) ? {exe_rkd_value[15:0], 16'd0} :
                                32'd0 ) :
                              // st.w
                              (exe_mem_op == 6) ?
                              ( exe_rkd_value ) :
                              // default
                              32'd0;

    // Forward data to IDU
    assign exe_rf_zip = {exe_valid & exe_res_from_mem, exe_valid & exe_rf_we, exe_rf_waddr, exe_alu_result};

    // Output assignment
    //                       39          4           32
    assign exe_to_mem_zip = {exe_rf_zip, exe_mem_op, exe_pc};

endmodule
