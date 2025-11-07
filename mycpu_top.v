`include "macros.h"
module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,  // byte write enable
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,  // byte write enable
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
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
    wire        br_taken;
    wire [31:0] br_target;

    // Global flush (exception/ertn)
    wire        flush;
    wire [31:0] flush_target;

    // CSR interface
    wire [31:0] csr_ex_entry;
    wire [31:0] csr_era;
    wire        csr_has_int;
    wire        csr_re;
    wire [13:0] csr_num;
    wire [31:0] csr_rvalue;
    wire        csr_we;
    wire [31:0] csr_wmask;
    wire [31:0] csr_wvalue;

    // WBU exception/ertn info
    wire        wb_ex_valid;
    wire [31:0] wb_ex_pc;
    wire [31:0] wb_vaddr;
    wire [5:0]  wb_ecode;
    wire [8:0]  wb_esubcode;
    wire        wb_is_ertn;

    IFU my_ifu(
        .clk(clk),
        .resetn(resetn),

        .flush(flush),
        .flush_target(flush_target),

        .inst_sram_en(inst_sram_en),
        .inst_sram_we(inst_sram_we),
        .inst_sram_addr(inst_sram_addr),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata),
        
        .id_allowin(id_allowin),
        .if_to_id_valid(if_to_id_valid),
        .br_taken(br_taken),
        .br_target(br_target),
        .if_to_id_zip(if_to_id_zip)
    );

    IDU my_idu(
        .clk(clk),
        .resetn(resetn),

        .flush(flush),
        .has_int(csr_has_int),

        .id_allowin(id_allowin),
        .br_taken(br_taken),
        .br_target(br_target),
        .if_to_id_valid(if_to_id_valid),
        .if_to_id_zip(if_to_id_zip),

        .exe_allowin(exe_allowin),
        .id_to_exe_valid(id_to_exe_valid),
        .id_to_exe_zip(id_to_exe_zip),

        .wb_rf_zip(wb_rf_zip),
        .mem_rf_zip(mem_rf_zip),
        .exe_rf_zip(exe_rf_zip)
    );

    EXEU my_exeu(
        .clk(clk),
        .resetn(resetn),
        .flush(flush),
        
        .exe_allowin(exe_allowin),
        .id_to_exe_valid(id_to_exe_valid),
        .id_to_exe_zip(id_to_exe_zip),

        .mem_allowin(mem_allowin),
        .exe_to_mem_valid(exe_to_mem_valid),
        .exe_to_mem_zip(exe_to_mem_zip),

        .data_sram_en(data_sram_en),
        .data_sram_we(data_sram_we),
        .data_sram_addr(data_sram_addr),
        .data_sram_wdata(data_sram_wdata),

        .exe_rf_zip(exe_rf_zip),
        .mem_ex(mem_ex),
        .wb_ex(wb_ex)
    );

    MEMU my_memu(
        .clk(clk),
        .resetn(resetn),
        .flush(flush),

        .mem_allowin(mem_allowin),
        .exe_to_mem_valid(exe_to_mem_valid),
        .exe_to_mem_zip(exe_to_mem_zip),

        .wb_allowin(wb_allowin),
        .mem_to_wb_valid(mem_to_wb_valid),
        .mem_to_wb_zip(mem_to_wb_zip),

        .data_sram_rdata(data_sram_rdata),

        .mem_rf_zip(mem_rf_zip),
        .mem_ex(mem_ex)
    ) ;

    WBU my_wbu(
        .clk(clk),
        .resetn(resetn),

        .wb_allowin(wb_allowin),
        .mem_to_wb_valid(mem_to_wb_valid),
        .mem_to_wb_zip(mem_to_wb_zip),

        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),

        .wb_rf_zip(wb_rf_zip),
        .wb_ex(wb_ex),
        .wb_ex_valid(wb_ex_valid),
        .wb_ex_pc(wb_ex_pc),
        .wb_vaddr(wb_vaddr),
        .wb_ecode(wb_ecode),
        .wb_esubcode(wb_esubcode),
        .wb_is_ertn(wb_is_ertn),

        .csr_re(csr_re),
        .csr_we(csr_we),
        .csr_num(csr_num),
        .csr_wmask(csr_wmask),
        .csr_wvalue(csr_wvalue),
        .csr_rvalue(csr_rvalue)
    );

    // CSR instance (updated for exp13)
    CSR u_csr(
        .clk(clk),
        .resetn(resetn),

        .csr_re(csr_re),
        .csr_num(csr_num),
        .csr_rvalue(csr_rvalue),
        .csr_we(csr_we),
        .csr_wmask(csr_wmask),
        .csr_wvalue(csr_wvalue),

        .hw_int_in(8'd0),
        .ipi_int_in(1'd0),
        .coreid_in(32'd0), // Core ID, can be customized

        .ex_entry(csr_ex_entry),
        .era(csr_era),
        .has_int(csr_has_int),
        
        .ertn_flush(wb_is_ertn),
        .wb_ex(wb_ex_valid),
        .wb_pc(wb_ex_pc),
        .wb_vaddr(wb_vaddr),
        .wb_ecode(wb_ecode),
        .wb_esubcode(wb_esubcode)
    );

    assign flush = wb_is_ertn | wb_ex_valid;
    assign flush_target = wb_is_ertn ? csr_era : csr_ex_entry;
endmodule
