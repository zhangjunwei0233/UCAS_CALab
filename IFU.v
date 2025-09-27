module IFU(
    input   wire        clk,
    input   wire        resetn,

    // Instruction SRAM interface
    output  wire        inst_sram_en,
    output  wire [ 3:0] inst_sram_we,
    output  wire [31:0] inst_sram_addr,
    output  wire [31:0] inst_sram_wdata,
    input   wire [31:0] inst_sram_rdata,

    // Pipeline interface with ID stage
    input   wire        id_allowin,
    input   wire        br_taken,
    input   wire [31:0] br_target,
    output  wire        if_to_id_valid,
    output  wire [31:0] if_inst,
    output  reg  [31:0] if_pc
);

    // Pipeline control signals
    reg         if_valid;
    wire        if_ready_go;

    // PC calculation
    wire [31:0] seq_pc;    // sequential PC
    wire [31:0] next_pc;   // next PC to fetch

    // Pipeline state control
    assign if_ready_go = 1'b1;
    assign if_allowin = ~if_valid | (if_ready_go & id_allowin);
    assign if_to_id_valid = if_valid & if_ready_go;

    always @(posedge clk) begin
        if_valid <= resetn;
    end

    // PC generation
    assign seq_pc = if_pc + 32'h4;
    assign next_pc = br_taken ? br_target : seq_pc;

    always @(posedge clk) begin
        if (~resetn)
            if_pc <= 32'h1bfffffc;
        else if (if_allowin)
            if_pc <= next_pc;
    end

    // Instruction SRAM interface
    assign inst_sram_en = if_allowin & resetn;
    assign inst_sram_we = 4'b0;
    assign inst_sram_addr = next_pc;
    assign inst_sram_wdata = 32'b0;
    assign if_inst = inst_sram_rdata;

endmodule