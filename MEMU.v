`include "macros.h"
module MEMU(
    input  wire        clk,
    input  wire        resetn,

    // Global flush from WB (exception/ertn)
    input  wire        flush,

    // Pipeline interface with EXE stage
    output wire        mem_allowin,
    input  wire        exe_to_mem_valid,
    input  wire [`EXE2MEM_LEN - 1:0] exe_to_mem_zip,

    // Pipeline interface with WB stage
    input  wire        wb_allowin,
    output wire        mem_to_wb_valid,
    output wire [`MEM2WB_LEN - 1:0] mem_to_wb_zip,

    // Data SRAM-like interface
    input  wire        data_data_ok,
    input  wire [31:0] data_rdata,

    // Data forwarding to ID stage
    output wire [39:0] mem_rf_zip,

    // Exception signal forwarding to EXE stage
    output wire        mem_ex,
    input  wire        wb_ex
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
    // CSR pipeline fields
    reg         mem_csr_read;
    reg         mem_csr_we;
    reg  [13:0] mem_csr_num;
    reg  [31:0] mem_csr_wmask;
    reg  [31:0] mem_csr_wvalue;
    // TLB pipeline fields
    reg  [2:0]  mem_tlb_op;
    reg  [4:0]  mem_invtlb_op;
    // Exception pipeline fields
    reg         mem_ex_valid;
    reg  [5:0]  mem_ecode;
    reg  [8:0]  mem_esubcode;
    reg         mem_is_ertn;
    reg  [31:0] mem_vaddr;      // Virtual address for BADV register

    wire [31:0] mem_rf_wdata;

    // Cache interface control
    wire        mem_wait_data_ok;
    reg         mem_wait_data_ok_r;

    assign mem_wait_data_ok = mem_wait_data_ok_r & mem_valid & ~wb_ex;

    // Pipeline state control
    assign mem_ready_go = ~mem_wait_data_ok | mem_wait_data_ok & data_data_ok;
    assign mem_allowin = ~mem_valid | (mem_ready_go & wb_allowin);
    assign mem_to_wb_valid = mem_valid & mem_ready_go;

    always @(posedge clk) begin
        if (~resetn)
            mem_valid <= 1'b0;
        else if (flush)
            mem_valid <= 1'b0;
        else if (mem_allowin)
            mem_valid <= exe_to_mem_valid;
    end

    // Pipeline register updates
    always @(posedge clk) begin
        if (exe_to_mem_valid & mem_allowin) begin
            {mem_wait_data_ok_r, mem_res_from_mem, mem_rf_we, mem_rf_waddr, mem_alu_result, mem_mem_op, mem_pc,
             mem_csr_read, mem_csr_we, mem_csr_num, mem_csr_wmask, mem_csr_wvalue,
             mem_vaddr,
             mem_ex_valid, mem_ecode, mem_esubcode, mem_is_ertn,
             mem_tlb_op, mem_invtlb_op} <= exe_to_mem_zip;
        end
    end

    // Exception generation (non for now)
    wire        mem_gen_ex_valid = 1'b0;
    wire [5:0]  mem_gen_ecode    = 6'd0;
    wire [8:0]  mem_gen_esubcode = 9'd0;

    wire        mem_to_wb_ex_valid = mem_gen_ex_valid ? 1'b1 : mem_ex_valid;
    wire [5:0]  mem_to_wb_ecode    = mem_gen_ex_valid ? mem_gen_ecode : mem_ecode;
    wire [8:0]  mem_to_wb_esubcode = mem_gen_ex_valid ? mem_gen_esubcode : mem_esubcode;
    wire        mem_to_wb_is_ertn  = mem_is_ertn;

    // Exception forwarding to EXE stage
    assign mem_ex = mem_valid & (mem_to_wb_ex_valid | mem_to_wb_is_ertn);

    // Output assignment
    wire addr0 = (mem_alu_result[1:0] == 2'd0);
    wire addr1 = (mem_alu_result[1:0] == 2'd1);
    wire addr2 = (mem_alu_result[1:0] == 2'd2);
    wire addr3 = (mem_alu_result[1:0] == 2'd3);
    wire [31:0] mem_data =
                // ld.b
                (mem_mem_op == 0) ?
                ( addr0 ? {{24{data_rdata[ 7]}}, data_rdata[ 7: 0]} :
                  addr1 ? {{24{data_rdata[15]}}, data_rdata[15: 8]} :
                  addr2 ? {{24{data_rdata[23]}}, data_rdata[23:16]} :
                  addr3 ? {{24{data_rdata[31]}}, data_rdata[31:24]} :
                  32'd0 ) :
                // ld.h
                (mem_mem_op == 1) ?
                ( (addr0 | addr1) ? {{16{data_rdata[15]}}, data_rdata[15: 0]} :
                  (addr2 | addr3) ? {{16{data_rdata[31]}}, data_rdata[31:16]} :
                  32'd0 ) :
                // ld.w
                (mem_mem_op == 2) ?
                ( data_rdata ) :
                // ld.bu
                (mem_mem_op == 8) ?
                ( addr0 ? {24'd0, data_rdata[ 7: 0]} :
                  addr1 ? {24'd0, data_rdata[15: 8]} :
                  addr2 ? {24'd0, data_rdata[23:16]} :
                  addr3 ? {24'd0, data_rdata[31:24]} :
                  32'd0 ) :
                // ld.hu
                (mem_mem_op == 9) ?
                ( (addr0 | addr1) ? {16'd0, data_rdata[15: 0]} :
                  (addr2 | addr3) ? {16'd0, data_rdata[31:16]} :
                  32'd0 ) :
                // default
                32'd0;
    assign mem_rf_wdata = mem_res_from_mem ? mem_data : mem_alu_result;

    // Data forwarding
    assign mem_rf_zip = {
            mem_valid & (mem_csr_read | mem_csr_we),
            mem_valid & mem_res_from_mem,
            mem_valid & mem_rf_we,
            mem_rf_waddr,
            // Note: DO NOT forward mem_rf_data, since it will cause a
            // direct logical path from data_sram to inst_sram!
            // mem_rf_wdata
            mem_alu_result
    };

    // Pipeline output to WB stage
    assign mem_to_wb_zip = {
            mem_rf_we,
            mem_rf_waddr,
            mem_rf_wdata,
            mem_pc,

            mem_csr_read,
            mem_csr_we,
            mem_csr_num,
            mem_csr_wmask,
            mem_csr_wvalue,
            
            mem_vaddr,  // vaddr for BADV register

            mem_to_wb_ex_valid,
            mem_to_wb_ecode,
            mem_to_wb_esubcode,
            mem_to_wb_is_ertn,

            mem_tlb_op,
            mem_invtlb_op
    };

endmodule
