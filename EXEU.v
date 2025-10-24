`include "macros.h"
module EXEU(
    input  wire        clk,
    input  wire        resetn,

    // Pipeline interface with ID stage
    output wire        exe_allowin,
    input  wire        id_to_exe_valid,
    input  wire [`ID2EXE_LEN - 1:0] id_to_exe_zip,

    // Pipeline interface with MEM stage
    input  wire        mem_allowin,
    output wire        exe_to_mem_valid,
    output wire [`EXE2MEM_LEN - 1:0] exe_to_mem_zip,

    // Data SRAM interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,

    // Data forwarding to ID stage
    output wire [38:0] exe_rf_zip      // {exe_res_from_mem, exe_rf_we, exe_rf_waddr, exe_alu_result}
);

    // Pipeline control
    reg         exe_valid;

    reg  [31:0] exe_pc;
    reg  [18:0] exe_alu_op;
    reg  [31:0] exe_alu_src1;
    reg  [31:0] exe_alu_src2;
    reg         exe_res_from_mem;
    reg  [ 3:0] exe_mem_op;
    reg  [31:0] exe_rkd_value;
    reg         exe_rf_we;
    reg  [ 4:0] exe_rf_waddr;

    wire [31:0] exe_alu_result;
    wire [31:0] final_result;
    
    // Multiply/Divide control signals
    wire        mul_busy;
    wire        mul_done;
    wire        div_busy;
    wire        div_done;
    wire [63:0] mul_product;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    wire        div_by_zero;
    
    // Multi-cycle operation detection
    wire        is_mul_op;
    wire        is_div_op;
    wire        is_multicycle_op;
    
    // Multi-cycle execution state machine
    reg         multicycle_executing;
    wire        exe_ready_go;
    
    assign is_mul_op = exe_alu_op[12] | exe_alu_op[13] | exe_alu_op[14];
    assign is_div_op = exe_alu_op[15] | exe_alu_op[16] | exe_alu_op[17] | exe_alu_op[18];
    assign is_multicycle_op = is_mul_op | is_div_op;

    // Pipeline state control with proper timing
    always @(posedge clk) begin
        if (~resetn) begin
            multicycle_executing <= 1'b0;
        end else begin
            if (start_multicycle) begin
                // Start multi-cycle execution
                multicycle_executing <= 1'b1;
            end else if (multicycle_executing) begin
                // Wait for completion of multi-cycle operation
                if ((is_mul_op & mul_done) | (is_div_op & div_done))
                    multicycle_executing <= 1'b0;
            end
        end
    end    
    wire   start_multicycle;
    assign start_multicycle = is_multicycle_op & start_exe;  // Special time stamp
    assign exe_ready_go = ~start_multicycle & ~multicycle_executing;
    assign exe_allowin = ~exe_valid | (exe_ready_go & mem_allowin);
    assign exe_to_mem_valid = exe_valid & exe_ready_go;

    always @(posedge clk) begin
        if (~resetn)
            exe_valid <= 1'b0;
        else if (multicycle_executing | (id_to_exe_valid & exe_allowin) | start_multicycle)
            exe_valid <= 1'b1;
        else
            exe_valid <= 1'b0;
    end

    // Pipeline register updates
    reg start_exe;
    always @(posedge clk) begin
        if (id_to_exe_valid & exe_allowin) begin
            {exe_alu_op, exe_res_from_mem, exe_alu_src1, exe_alu_src2, exe_mem_op, exe_rf_we, exe_rf_waddr, exe_rkd_value, exe_pc} <= id_to_exe_zip;
            start_exe <= 1'b1;
        end else
            start_exe <= 1'b0;
    end

    // ALU instantiation (only handles first 12 bits for regular ALU operations)
    alu u_alu(
        .alu_op     (exe_alu_op[11:0]),
        .alu_src1   (exe_alu_src1),
        .alu_src2   (exe_alu_src2),
        .alu_result (exe_alu_result)
    );
    
    // Start signals for multiply/divide operations
    reg mul_start;
    reg div_start;
    
    always @(posedge clk) begin
        if (~resetn) begin
            mul_start <= 1'b0;
            div_start <= 1'b0;
        end else begin
            // Start signal active for one cycle when new multicycle instruction arrives
            mul_start <= is_mul_op & start_multicycle;
            div_start <= is_div_op & start_multicycle;
        end
    end
    
    // Multiply module instantiation
    mul u_mul(
        .clk         (clk),
        .resetn      (resetn),
        .start       (mul_start),
        .signed_mode (exe_alu_op[12] | exe_alu_op[13]), // signed for MUL.W and MULH.W
        .op_a        (exe_alu_src1),
        .op_b        (exe_alu_src2),
        .busy        (mul_busy),
        .done        (mul_done),
        .product     (mul_product)
    );
    
    // Divide module instantiation  
    div u_div(
        .clk           (clk),
        .resetn        (resetn),
        .start         (div_start),
        .signed_mode   (exe_alu_op[15] | exe_alu_op[16]), // signed for DIV.W and MOD.W
        .dividend      (exe_alu_src1),
        .divisor       (exe_alu_src2),
        .busy          (div_busy),
        .done          (div_done),
        .divide_by_zero(div_by_zero),
        .quotient      (div_quotient),
        .remainder     (div_remainder)
    );

    // Result selection logic for multiply/divide operations
    assign final_result = exe_alu_op[12] ? mul_product[31:0] :     // MUL.W: low 32 bits
                          exe_alu_op[13] ? mul_product[63:32] :    // MULH.W: high 32 bits (signed)
                          exe_alu_op[14] ? mul_product[63:32] :    // MULH.WU: high 32 bits (unsigned)
                          exe_alu_op[15] ? div_quotient :          // DIV.W: quotient (signed)
                          exe_alu_op[16] ? div_remainder :         // MOD.W: remainder (signed)
                          exe_alu_op[17] ? div_quotient :          // DIV.WU: quotient (unsigned)
                          exe_alu_op[18] ? div_remainder :         // MOD.WU: remainder (unsigned)
                          exe_alu_result;                          // Regular ALU result

    // Data SRAM interface
    wire addr0 = (exe_alu_result[1:0] == 2'd0);
    wire addr1 = (exe_alu_result[1:0] == 2'd1);
    wire addr2 = (exe_alu_result[1:0] == 2'd2);
    wire addr3 = (exe_alu_result[1:0] == 2'd3);
    assign data_sram_en     = (exe_res_from_mem | exe_mem_op[2]) & exe_valid;
    assign data_sram_we     = // st.b
                              (exe_mem_op == 4) ?
                              ( addr0 ? 4'b0001 :
                                addr1 ? 4'b0010 :
                                addr2 ? 4'b0100 :
                                addr3 ? 4'b1000 :
                                4'b0000) :
                              // st.h
                              (exe_mem_op == 5) ?
                              ( (addr0 | addr1) ? 4'b0011 :
                                (addr2 | addr3) ? 4'b1100 :
                                4'b0000 ) :
                              // st.w
                              (exe_mem_op == 6) ?
                              ( 4'b1111 ) :
                              4'b0;
    assign data_sram_addr   = exe_alu_result & ~32'd3; // Alignment
    assign data_sram_wdata  = // st.b
                              (exe_mem_op == 4) ?
                              ( addr0 ? {24'd0, exe_rkd_value[7:0]       } :
                                addr1 ? {16'd0, exe_rkd_value[7:0],  8'd0} :
                                addr2 ? { 8'd0, exe_rkd_value[7:0], 16'd0} :
                                addr3 ? {       exe_rkd_value[7:0], 24'd0} :
                                32'd0 ) :
                              // st.h
                              (exe_mem_op == 5) ?
                              ( (addr0 | addr1) ? {16'd0, exe_rkd_value[15:0]} :
                                (addr2 | addr3) ? {exe_rkd_value[15:0], 16'd0} :
                                32'd0 ) :
                              // st.w
                              (exe_mem_op == 6) ?
                              ( exe_rkd_value ) :
                              // default
                              32'd0;

    // Forward data to IDU
    assign exe_rf_zip = {exe_valid & exe_res_from_mem, exe_valid & exe_rf_we, exe_rf_waddr, final_result};

    // Output assignment
    //                       39          4           32
    assign exe_to_mem_zip = {exe_rf_zip, exe_mem_op, exe_pc};

endmodule
