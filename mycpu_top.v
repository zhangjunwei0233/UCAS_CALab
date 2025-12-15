`include "macros.h"
module mycpu_top
  ( // AXI
    input wire         aclk,
    input wire         aresetn,
    // AR
    output wire [3:0]  arid,
    output wire [31:0] araddr,
    output wire [7:0]  arlen,
    output wire [2:0]  arsize,
    output wire [1:0]  arburst,
    output wire [1:0]  arlock,
    output wire [3:0]  arcache,
    output wire [2:0]  arprot,
    output wire        arvalid,
    input wire         arready,
    // R
    input wire [3:0]   rid,
    input wire [31:0]  rdata,
    input wire [1:0]   rresp,
    input wire         rlast,
    input wire         rvalid,
    output wire        rready,
    // AW
    output wire [3:0]  awid,
    output wire [31:0] awaddr,
    output wire [7:0]  awlen,
    output wire [2:0]  awsize,
    output wire [1:0]  awburst,
    output wire [1:0]  awlock,
    output wire [3:0]  awcache,
    output wire [2:0]  awprot,
    output wire        awvalid,
    input wire         awready,
    // W
    output wire [3:0]  wid,
    output wire [31:0] wdata,
    output wire [3:0]  wstrb,
    output wire        wlast,
    output wire        wvalid,
    input wire         wready,
    // B
    input wire [3:0]   bid,
    input wire [1:0]   bresp,
    input wire         bvalid,
    output wire        bready,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    wire        id_allowin;
    wire        exe_allowin;
    wire        mem_allowin;
    wire        wb_allowin;

    wire        if_to_id_valid;
    wire        id_to_exe_valid;
    wire        exe_to_mem_valid;
    wire        mem_to_wb_valid;

    // Pipline interface
    wire [`IF2ID_LEN   - 1:0]   if_to_id_zip;
    wire [`ID2EXE_LEN  - 1:0]   id_to_exe_zip;
    wire [`EXE2MEM_LEN - 1:0]   exe_to_mem_zip;
    wire [`MEM2WB_LEN  - 1:0]   mem_to_wb_zip;

    // Data forwarding
    wire [38:0] wb_rf_zip;
    wire [39:0] mem_rf_zip;
    wire [39:0] exe_rf_zip;

    // Exception Signal forwarding
    wire        wb_ex;
    wire        mem_ex;

    // Brach resolving
    wire        br_stall;
    wire        br_taken;
    wire [31:0] br_target;

    // Global flush (exception/ertn)
    wire        flush;
    wire [31:0] flush_target;

    // CSR interface
    wire [31:0] csr_ex_entry;
    wire [31:0] csr_era;
    wire        has_int;
    wire        csr_re;
    wire [13:0] csr_num;
    wire [31:0] csr_rvalue;
    wire        csr_we;
    wire [31:0] csr_wmask;
    wire [31:0] csr_wvalue;

    // TLB related CSR helper wires
    wire [3:0]  csr_tlbidx_index;
    wire [5:0]  csr_tlbidx_ps;
    wire        csr_tlbidx_ne;
    wire [18:0] csr_tlbehi_vppn;
    wire [31:0] csr_tlbelo0_value;
    wire [31:0] csr_tlbelo1_value;
    wire [31:0] csr_asid_value;
    wire [31:0] csr_tlbidx_value;
    wire [31:0] csr_tlbehi_value;
    wire [31:0] csr_tlbren_value;

    wire [9:0] csr_asid_asid = csr_asid_value[9:0];

    // WBU exception/ertn info
    wire        wb_ex_valid;
    wire [31:0] wb_ex_pc;
    wire [31:0] wb_vaddr;
    wire [5:0]  wb_ecode;
    wire [8:0]  wb_esubcode;
    wire        wb_is_ertn;

    // TLB interface wires
    wire        tlb_invtlb_valid;
    wire [4:0]  tlb_invtlb_op;
    wire        tlb_r_e;
    wire [18:0] tlb_r_vppn;
    wire [5:0]  tlb_r_ps;
    wire [9:0]  tlb_r_asid;
    wire        tlb_r_g;
    wire [19:0] tlb_r_ppn0;
    wire [1:0]  tlb_r_plv0;
    wire [1:0]  tlb_r_mat0;
    wire        tlb_r_d0;
    wire        tlb_r_v0;
    wire [19:0] tlb_r_ppn1;
    wire [1:0]  tlb_r_plv1;
    wire [1:0]  tlb_r_mat1;
    wire        tlb_r_d1;
    wire        tlb_r_v1;
    wire        tlb_we;
    wire [3:0]  tlb_w_index;
    wire        tlb_w_e;
    wire [18:0] tlb_w_vppn;
    wire [5:0]  tlb_w_ps;
    wire [9:0]  tlb_w_asid;
    wire        tlb_w_g;
    wire [19:0] tlb_w_ppn0;
    wire [1:0]  tlb_w_plv0;
    wire [1:0]  tlb_w_mat0;
    wire        tlb_w_d0;
    wire        tlb_w_v0;
    wire [19:0] tlb_w_ppn1;
    wire [1:0]  tlb_w_plv1;
    wire [1:0]  tlb_w_mat1;
    wire        tlb_w_d1;
    wire        tlb_w_v1;
    wire        csr_tlbrd_en;

    wire                clk;                    // From my_bridge of bridge.v
    wire [31:0]         data_sram_addr;         // From my_exeu of EXEU.v
    wire                data_sram_addr_ok;      // From my_bridge of bridge.v
    wire                data_sram_data_ok;      // From my_bridge of bridge.v
    wire [31:0]         data_sram_rdata;        // From my_bridge of bridge.v
    wire                data_sram_req;          // From my_exeu of EXEU.v
    wire [1:0]          data_sram_size;         // From my_exeu of EXEU.v
    wire [31:0]         data_sram_wdata;        // From my_exeu of EXEU.v
    wire                data_sram_wr;           // From my_exeu of EXEU.v
    wire [3:0]          data_sram_wstrb;        // From my_exeu of EXEU.v
    wire [31:0]         inst_sram_addr;         // From my_ifu of IFU.v
    wire                inst_sram_addr_ok;      // From my_bridge of bridge.v
    wire                inst_sram_data_ok;      // From my_bridge of bridge.v
    wire [31:0]         inst_sram_rdata;        // From my_bridge of bridge.v
    wire                inst_sram_req;          // From my_ifu of IFU.v
    wire [1:0]          inst_sram_size;         // From my_ifu of IFU.v
    wire [31:0]         inst_sram_wdata;        // From my_ifu of IFU.v
    wire                inst_sram_wr;           // From my_ifu of IFU.v
    wire [3:0]          inst_sram_wstrb;        // From my_ifu of IFU.v
    wire                resetn;                 // From my_bridge of bridge.v

    wire [9:0]          s0_asid;                // From my_ifu of IFU.v
    wire                s0_d;                   // From u_tlb of tlb.v
    wire                s0_found;               // From u_tlb of tlb.v
    wire [3:0]          s0_index;               // From u_tlb of tlb.v
    wire [1:0]          s0_mat;                 // From u_tlb of tlb.v
    wire [1:0]          s0_plv;                 // From u_tlb of tlb.v
    wire [19:0]         s0_ppn;                 // From u_tlb of tlb.v
    wire [5:0]          s0_ps;                  // From u_tlb of tlb.v
    wire                s0_v;                   // From u_tlb of tlb.v
    wire                s0_va_bit12;            // From my_ifu of IFU.v
    wire [18:0]         s0_vppn;                // From my_ifu of IFU.v
    wire [9:0]          s1_asid;                // From my_exeu of EXEU.v
    wire                s1_d;                   // From u_tlb of tlb.v
    wire                s1_found;               // From u_tlb of tlb.v
    wire [3:0]          s1_index;               // From u_tlb of tlb.v
    wire [1:0]          s1_mat;                 // From u_tlb of tlb.v
    wire [1:0]          s1_plv;                 // From u_tlb of tlb.v
    wire [19:0]         s1_ppn;                 // From u_tlb of tlb.v
    wire [5:0]          s1_ps;                  // From u_tlb of tlb.v
    wire                s1_v;                   // From u_tlb of tlb.v
    wire                s1_va_bit12;            // From my_exeu of EXEU.v
    wire [18:0]         s1_vppn;                // From my_exeu of EXEU.v
    wire                csr_crmd_da_value;      // From u_csr of CSR.v
    wire                csr_crmd_pg_value;      // From u_csr of CSR.v
    wire [1:0]          csr_crmd_plv_value;     // From u_csr of CSR.v
    wire [31:0]         csr_dmw0_value;         // From u_csr of CSR.v
    wire [31:0]         csr_dmw1_value;         // From u_csr of CSR.v
    
    bridge my_bridge(
        // Outputs
        .clk               (clk),
        .resetn            (resetn),
        .inst_sram_addr_ok (inst_sram_addr_ok),
        .inst_sram_data_ok (inst_sram_data_ok),
        .inst_sram_rdata   (inst_sram_rdata[31:0]),
        .data_sram_addr_ok (data_sram_addr_ok),
        .data_sram_data_ok (data_sram_data_ok),
        .data_sram_rdata   (data_sram_rdata[31:0]),
        .arid              (arid[3:0]),
        .araddr            (araddr[31:0]),
        .arlen             (arlen[7:0]),
        .arsize            (arsize[2:0]),
        .arburst           (arburst[1:0]),
        .arlock            (arlock[1:0]),
        .arcache           (arcache[3:0]),
        .arprot            (arprot[2:0]),
        .arvalid           (arvalid),
        .rready            (rready),
        .awid              (awid[3:0]),
        .awaddr            (awaddr[31:0]),
        .awlen             (awlen[7:0]),
        .awsize            (awsize[2:0]),
        .awburst           (awburst[1:0]),
        .awlock            (awlock[1:0]),
        .awcache           (awcache[3:0]),
        .awprot            (awprot[2:0]),
        .awvalid           (awvalid),
        .wid               (wid[3:0]),
        .wdata             (wdata[31:0]),
        .wstrb             (wstrb[3:0]),
        .wlast             (wlast),
        .wvalid            (wvalid),
        .bready            (bready),
        // Inputs
        .inst_sram_req     (inst_sram_req),
        .inst_sram_wr      (inst_sram_wr),
        .inst_sram_size    (inst_sram_size[1:0]),
        .inst_sram_addr    (inst_sram_addr[31:0]),
        .inst_sram_wstrb   (inst_sram_wstrb[3:0]),
        .inst_sram_wdata   (inst_sram_wdata[31:0]),
        .data_sram_req     (data_sram_req),
        .data_sram_wr      (data_sram_wr),
        .data_sram_size    (data_sram_size[1:0]),
        .data_sram_addr    (data_sram_addr[31:0]),
        .data_sram_wstrb   (data_sram_wstrb[3:0]),
        .data_sram_wdata   (data_sram_wdata[31:0]),
        .aclk              (aclk),
        .aresetn           (aresetn),
        .arready           (arready),
        .rid               (rid[3:0]),
        .rdata             (rdata[31:0]),
        .rresp             (rresp[1:0]),
        .rlast             (rlast),
        .rvalid            (rvalid),
        .awready           (awready),
        .wready            (wready),
        .bid               (bid[3:0]),
        .bresp             (bresp[1:0]),
        .bvalid            (bvalid));

    IFU my_ifu(/*AUTOINST*/
               // Outputs
               .inst_sram_req           (inst_sram_req),
               .inst_sram_wr            (inst_sram_wr),
               .inst_sram_size          (inst_sram_size[1:0]),
               .inst_sram_addr          (inst_sram_addr[31:0]),
               .inst_sram_wstrb         (inst_sram_wstrb[3:0]),
               .inst_sram_wdata         (inst_sram_wdata[31:0]),
               .s0_vppn                 (s0_vppn[18:0]),
               .s0_va_bit12             (s0_va_bit12),
               .s0_asid                 (s0_asid[9:0]),
               .if_to_id_valid          (if_to_id_valid),
               .if_to_id_zip            (if_to_id_zip[`IF2ID_LEN-1:0]),
               // Inputs
               .clk                     (clk),
               .resetn                  (resetn),
               .flush                   (flush),
               .flush_target            (flush_target[31:0]),
               .inst_sram_addr_ok       (inst_sram_addr_ok),
               .inst_sram_data_ok       (inst_sram_data_ok),
               .inst_sram_rdata         (inst_sram_rdata[31:0]),
               .s0_found                (s0_found),
               .s0_index                (s0_index[3:0]),
               .s0_ppn                  (s0_ppn[19:0]),
               .s0_ps                   (s0_ps[5:0]),
               .s0_plv                  (s0_plv[1:0]),
               .s0_mat                  (s0_mat[1:0]),
               .s0_d                    (s0_d),
               .s0_v                    (s0_v),
               .csr_asid_asid           (csr_asid_asid[9:0]),
               .csr_crmd_da_value       (csr_crmd_da_value),
               .csr_crmd_pg_value       (csr_crmd_pg_value),
               .csr_crmd_plv_value      (csr_crmd_plv_value),
               .csr_dmw0_value          (csr_dmw0_value[31:0]),
               .csr_dmw1_value          (csr_dmw1_value[31:0]),
               .id_allowin              (id_allowin),
               .br_stall                (br_stall),
               .br_taken                (br_taken),
               .br_target               (br_target[31:0]));

    IDU my_idu(/*AUTOINST*/
               // Outputs
               .id_allowin              (id_allowin),
               .br_stall                (br_stall),
               .br_taken                (br_taken),
               .br_target               (br_target[31:0]),
               .id_to_exe_valid         (id_to_exe_valid),
               .id_to_exe_zip           (id_to_exe_zip[`ID2EXE_LEN-1:0]),
               // Inputs
               .clk                     (clk),
               .resetn                  (resetn),
               .flush                   (flush),
               .has_int                 (has_int),
               .if_to_id_valid          (if_to_id_valid),
               .if_to_id_zip            (if_to_id_zip[`IF2ID_LEN-1:0]),
               .exe_allowin             (exe_allowin),
               .wb_rf_zip               (wb_rf_zip[38:0]),
               .mem_rf_zip              (mem_rf_zip[39:0]),
               .exe_rf_zip              (exe_rf_zip[39:0]));

    EXEU my_exeu(/*AUTOINST*/
                 // Outputs
                 .exe_allowin           (exe_allowin),
                 .exe_to_mem_valid      (exe_to_mem_valid),
                 .exe_to_mem_zip        (exe_to_mem_zip[`EXE2MEM_LEN-1:0]),
                 .data_sram_req         (data_sram_req),
                 .data_sram_wr          (data_sram_wr),
                 .data_sram_size        (data_sram_size[1:0]),
                 .data_sram_addr        (data_sram_addr[31:0]),
                 .data_sram_wstrb       (data_sram_wstrb[3:0]),
                 .data_sram_wdata       (data_sram_wdata[31:0]),
                 .exe_rf_zip            (exe_rf_zip[39:0]),
                 .s1_vppn               (s1_vppn[18:0]),
                 .s1_va_bit12           (s1_va_bit12),
                 .s1_asid               (s1_asid[9:0]),
                 .tlb_invtlb_valid      (tlb_invtlb_valid),
                 .tlb_invtlb_op         (tlb_invtlb_op[4:0]),
                 // Inputs
                 .clk                   (clk),
                 .resetn                (resetn),
                 .flush                 (flush),
                 .id_to_exe_valid       (id_to_exe_valid),
                 .id_to_exe_zip         (id_to_exe_zip[`ID2EXE_LEN-1:0]),
                 .mem_allowin           (mem_allowin),
                 .data_sram_addr_ok     (data_sram_addr_ok),
                 .mem_ex                (mem_ex),
                 .wb_ex                 (wb_ex),
                 .csr_tlbehi_vppn       (csr_tlbehi_vppn[18:0]),
                 .csr_asid_asid         (csr_asid_asid[9:0]),
                 .csr_crmd_da_value     (csr_crmd_da_value),
                 .csr_crmd_pg_value     (csr_crmd_pg_value),
                 .csr_crmd_plv_value    (csr_crmd_plv_value[1:0]),
                 .csr_dmw0_value        (csr_dmw0_value[31:0]),
                 .csr_dmw1_value        (csr_dmw1_value[31:0]),
                 .s1_found              (s1_found),
                 .s1_index              (s1_index[3:0]),
                 .s1_ppn                (s1_ppn[19:0]),
                 .s1_ps                 (s1_ps[5:0]),
                 .s1_plv                (s1_plv[1:0]),
                 .s1_mat                (s1_mat[1:0]),
                 .s1_d                  (s1_d),
                 .s1_v                  (s1_v));

    MEMU my_memu(/*AUTOINST*/
                 // Outputs
                 .mem_allowin           (mem_allowin),
                 .mem_to_wb_valid       (mem_to_wb_valid),
                 .mem_to_wb_zip         (mem_to_wb_zip[`MEM2WB_LEN-1:0]),
                 .mem_rf_zip            (mem_rf_zip[39:0]),
                 .mem_ex                (mem_ex),
                 // Inputs
                 .clk                   (clk),
                 .resetn                (resetn),
                 .flush                 (flush),
                 .exe_to_mem_valid      (exe_to_mem_valid),
                 .exe_to_mem_zip        (exe_to_mem_zip[`EXE2MEM_LEN-1:0]),
                 .wb_allowin            (wb_allowin),
                 .data_sram_data_ok     (data_sram_data_ok),
                 .data_sram_rdata       (data_sram_rdata[31:0]),
                 .wb_ex                 (wb_ex)); 

    WBU my_wbu(/*AUTOINST*/
               // Outputs
               .wb_allowin              (wb_allowin),
               .debug_wb_pc             (debug_wb_pc[31:0]),
               .debug_wb_rf_we          (debug_wb_rf_we[3:0]),
               .debug_wb_rf_wnum        (debug_wb_rf_wnum[4:0]),
               .debug_wb_rf_wdata       (debug_wb_rf_wdata[31:0]),
               .wb_rf_zip               (wb_rf_zip[38:0]),
               .wb_ex                   (wb_ex),
               .wb_ex_valid             (wb_ex_valid),
               .wb_ex_pc                (wb_ex_pc[31:0]),
               .wb_vaddr                (wb_vaddr[31:0]),
               .wb_ecode                (wb_ecode[5:0]),
               .wb_esubcode             (wb_esubcode[8:0]),
               .wb_is_ertn              (wb_is_ertn),
               .csr_we                  (csr_we),
               .csr_num                 (csr_num[13:0]),
               .csr_wmask               (csr_wmask[31:0]),
               .csr_wvalue              (csr_wvalue[31:0]),
               .csr_re                  (csr_re),
               .tlb_we                  (tlb_we),
               .tlb_w_index             (tlb_w_index[3:0]),
               .tlb_w_e                 (tlb_w_e),
               .tlb_w_vppn              (tlb_w_vppn[18:0]),
               .tlb_w_ps                (tlb_w_ps[5:0]),
               .tlb_w_asid              (tlb_w_asid[9:0]),
               .tlb_w_g                 (tlb_w_g),
               .tlb_w_ppn0              (tlb_w_ppn0[19:0]),
               .tlb_w_plv0              (tlb_w_plv0[1:0]),
               .tlb_w_mat0              (tlb_w_mat0[1:0]),
               .tlb_w_d0                (tlb_w_d0),
               .tlb_w_v0                (tlb_w_v0),
               .tlb_w_ppn1              (tlb_w_ppn1[19:0]),
               .tlb_w_plv1              (tlb_w_plv1[1:0]),
               .tlb_w_mat1              (tlb_w_mat1[1:0]),
               .tlb_w_d1                (tlb_w_d1),
               .tlb_w_v1                (tlb_w_v1),
               .csr_tlbrd_en            (csr_tlbrd_en),
               // Inputs
               .clk                     (clk),
               .resetn                  (resetn),
               .mem_to_wb_valid         (mem_to_wb_valid),
               .mem_to_wb_zip           (mem_to_wb_zip[`MEM2WB_LEN-1:0]),
               .csr_rvalue              (csr_rvalue[31:0]),
               .csr_tlbidx_index        (csr_tlbidx_index[3:0]),
               .csr_tlbidx_ps           (csr_tlbidx_ps[5:0]),
               .csr_tlbidx_ne           (csr_tlbidx_ne),
               .csr_tlbehi_vppn         (csr_tlbehi_vppn[18:0]),
               .csr_tlbelo0_value       (csr_tlbelo0_value[31:0]),
               .csr_tlbelo1_value       (csr_tlbelo1_value[31:0]),
               .csr_asid_value          (csr_asid_value[31:0]),
               .tlb_r_e                 (tlb_r_e),
               .tlb_r_vppn              (tlb_r_vppn[18:0]),
               .tlb_r_ps                (tlb_r_ps[5:0]),
               .tlb_r_asid              (tlb_r_asid[9:0]),
               .tlb_r_g                 (tlb_r_g),
               .tlb_r_ppn0              (tlb_r_ppn0[19:0]),
               .tlb_r_plv0              (tlb_r_plv0[1:0]),
               .tlb_r_mat0              (tlb_r_mat0[1:0]),
               .tlb_r_d0                (tlb_r_d0),
               .tlb_r_v0                (tlb_r_v0),
               .tlb_r_ppn1              (tlb_r_ppn1[19:0]),
               .tlb_r_plv1              (tlb_r_plv1[1:0]),
               .tlb_r_mat1              (tlb_r_mat1[1:0]),
               .tlb_r_d1                (tlb_r_d1),
               .tlb_r_v1                (tlb_r_v1));

    // CSR instance (updated for exp13)
    CSR u_csr(
        .hw_int_in                (8'd0),
        .ipi_int_in               (1'd0),
        .coreid_in                (32'd0), // Core ID, can be customized
        .ex_entry                 (csr_ex_entry),
        .era                      (csr_era),
        .has_int                  (has_int),
        .ertn_flush               (wb_is_ertn),
        .wb_ex                    (wb_ex_valid),
        .wb_pc                    (wb_ex_pc),
        .tlbrd_en                 (csr_tlbrd_en),
        .tlbidx_index             (csr_tlbidx_index[3:0]),
        .tlbidx_ps                (csr_tlbidx_ps[5:0]),
        .tlbidx_ne                (csr_tlbidx_ne),
        .tlbehi_vppn              (csr_tlbehi_vppn[18:0]),
        /*AUTOINST*/
              // Outputs
              .csr_rvalue               (csr_rvalue[31:0]),
              .csr_tlbidx_value         (csr_tlbidx_value[31:0]),
              .csr_tlbehi_value         (csr_tlbehi_value[31:0]),
              .csr_tlbelo0_value        (csr_tlbelo0_value[31:0]),
              .csr_tlbelo1_value        (csr_tlbelo1_value[31:0]),
              .csr_asid_value           (csr_asid_value[31:0]),
              .csr_tlbren_value         (csr_tlbren_value[31:0]),
              .csr_crmd_da_value        (csr_crmd_da_value),
              .csr_crmd_pg_value        (csr_crmd_pg_value),
              .csr_crmd_plv_value       (csr_crmd_plv_value[1:0]),
              .csr_dmw0_value           (csr_dmw0_value[31:0]),
              .csr_dmw1_value           (csr_dmw1_value[31:0]),
              // Inputs
              .clk                      (clk),
              .resetn                   (resetn),
              .csr_re                   (csr_re),
              .csr_num                  (csr_num[13:0]),
              .csr_we                   (csr_we),
              .csr_wmask                (csr_wmask[31:0]),
              .csr_wvalue               (csr_wvalue[31:0]),
              .wb_vaddr                 (wb_vaddr[31:0]),
              .wb_ecode                 (wb_ecode[5:0]),
              .wb_esubcode              (wb_esubcode[8:0]),
              .tlb_r_e                  (tlb_r_e),
              .tlb_r_vppn               (tlb_r_vppn[18:0]),
              .tlb_r_ps                 (tlb_r_ps[5:0]),
              .tlb_r_asid               (tlb_r_asid[9:0]),
              .tlb_r_g                  (tlb_r_g),
              .tlb_r_ppn0               (tlb_r_ppn0[19:0]),
              .tlb_r_plv0               (tlb_r_plv0[1:0]),
              .tlb_r_mat0               (tlb_r_mat0[1:0]),
              .tlb_r_d0                 (tlb_r_d0),
              .tlb_r_v0                 (tlb_r_v0),
              .tlb_r_ppn1               (tlb_r_ppn1[19:0]),
              .tlb_r_plv1               (tlb_r_plv1[1:0]),
              .tlb_r_mat1               (tlb_r_mat1[1:0]),
              .tlb_r_d1                 (tlb_r_d1),
              .tlb_r_v1                 (tlb_r_v1));

    // TLB instance (TLBNUM = 16)
    tlb u_tlb(
        // invtlb opcode
        .invtlb_valid (tlb_invtlb_valid),
        .invtlb_op    (tlb_invtlb_op),
        // write port
        .we           (tlb_we),
        .w_index      (tlb_w_index),
        .w_e          (tlb_w_e),
        .w_vppn       (tlb_w_vppn),
        .w_ps         (tlb_w_ps),
        .w_asid       (tlb_w_asid),
        .w_g          (tlb_w_g),
        .w_ppn0       (tlb_w_ppn0),
        .w_plv0       (tlb_w_plv0),
        .w_mat0       (tlb_w_mat0),
        .w_d0         (tlb_w_d0),
        .w_v0         (tlb_w_v0),
        .w_ppn1       (tlb_w_ppn1),
        .w_plv1       (tlb_w_plv1),
        .w_mat1       (tlb_w_mat1),
        .w_d1         (tlb_w_d1),
        .w_v1         (tlb_w_v1),
        // read port
        .r_index      (csr_tlbidx_index),
        .r_e          (tlb_r_e),
        .r_vppn       (tlb_r_vppn),
        .r_ps         (tlb_r_ps),
        .r_asid       (tlb_r_asid),
        .r_g          (tlb_r_g),
        .r_ppn0       (tlb_r_ppn0),
        .r_plv0       (tlb_r_plv0),
        .r_mat0       (tlb_r_mat0),
        .r_d0         (tlb_r_d0),
        .r_v0         (tlb_r_v0),
        .r_ppn1       (tlb_r_ppn1),
        .r_plv1       (tlb_r_plv1),
        .r_mat1       (tlb_r_mat1),
        .r_d1         (tlb_r_d1),
        .r_v1         (tlb_r_v1),
              // Outputs
              .s0_found                 (s0_found),
              .s0_index                 (s0_index[3:0]),
              .s0_ppn                   (s0_ppn[19:0]),
              .s0_ps                    (s0_ps[5:0]),
              .s0_plv                   (s0_plv[1:0]),
              .s0_mat                   (s0_mat[1:0]),
              .s0_d                     (s0_d),
              .s0_v                     (s0_v),
              .s1_found                 (s1_found),
              .s1_index                 (s1_index[3:0]),
              .s1_ppn                   (s1_ppn[19:0]),
              .s1_ps                    (s1_ps[5:0]),
              .s1_plv                   (s1_plv[1:0]),
              .s1_mat                   (s1_mat[1:0]),
              .s1_d                     (s1_d),
              .s1_v                     (s1_v),
              // Inputs
              .clk                      (clk),
              .s0_vppn                  (s0_vppn[18:0]),
              .s0_va_bit12              (s0_va_bit12),
              .s0_asid                  (s0_asid[9:0]),
              .s1_vppn                  (s1_vppn[18:0]),
              .s1_va_bit12              (s1_va_bit12),
              .s1_asid                  (s1_asid[9:0]));
    
    assign flush = wb_is_ertn | wb_ex_valid;
    assign flush_target = wb_is_ertn ? csr_era :
                          (wb_ecode == `ECODE_TLBR) ? csr_tlbren_value :
                          csr_ex_entry;
endmodule
