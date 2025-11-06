`include "macros.h"
module IFU(
    input   wire        clk,
    input   wire        resetn,

    // Global flush from WB (exception/ertn)
    input   wire        flush,
    input   wire [31:0] flush_target,

    // Instruction SRAM interface
    output  wire        inst_sram_en,
    output  wire [ 3:0] inst_sram_we,
    output  wire [31:0] inst_sram_addr,
    output  wire [31:0] inst_sram_wdata,
    input   wire [31:0] inst_sram_rdata,

    // Pipeline interface with ID stage
    input   wire        id_allowin,
    output  wire        if_to_id_valid,
    input   wire        br_taken,
    input   wire [31:0] br_target,
    output  wire [`IF2ID_LEN - 1:0] if_to_id_zip
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
    wire if_ex_adef;       // Address error for instruction fetch
    wire if_ex_valid;      // Exception valid
    wire [5:0]  if_ecode;
    wire [8:0]  if_esubcode;
    wire        if_is_ertn;

    // Pipeline state control
    assign if_ready_go = 1'b1;
    assign if_allowin = ~if_valid | (if_ready_go & id_allowin) | flush;
    assign if_to_id_valid = if_valid & if_ready_go;

    always @(posedge clk) begin
        if_valid <= resetn;
    end

    // PC generation
    assign seq_pc = if_pc + 32'h4;
    assign next_pc = flush ? flush_target : (br_taken ? br_target : seq_pc);

    always @(posedge clk) begin
        if (~resetn)
            if_pc <= 32'h1bfffffc;
        else if (flush)
            if_pc <= flush_target;
        else if (if_allowin)
            if_pc <= next_pc;
    end

    // Instruction SRAM interface
    assign inst_sram_en = if_allowin & resetn;
    assign inst_sram_we = 4'b0;
    assign inst_sram_addr = next_pc;
    assign inst_sram_wdata = 32'b0;
    assign if_inst = inst_sram_rdata;

    // Exception detection: ADEF - Address error for instruction fetch
    // PC must be word-aligned (lowest 2 bits must be 00)
    assign if_ex_adef = (if_pc[1:0] != 2'b00);
    assign if_ex_valid = if_ex_adef;
    assign if_ecode = if_ex_adef ? `ECODE_ADE : 6'd0;
    assign if_esubcode = if_ex_adef ? `ESUBCODE_ADEF : 9'd0;
    assign if_is_ertn = 1'b0;

    // Pack exception fields: {ex_valid, ecode[5:0], esubcode[8:0], is_ertn}
    wire [`EX_FIELDS_LEN-1:0] if_ex_fields = {if_ex_valid, if_ecode, if_esubcode, if_is_ertn};

    // Output assignments
    assign if_to_id_zip = {if_inst, if_pc, if_ex_fields};

endmodule
