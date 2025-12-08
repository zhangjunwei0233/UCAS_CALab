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
    output wire [38:0] wb_rf_zip,

    // Exception signal forwarding to EXE stage
    output wire        wb_ex,

    // Exception/ERTN info to top
    output wire        wb_ex_valid,
    output wire [31:0] wb_ex_pc,
    output wire [31:0] wb_vaddr,
    output wire [5:0]  wb_ecode,
    output wire [8:0]  wb_esubcode,
    output wire        wb_is_ertn,

    // CSR commit interface
    output wire        csr_we,
    output wire [13:0] csr_num,
    output wire [31:0] csr_wmask,
    output wire [31:0] csr_wvalue,
    output wire        csr_re,
    input  wire [31:0] csr_rvalue,

    // CSR helper inputs for TLB operations
    input  wire [3:0]  csr_tlbidx_index,
    input  wire [5:0]  csr_tlbidx_ps,
    input  wire        csr_tlbidx_ne,
    input  wire [18:0] csr_tlbehi_vppn,
    input  wire [31:0] csr_tlbelo0_value,
    input  wire [31:0] csr_tlbelo1_value,
    input  wire [31:0] csr_asid_value,

    // TLB read port result (for TLBRD)
    input  wire        tlb_r_e,
    input  wire [18:0] tlb_r_vppn,
    input  wire [5:0]  tlb_r_ps,
    input  wire [9:0]  tlb_r_asid,
    input  wire        tlb_r_g,
    input  wire [19:0] tlb_r_ppn0,
    input  wire [1:0]  tlb_r_plv0,
    input  wire [1:0]  tlb_r_mat0,
    input  wire        tlb_r_d0,
    input  wire        tlb_r_v0,
    input  wire [19:0] tlb_r_ppn1,
    input  wire [1:0]  tlb_r_plv1,
    input  wire [1:0]  tlb_r_mat1,
    input  wire        tlb_r_d1,
    input  wire        tlb_r_v1,

    // TLB write / TLBRD control outputs
    output wire        tlb_we,
    output wire [3:0]  tlb_w_index,
    output wire        tlb_w_e,
    output wire [18:0] tlb_w_vppn,
    output wire [5:0]  tlb_w_ps,
    output wire [9:0]  tlb_w_asid,
    output wire        tlb_w_g,
    output wire [19:0] tlb_w_ppn0,
    output wire [1:0]  tlb_w_plv0,
    output wire [1:0]  tlb_w_mat0,
    output wire        tlb_w_d0,
    output wire        tlb_w_v0,
    output wire [19:0] tlb_w_ppn1,
    output wire [1:0]  tlb_w_plv1,
    output wire [1:0]  tlb_w_mat1,
    output wire        tlb_w_d1,
    output wire        tlb_w_v1,
    output wire        csr_tlbrd_en
);
    // Pipeline control
    wire        wb_ready_go;
    reg         wb_valid;

    reg         wb_rf_we;
    reg  [4 :0] wb_rf_waddr;
    reg  [31:0] wb_rf_wdata;
    reg  [31:0] wb_pc;
    // CSR pipeline fields
    reg         wb_csr_read;
    reg         wb_csr_we;
    reg  [13:0] wb_csr_num;
    reg  [31:0] wb_csr_wmask;
    reg  [31:0] wb_csr_wvalue;
    // TLB pipeline fields
    reg  [2:0]  wb_tlb_op;
    reg  [4:0]  wb_invtlb_op;
    // Exception pipeline fields
    reg         wb_ex_valid_r;
    reg  [5:0]  wb_ecode_r;
    reg  [8:0]  wb_esubcode_r;
    reg         wb_is_ertn_r;
    reg  [31:0] wb_vaddr_r;

    // TLBFILL round-robin pointer
    reg  [3:0]  tlb_fill_ptr;

    // Pipeline state control
    assign wb_ready_go = 1'b1;
    assign wb_allowin = ~wb_valid | wb_ready_go;

    always @(posedge clk) begin
        if (~resetn)
            wb_valid <= 1'b0;
        else if (wb_ex_raw)
            wb_valid <= 1'b0;
        else
            wb_valid <= mem_to_wb_valid & wb_allowin;
    end

    // Pipeline register updates
    always @(posedge clk) begin
        if (~resetn) begin
            wb_rf_we      <= 1'b0;
            wb_rf_waddr   <= 5'd0;
            wb_rf_wdata   <= 32'd0;
            wb_pc         <= 32'd0;
            wb_csr_read   <= 1'b0;
            wb_csr_we     <= 1'b0;
            wb_csr_num    <= 14'd0;
            wb_csr_wmask  <= 32'd0;
            wb_csr_wvalue <= 32'd0;
            wb_tlb_op     <= `TLB_OP_NONE;
            wb_invtlb_op  <= 5'd0;
            wb_ex_valid_r <= 1'b0;
            wb_ecode_r    <= 6'd0;
            wb_esubcode_r <= 9'd0;
            wb_is_ertn_r  <= 1'b0;
            wb_vaddr_r    <= 32'd0;
            tlb_fill_ptr  <= 4'd0;
        end else if (wb_ex_raw) begin
            wb_ex_valid_r <= 1'b0;
            wb_ecode_r    <= 6'd0;
            wb_esubcode_r <= 9'd0;
            wb_is_ertn_r  <= 1'b0;
            wb_vaddr_r    <= 32'd0;
        end else if (mem_to_wb_valid) begin
            {wb_rf_we, wb_rf_waddr, wb_rf_wdata, wb_pc,
             wb_csr_read, wb_csr_we, wb_csr_num, wb_csr_wmask, wb_csr_wvalue,
             wb_vaddr_r,
             wb_ex_valid_r, wb_ecode_r, wb_esubcode_r, wb_is_ertn_r,
             wb_tlb_op, wb_invtlb_op} <= mem_to_wb_zip;
        end
    end

    // Exception generation (non for now)
    wire        wb_gen_ex_valid = 1'b0;
    wire [5:0]  wb_gen_ecode    = 6'd0;
    wire [8:0]  wb_gen_esubcode = 9'd0;

    wire        wb_ex_raw = wb_ex_valid_r | wb_is_ertn_r | wb_gen_ex_valid;
    wire        wb_forward_ok = wb_valid & ~wb_ex_raw;

    // TLB helper signals
    wire wb_do_tlbrd   = wb_forward_ok & (wb_tlb_op == `TLB_OP_RD);
    wire wb_do_tlbwr   = wb_forward_ok & (wb_tlb_op == `TLB_OP_WR);
    wire wb_do_tlbfill = wb_forward_ok & (wb_tlb_op == `TLB_OP_FILL);
    wire tlbelo0_v     = csr_tlbelo0_value[`CSR_TLBELO_V];
    wire tlbelo0_d     = csr_tlbelo0_value[`CSR_TLBELO_D];
    wire [1:0] tlbelo0_plv = csr_tlbelo0_value[`CSR_TLBELO_PLV];
    wire [1:0] tlbelo0_mat = csr_tlbelo0_value[`CSR_TLBELO_MAT];
    wire tlbelo0_g     = csr_tlbelo0_value[`CSR_TLBELO_G];
    wire [19:0] tlbelo0_ppn = csr_tlbelo0_value[`CSR_TLBELO_PPN];
    wire tlbelo1_v     = csr_tlbelo1_value[`CSR_TLBELO_V];
    wire tlbelo1_d     = csr_tlbelo1_value[`CSR_TLBELO_D];
    wire [1:0] tlbelo1_plv = csr_tlbelo1_value[`CSR_TLBELO_PLV];
    wire [1:0] tlbelo1_mat = csr_tlbelo1_value[`CSR_TLBELO_MAT];
    wire tlbelo1_g     = csr_tlbelo1_value[`CSR_TLBELO_G];
    wire [19:0] tlbelo1_ppn = csr_tlbelo1_value[`CSR_TLBELO_PPN];
    wire tlb_w_g_int   = tlbelo0_g & tlbelo1_g;
    wire [9:0] csr_asid_asid = csr_asid_value[`CSR_ASID_ASID];

    // TLBFILL pointer update
    always @(posedge clk) begin
        if (~resetn)
            tlb_fill_ptr <= 4'd0;
        else if (wb_do_tlbfill)
            tlb_fill_ptr <= tlb_fill_ptr + 1'b1;
    end

    // Exception forwarding to EXE stage
    assign wb_ex = wb_valid & wb_ex_raw;

    // Data forwarding
    wire [31:0] wb_wdata_final = wb_csr_read ? csr_rvalue : wb_rf_wdata;
    assign wb_rf_zip = {
            wb_csr_read,
            wb_forward_ok ? wb_rf_we : 1'b0,
            wb_rf_waddr,
            wb_wdata_final
    };

    // Debug trace interface
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_we = {4{wb_rf_we & wb_forward_ok}};
    assign debug_wb_rf_wnum = wb_rf_waddr;
    assign debug_wb_rf_wdata = wb_wdata_final;

    // CSR commit signals
    assign csr_re     = wb_csr_read;
    assign csr_we     = wb_forward_ok & wb_csr_we;
    assign csr_num    = wb_csr_num;
    assign csr_wmask  = wb_csr_wmask;
    assign csr_wvalue = wb_csr_wvalue;

    // TLB write / read control
    assign csr_tlbrd_en = wb_do_tlbrd;
    assign tlb_we       = wb_do_tlbwr | wb_do_tlbfill;
    assign tlb_w_index  = (wb_tlb_op == `TLB_OP_FILL) ? tlb_fill_ptr : csr_tlbidx_index;
    assign tlb_w_e      = ~csr_tlbidx_ne;
    assign tlb_w_vppn   = csr_tlbehi_vppn;
    assign tlb_w_ps     = csr_tlbidx_ps;
    assign tlb_w_asid   = csr_asid_asid;
    assign tlb_w_g      = tlb_w_g_int;
    assign tlb_w_ppn0   = tlbelo0_ppn;
    assign tlb_w_plv0   = tlbelo0_plv;
    assign tlb_w_mat0   = tlbelo0_mat;
    assign tlb_w_d0     = tlbelo0_d;
    assign tlb_w_v0     = tlbelo0_v;
    assign tlb_w_ppn1   = tlbelo1_ppn;
    assign tlb_w_plv1   = tlbelo1_plv;
    assign tlb_w_mat1   = tlbelo1_mat;
    assign tlb_w_d1     = tlbelo1_d;
    assign tlb_w_v1     = tlbelo1_v;

    // Exception/ERTN outputs
    assign wb_ex_valid  = wb_valid & (wb_ex_valid_r | wb_gen_ex_valid);
    assign wb_ex_pc     = wb_pc;
    assign wb_vaddr     = wb_vaddr_r;
    assign wb_ecode     = wb_gen_ex_valid ? wb_gen_ecode : wb_ecode_r;
    assign wb_esubcode  = wb_gen_ex_valid ? wb_gen_esubcode : wb_esubcode_r;
    assign wb_is_ertn   = wb_valid & wb_is_ertn_r;
endmodule
