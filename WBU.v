module WBU(
    input  wire        clk,
    input  wire        resetn,

    // Pipeline interface with MEM stage
    output wire        wb_allowin,
    input  wire [37:0] mem_rf_zip,
    input  wire        mem_to_wb_valid,
    input  wire [31:0] mem_pc,

    // Debug trace interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,

    // Pipeline interface with ID stage
    output wire [37:0] wb_rf_zip
);
    // Pipeline control
    wire        wb_ready_go;
    reg         wb_valid;

    // Register file data
    reg         rf_we;
    reg  [4 :0] rf_waddr;
    reg  [31:0] rf_wdata;
    reg  [31:0] wb_pc;
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
            wb_pc <= mem_pc;
            {rf_we, rf_waddr, rf_wdata} <= mem_rf_zip;
        end
    end

    // Output assignments
    assign wb_rf_zip = {rf_we, rf_waddr, rf_wdata};

    // Debug trace interface
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_we = {4{rf_we & wb_valid}};
    assign debug_wb_rf_wnum = rf_waddr;
    assign debug_wb_rf_wdata = rf_wdata;
endmodule
