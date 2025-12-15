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
    input wire [1:0]               s0_plv,
    input wire [1:0]               s0_mat,
    input wire                     s0_d,
    input wire                     s0_v,

    // CSR
    input wire [9:0]               csr_asid_asid,
    input wire                     csr_crmd_da_value,
    input wire                     csr_crmd_pg_value,
    input wire [1:0]               csr_crmd_plv_value,
    input wire [31:0]              csr_dmw0_value,
    input wire [31:0]              csr_dmw1_value,

    // Pipeline interface with ID stage
    input wire                     id_allowin,
    output wire                    if_to_id_valid,
    input wire                     br_stall,
    input wire                     br_taken,
    input wire [31:0]              br_target,
    output wire [`IF2ID_LEN - 1:0] if_to_id_zip
);

    wire id_ready = id_allowin && !br_stall;

    reg [31:0] if_pc;
    reg [31:0] inst_buf;
    reg        inst_buf_valid;
    reg        req_sent;
    reg        cancel;
    reg [31:0] cancel_target;
    always @(posedge clk) begin
        if (!resetn) begin
            if_pc          <= 32'h1c000000;
            inst_buf_valid <= 0;
            req_sent       <= 0;
            cancel         <= 0;
        end else begin
            if (!inst_buf_valid) begin
                // Buffer is empty, fetch one from memory
                if (!req_sent) begin
                    if (if_ex_valid) begin
                        // When exception occurs at IF, stop accessing the wrong address
                        // To pass exception down the pipeline, fake a NOP instruction
                        inst_buf_valid <= 1;
                        inst_buf       <= 32'h02800000;
                    end else begin
                        req_sent <= inst_sram_addr_ok;
                    end
                end else if (inst_sram_data_ok) begin
                    // We have sent the request, now handshaking
                    inst_buf <= inst_sram_rdata;
                    req_sent <= 0;

                    if (!cancel) begin
                        inst_buf_valid <= !id_ready;
                        if (id_ready) begin
                            if_pc <= if_pc + 32'd4;
                        end
                    end else if (!flush && !br_taken) begin
                        cancel <= 0;
                        if_pc <= cancel_target;
                    end
                end

                if (flush || br_taken) begin
                    // Currently there is a transmission on bus
                    // Mark cancel and wait for the transmission to end
                    cancel         <= 1;
                    cancel_target  <= flush ? flush_target : br_target;
                end
            end else begin
                // Buffer is full
                if (flush || br_taken) begin
                    // No transmission on bus, only cancel the buffer
                    inst_buf_valid <= 0;
                    if_pc <= flush ? flush_target : br_target;
                end else if (id_ready) begin
                    inst_buf_valid <= 0;
                    if_pc <= if_pc + 32'd4;
                end
            end
        end
    end

    assign if_to_id_valid = (!flush && !br_taken) &&
                            (inst_buf_valid ||
                             (req_sent && inst_sram_data_ok && !cancel));

    // TLB
    assign s0_vppn     = if_pc[31:13];
    assign s0_va_bit12 = if_pc[12];
    assign s0_asid     = csr_asid_asid;

    wire is_dmw0 = if_pc[31:29] == csr_dmw0_value[31:29];
    wire is_dmw1 = if_pc[31:29] == csr_dmw1_value[31:29];
    wire [31:0] paddr =
                csr_crmd_pg_value ?
                ( is_dmw0 ? {csr_dmw0_value[27:25], if_pc[28:0]} :
                  is_dmw1 ? {csr_dmw1_value[27:25], if_pc[28:0]} :
                  ( (s0_ps == 12) ?
                    {s0_ppn[19:0], if_pc[11:0]} :
                    {s0_ppn[19:9], if_pc[20:0]} )
                 ) : if_pc;

    // Instruction SRAM-like interface
    assign inst_sram_req   = !inst_buf_valid & !req_sent;
    assign inst_sram_wr    = 1'b0;    // Never write instruction
    assign inst_sram_size  = 2'b10;   // Always 4 bytes for instruction
    assign inst_sram_addr  = paddr;
    assign inst_sram_wstrb = 4'b0;
    assign inst_sram_wdata = 32'b0;

    // Select instruction from buffer or current input
    wire [31:0] if_inst = inst_buf_valid ? inst_buf : inst_sram_rdata;

    // Exception detection: ADEF - Address error for instruction fetch
    // PC must be word-aligned (lowest 2 bits must be 00)
    wire        adef_error          = (if_pc[1:0] != 2'b00);
    wire        tlb_gen_error       = csr_crmd_pg_value & !is_dmw0 & !is_dmw1;
    wire        tlb_refill_error    = tlb_gen_error & !s0_found;
    wire        fetch_invalid_error = tlb_gen_error &  s0_found & !s0_v;
    wire        tlb_plv_error       = tlb_gen_error &  s0_found &  s0_v & (csr_crmd_plv_value > s0_plv);
    wire        if_ex_valid         =
                adef_error          | tlb_refill_error |
                fetch_invalid_error | tlb_plv_error;
    wire [5:0]  if_ecode            =
                adef_error          ? `ECODE_ADE  :
                tlb_refill_error    ? `ECODE_TLBR :
                fetch_invalid_error ? `ECODE_PIF  :
                tlb_plv_error       ? `ECODE_PPI  :
                6'd0;
    wire [8:0] if_esubcode          = 9'd0;
    wire       if_is_ertn           = 1'b0;

    // Pack exception fields: {ex_valid, ecode[5:0], esubcode[8:0], is_ertn}
    wire [`EX_FIELDS_LEN-1:0] if_ex_fields = {if_ex_valid, if_ecode, if_esubcode, if_is_ertn};

    // Output assignments
    assign if_to_id_zip = {if_inst, if_pc, if_ex_fields};

endmodule
