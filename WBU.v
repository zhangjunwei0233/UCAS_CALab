`include "macros.h"
module WBU(
    input  wire        clk,
    input  wire        resetn,

    // Pipeline interface with MEM stage
    output wire        wb_allowin,
    input  wire        mem_to_wb_valid,
    input  wire [`MEM2WB_LEN - 1:0] mem_to_wb_zip,

    // Debug trace interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,

    // Data forwarding to ID stage
    output wire [37:0] wb_rf_zip,

    // Exception/ERTN info to top
    output wire        wb_ex_valid,
    output wire [31:0] wb_ex_pc,
    output wire [5:0]  wb_ecode,
    output wire [8:0]  wb_esubcode,
    output wire        wb_is_ertn
);
    // Pipeline control
    wire        wb_ready_go;
    reg         wb_valid;

    reg         wb_rf_we;
    reg  [4 :0] wb_rf_waddr;
    reg  [31:0] wb_rf_wdata;
    reg  [31:0] wb_pc;
    // Exception pipeline fields
    reg         wb_ex_valid_r;
    reg  [5:0]  wb_ecode_r;
    reg  [8:0]  wb_esubcode_r;
    reg         wb_is_ertn_r;

    // Pipeline state control
    assign wb_ready_go = 1'b1;
    assign wb_allowin = ~wb_valid | wb_ready_go;

    always @(posedge clk) begin
        if (~resetn)
            wb_valid <= 1'b0;
        else
            wb_valid <= mem_to_wb_valid & wb_allowin;
    end

    // Pipeline register updates
    always @(posedge clk) begin
        if (mem_to_wb_valid) begin
            {wb_rf_we, wb_rf_waddr, wb_rf_wdata, wb_pc, wb_ex_valid_r, wb_ecode_r, wb_esubcode_r, wb_is_ertn_r} <= mem_to_wb_zip;
        end
    end

    // Data forwarding
    assign wb_rf_zip = {wb_valid ? (wb_rf_we & ~wb_ex_valid_r & ~wb_is_ertn_r) : 0, wb_rf_waddr, wb_rf_wdata};

    // Debug trace interface
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_we = {4{wb_rf_we & wb_valid & ~wb_ex_valid_r & ~wb_is_ertn_r}};
    assign debug_wb_rf_wnum = wb_rf_waddr;
    assign debug_wb_rf_wdata = wb_rf_wdata;

    // Exception/ERTN outputs
    assign wb_ex_valid  = wb_valid & wb_ex_valid_r;
    assign wb_ex_pc     = wb_pc;
    assign wb_ecode     = wb_ecode_r;
    assign wb_esubcode  = wb_esubcode_r;
    assign wb_is_ertn   = wb_valid & wb_is_ertn_r;
endmodule
