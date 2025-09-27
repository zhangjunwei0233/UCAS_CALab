module MEMU(
    input  wire        clk,
    input  wire        resetn,

    // Pipeline interface with EXE stage
    output wire        mem_allowin,
    input  wire [5 :0] exe_rf_zip,
    input  wire        exe_to_mem_valid,
    input  wire [31:0] exe_pc,
    input  wire [31:0] exe_alu_result,
    input  wire        exe_res_from_mem,
    input  wire        exe_mem_we,
    input  wire [31:0] exe_rkd_value,

    // Pipeline interface with WB stage
    input  wire        wb_allowin,
    output wire [37:0] mem_rf_zip,
    output wire        mem_to_wb_valid,
    output reg  [31:0] mem_pc,

    // Data SRAM interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata
);
    // Pipeline control
    wire        mem_ready_go;
    reg         mem_valid;

    // Register file control
    reg         mem_rf_we;
    reg  [4 :0] mem_rf_waddr;
    wire [31:0] mem_rf_wdata;

    // Memory and ALU data
    wire [31:0] mem_result;
    reg  [31:0] alu_result;
    reg         mem_we;
    reg  [31:0] rkd_value;
    reg         res_from_mem;

    // Pipeline state control
    assign mem_ready_go = 1'b1;
    assign mem_allowin = ~mem_valid | (mem_ready_go & wb_allowin);
    assign mem_to_wb_valid = mem_valid & mem_ready_go;
    assign mem_rf_wdata = res_from_mem ? mem_result : alu_result;
    assign mem_rf_zip = {mem_rf_we, mem_rf_waddr, mem_rf_wdata};

    always @(posedge clk) begin
        if (~resetn)
            mem_valid <= 1'b0;
        else
            mem_valid <= exe_to_mem_valid & mem_allowin;
    end

    // Pipeline register updates
    always @(posedge clk) begin
        if (exe_to_mem_valid & mem_allowin) begin
            mem_pc <= exe_pc;
            alu_result <= exe_alu_result;
            {mem_rf_we, mem_rf_waddr} <= exe_rf_zip;
            {res_from_mem, mem_we, rkd_value} <= {exe_res_from_mem, exe_mem_we, exe_rkd_value};
        end
    end

    // Memory result
    assign mem_result = data_sram_rdata;

    // Data SRAM interface
    assign data_sram_en = exe_res_from_mem | exe_mem_we;
    assign data_sram_we = {4{exe_mem_we}};
    assign data_sram_addr = exe_alu_result;
    assign data_sram_wdata = exe_rkd_value;

endmodule
