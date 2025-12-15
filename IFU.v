`include "macros.h"
module IFU(
    input wire                     clk,
    input wire                     resetn,

    // Global flush from WB (exception/ertn)
    input wire                     flush,
    input wire [31:0]              flush_target,

    // Instruction SRAM-like interface
    output wire                    inst_sram_req,
    output wire                    inst_sram_wr,
    output wire [ 1:0]             inst_sram_size,
    output wire [31:0]             inst_sram_addr,
    output wire [ 3:0]             inst_sram_wstrb,
    output wire [31:0]             inst_sram_wdata,
    input wire                     inst_sram_addr_ok,
    input wire                     inst_sram_data_ok,
    input wire [31:0]              inst_sram_rdata,

    // TLB related (Port 0)
    output wire [18:0]             s0_vppn,
    output wire                    s0_va_bit12,
    output wire [9:0]              s0_asid,
    input wire                     s0_found,
    input wire [3:0]               s0_index,
    input wire [19:0]              s0_ppn,
    input wire [5:0]               s0_ps,
    input wire [1:0]               s0_mat,
    input wire                     s0_d,
    input wire                     s0_v,

    // CSR
    input wire [9:0]               csr_asid_asid,
    input wire                     csr_crmd_da_value,
    input wire                     csr_crmd_pg_value,

    // Pipeline interface with ID stage
    input wire                     id_allowin,
    output wire                    if_to_id_valid,
    input wire                     br_stall,
    input wire                     br_taken,
    input wire [31:0]              br_target,
    output wire [`IF2ID_LEN - 1:0] if_to_id_zip
);

    // Pipeline control signals
    reg         if_valid;
    reg  [31:0] if_pc;
    wire        if_ready_go;
    wire [31:0] if_inst;
    wire        if_allowin;

    // PC calculation
    wire [31:0] seq_pc;    // sequential PC
    wire [31:0] next_pc;   // next PC to fetch
    
    // Exception detection
    wire [5:0]  if_ecode;
    wire [8:0]  if_esubcode;
    wire        if_is_ertn;

    // SRAM-like interface handshake control
    reg  [31:0] inst_buff;        // Instruction buffer
    reg         inst_buff_valid;  // Instruction buffer valid
    reg         inst_discard;     // Need to discard inst

    // Pre-IF control: request handshake 
    wire        to_fs_valid;      // Request has been accepted (addr_ok received)
    wire        pre_if_ready_go;
    wire        req_handshake;    // req & addr_ok

    // Request handshake: only send request when IF allows in (simplified design)
    assign inst_sram_req = if_allowin & resetn & ~br_stall &
                           (csr_crmd_da_value | (s0_found & s0_v));
    assign req_handshake = inst_sram_req & inst_sram_addr_ok;
    assign pre_if_ready_go = req_handshake;

    // Track if request has been accepted
    assign to_fs_valid = pre_if_ready_go;
    
    // Instruction buffer: store instruction when IF can't enter ID
    always @(posedge clk) begin
        if (~resetn) begin
            inst_buff <= 32'b0;
            inst_buff_valid <= 1'b0;
        end
        else if (if_to_id_valid & id_allowin)
            inst_buff_valid <= 1'b0;
        else if (if_cancel)
            inst_buff_valid <= 1'b0;
        else if (~inst_buff_valid & inst_sram_data_ok & ~inst_discard) begin
            inst_buff <= if_inst;
            inst_buff_valid <= 1'b1;
        end
    end

    // Cancel control: discard data when exception/branch cancels pending request
    always @(posedge clk) begin
        if (~resetn)
            inst_discard <= 1'b0;
        else if (if_cancel & ~if_allowin & ~if_ready_go)
            inst_discard <= 1'b1;
        else if (inst_discard & inst_sram_data_ok)
            inst_discard <= 1'b0;
    end

    // IF stage ready_go: data received or buffer has valid instruction
    assign if_ready_go = (inst_buff_valid | inst_sram_data_ok) & ~inst_discard;
    assign if_allowin = ~if_valid | (if_ready_go & id_allowin);
    assign if_to_id_valid = if_valid & if_ready_go;
    assign if_cancel = flush | br_taken;

    // IF valid control
    always @(posedge clk) begin
        if (~resetn)
            if_valid <= 1'b0;
        else if (if_allowin)
            if_valid <= to_fs_valid;
        else if (if_cancel)
            if_valid <= 1'b0;
    end

    reg flush_r;
    reg br_taken_r;
    reg [31:0] br_target_r;
    reg [31:0] flush_target_r;

    always @(posedge clk) begin
        if (~resetn) begin
            flush_r <= 1'b0;
            br_taken_r <= 1'b0;
            br_target_r <= 32'b0;
            flush_target_r <= 32'b0;
        end
        // Save flush and br_taken signals when pre_if_ready_go is not asserted
        else if (flush & ~pre_if_ready_go) begin
            flush_r <= 1'b1;
            flush_target_r <= flush_target;
        end
        else if (br_taken & ~pre_if_ready_go) begin
            br_taken_r <= 1'b1;
            br_target_r <= br_target;
        end
        else if (pre_if_ready_go) begin
            flush_r <= 1'b0;
            br_taken_r <= 1'b0;
        end
    end

    // PC generation
    assign seq_pc = if_pc + 32'h4;
    assign next_pc = flush_r ? flush_target_r : flush ? flush_target : 
                     br_taken_r ? br_target_r : br_taken ? br_target : seq_pc;

    always @(posedge clk) begin
        if (~resetn)
            if_pc <= 32'h1bfffffc;
        else if (to_fs_valid & if_allowin)
            if_pc <= next_pc;
    end

    // va = next_pc
    assign s0_vppn = next_pc[31:13];
    assign s0_va_bit12 = next_pc[12];
    assign s0_asid = csr_asid_asid;

    wire [31:0] paddr = csr_crmd_pg_value ? {s0_ppn, next_pc[11:0]} : next_pc;
    

    // Instruction SRAM-like interface
    assign inst_sram_wr = 1'b0;           // Never write instruction
    assign inst_sram_size = 2'b10;        // Always 4 bytes for instruction
    assign inst_sram_addr = paddr;
    assign inst_sram_wstrb = 4'b0;
    assign inst_sram_wdata = 32'b0;

    // Select instruction from buffer or current input
    assign if_inst = inst_buff_valid ? inst_buff : inst_sram_rdata;

    // Exception detection: ADEF - Address error for instruction fetch
    // PC must be word-aligned (lowest 2 bits must be 00)
    wire if_ex_adef = (if_pc[1:0] != 2'b00);
    // TLB Refill
    wire if_ex_tlbr = csr_crmd_pg_value & !s0_found;
    // Fetch Page Invalid
    wire if_ex_pif  = csr_crmd_pg_value & s0_found && !s0_v;
    // TLB Invalid
    wire if_ex_valid = if_ex_adef | if_ex_tlbr | if_ex_pif;
    assign if_ecode    = if_ex_adef ? `ECODE_ADE  :
                         if_ex_tlbr ? `ECODE_TLBR :
                         if_ex_pif  ? `ECODE_PIF  :
                         6'd0;
    assign if_esubcode = 9'd0;
    assign if_is_ertn  = 1'b0;

    // Pack exception fields: {ex_valid, ecode[5:0], esubcode[8:0], is_ertn}
    wire [`EX_FIELDS_LEN-1:0] if_ex_fields = {if_ex_valid, if_ecode, if_esubcode, if_is_ertn};

    // Output assignments
    assign if_to_id_zip = {if_inst, if_pc, if_ex_fields};

endmodule
