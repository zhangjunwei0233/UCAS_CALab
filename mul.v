module mul #(
    parameter XLEN = 32
)(
    input  wire                  clk,
    input  wire                  resetn,
    input  wire                  start,
    input  wire                  signed_mode,
    input  wire [XLEN-1:0]       op_a,
    input  wire [XLEN-1:0]       op_b,
    output wire                  busy,
    output wire                  done,
    output wire [2*XLEN-1:0]     product
);

    localparam COUNT_WIDTH = $clog2(XLEN) + 1;

    // Handshake/state bookkeeping
    reg                         busy_r;
    reg                         done_r;
    reg                         sign_result_r;
    reg [COUNT_WIDTH-1:0]       count_r;
    // Shift-and-add datapath registers
    reg [2*XLEN-1:0]            multiplicand_r;
    reg [XLEN-1:0]              multiplier_r;
    reg [2*XLEN-1:0]            acc_r;
    reg [2*XLEN-1:0]            product_r;

    // Combinational helpers for the next cycle of the shift-add algorithm
    wire [2*XLEN-1:0] add_term          = multiplier_r[0] ? multiplicand_r : {2*XLEN{1'b0}};
    wire [2*XLEN-1:0] acc_sum           = acc_r + add_term;
    wire [2*XLEN-1:0] multiplicand_shift= multiplicand_r << 1;
    wire [XLEN-1:0]   multiplier_shift  = multiplier_r >> 1;
    wire               last_cycle       = (count_r == {{(COUNT_WIDTH-1){1'b0}}, 1'b1});

    assign busy    = busy_r;
    assign done    = done_r;
    assign product = product_r;

    // Utility to take the magnitude of a two's-complement operand
    function [XLEN-1:0] abs_signed;
        input [XLEN-1:0] value;
        begin
            if (value[XLEN-1]) begin
                abs_signed = (~value) + {{(XLEN-1){1'b0}}, 1'b1};
            end else begin
                abs_signed = value;
            end
        end
    endfunction

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            busy_r         <= 1'b0;
            done_r         <= 1'b0;
            sign_result_r  <= 1'b0;
            count_r        <= {COUNT_WIDTH{1'b0}};
            multiplicand_r <= {2*XLEN{1'b0}};
            multiplier_r   <= {XLEN{1'b0}};
            acc_r          <= {2*XLEN{1'b0}};
            product_r      <= {2*XLEN{1'b0}};
        end else begin
            done_r <= 1'b0;

            if (start && !busy_r) begin
                // Latch operands and initialise the iterative multiply
                busy_r         <= 1'b1;
                sign_result_r  <= signed_mode && (op_a[XLEN-1] ^ op_b[XLEN-1]);
                count_r        <= XLEN;
                multiplicand_r <= {{XLEN{1'b0}}, signed_mode ? abs_signed(op_a) : op_a};
                multiplier_r   <= signed_mode ? abs_signed(op_b) : op_b;
                acc_r          <= {2*XLEN{1'b0}};
            end else if (busy_r) begin
                if (last_cycle) begin
                    // Final accumulation and sign correction
                    busy_r         <= 1'b0;
                    done_r         <= 1'b1;
                    product_r      <= sign_result_r ? (~acc_sum + {{(2*XLEN-1){1'b0}}, 1'b1}) : acc_sum;
                    acc_r          <= {2*XLEN{1'b0}};
                    multiplicand_r <= {2*XLEN{1'b0}};
                    multiplier_r   <= {XLEN{1'b0}};
                    count_r        <= {COUNT_WIDTH{1'b0}};
                end else begin
                    // Shift the operands and accumulate partial product
                    acc_r          <= acc_sum;
                    multiplicand_r <= multiplicand_shift;
                    multiplier_r   <= multiplier_shift;
                    count_r        <= count_r - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                end
            end
        end
    end

endmodule
