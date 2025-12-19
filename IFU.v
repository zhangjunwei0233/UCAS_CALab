`include "macros.h"
module IFU(
    input wire                     clk,
    input wire                     resetn,

    // Global flush from WB (exception/ertn)
    input wire                     flush,
    input wire [31:0]              flush_target,

    // Instruction Cache interface
    output wire                    inst_valid,
    output wire                    inst_op,
    output wire [ 7:0]             inst_index,
    output wire [19:0]             inst_tag,
    output wire [ 3:0]             inst_offset,
    output wire [ 3:0]             inst_wstrb,
    output wire [31:0]             inst_wdata,
    output wire                    inst_uncache,
    input wire                     inst_addr_ok,
    input wire                     inst_data_ok,
    input wire [31:0]              inst_rdata,

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
    input wire [1:0]               csr_crmd_datf_value,
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
                        req_sent <= inst_addr_ok;
                    end
                end else if (inst_data_ok) begin
                    // We have sent the request, now handshaking
                    inst_buf <= inst_rdata;
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
                             (req_sent && inst_data_ok && !cancel));

    // TLB
    assign s0_vppn     = if_pc[31:13];
    assign s0_va_bit12 = if_pc[12];
    assign s0_asid     = csr_asid_asid;

    // DMW match: check both address segment and privilege level
    wire dmw0_plv_ok = (csr_crmd_plv_value == 2'd0) ? csr_dmw0_value[0] : 
                       (csr_crmd_plv_value == 2'd3) ? csr_dmw0_value[3] : 1'b0;
    wire dmw1_plv_ok = (csr_crmd_plv_value == 2'd0) ? csr_dmw1_value[0] : 
                       (csr_crmd_plv_value == 2'd3) ? csr_dmw1_value[3] : 1'b0;
    wire is_dmw0 = dmw0_plv_ok && (if_pc[31:29] == csr_dmw0_value[31:29]);
    wire is_dmw1 = dmw1_plv_ok && (if_pc[31:29] == csr_dmw1_value[31:29]);
    wire [31:0] paddr =
                csr_crmd_pg_value ?
                ( is_dmw0 ? {csr_dmw0_value[27:25], if_pc[28:0]} :
                  is_dmw1 ? {csr_dmw1_value[27:25], if_pc[28:0]} :
                  ( (s0_ps == 12) ?
                    {s0_ppn[19:0], if_pc[11:0]} :
                    {s0_ppn[19:9], if_pc[20:0]} )
                 ) : if_pc;

    // Determine if access is cacheable (MAT field)
    // MAT=0: SUC (Strong-ordered Uncached), MAT=1: CC (Coherent Cached)
    // For ICache, storage type comes from:
    // 1. Direct address translation (DA=1, PG=0): CRMD.DATF (2 bits)
    // 2. Direct mapped window (PG=1, DMW hit): DMW.MAT (2 bits)
    // 3. Page table mapped (PG=1, no DMW): TLB.MAT (2 bits)
    wire [1:0] fetch_mat = 
                !csr_crmd_pg_value ? csr_crmd_datf_value : // DA mode: cacheable by default
                ( is_dmw0 ? csr_dmw0_value[5:4] :     // DMW0 MAT
                  is_dmw1 ? csr_dmw1_value[5:4] :     // DMW1 MAT
                  s0_mat                              // TLB MAT
                );
    
    wire fetch_uncache = (fetch_mat == 2'b00);  // SUC (MAT=0): uncached

    // Instruction Cache interface
    assign inst_valid   = !inst_buf_valid & !req_sent;
    assign inst_op      = 1'b0;               // Always read for instruction fetch
    assign inst_index   = if_pc[11:4];        // Virtual address index (VIPT)
    assign inst_tag     = paddr[31:12];       // Physical address tag
    assign inst_offset  = if_pc[3:0];         // Offset
    assign inst_wstrb   = 4'b0;               // No write
    assign inst_wdata   = 32'b0;              // No write data
    assign inst_uncache = fetch_uncache;      // Uncached access flag

    // Select instruction from buffer or current input
    wire [31:0] if_inst = inst_buf_valid ? inst_buf : inst_rdata;

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
