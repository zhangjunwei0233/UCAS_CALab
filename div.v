module div #(
    parameter XLEN = 32
)(
    input  wire            clk,
    input  wire            resetn,
    input  wire            start,
    input  wire            signed_mode,
    input  wire [XLEN-1:0] dividend,
    input  wire [XLEN-1:0] divisor,
    output wire            busy,
    output wire            done,
    output wire            divide_by_zero,
    output wire [XLEN-1:0] quotient,
    output wire [XLEN-1:0] remainder
);

    localparam COUNT_WIDTH = $clog2(XLEN) + 1;

    // Handshake and sign tracking
    reg                   busy_r;
    reg                   done_r;
    reg                   divide_by_zero_r;
    reg                   sign_quotient_r;
    reg                   sign_remainder_r;
    reg [COUNT_WIDTH-1:0] count_r;
    // Restoring-divider datapath
    reg [XLEN-1:0]        divisor_mag_r;
    reg [XLEN-1:0]        dividend_shift_r;
    reg [XLEN-1:0]        quotient_mag_r;
    reg [XLEN-1:0]        remainder_mag_r;
    reg [XLEN-1:0]        quotient_r;
    reg [XLEN-1:0]        remainder_r;

    wire [XLEN:0] divisor_ext         = {1'b0, divisor_mag_r};
    wire [XLEN:0] remainder_candidate = {remainder_mag_r, dividend_shift_r[XLEN-1]};
    wire [XLEN:0] remainder_sub_full  = remainder_candidate - divisor_ext;
    wire           ge_candidate       = ~remainder_sub_full[XLEN]; // high bit indicates borrow
    wire [XLEN-1:0] remainder_sub     = remainder_sub_full[XLEN-1:0];
    wire [XLEN-1:0] quotient_shift    = (quotient_mag_r << 1) | {{(XLEN-1){1'b0}}, ge_candidate};
    wire [XLEN-1:0] dividend_shift    = dividend_shift_r << 1;
    wire [XLEN-1:0] remainder_next    = ge_candidate ? remainder_sub[XLEN-1:0] : remainder_candidate[XLEN-1:0];
    wire             last_cycle       = (count_r == {{(COUNT_WIDTH-1){1'b0}}, 1'b1});

    assign busy           = busy_r;
    assign done           = done_r;
    assign divide_by_zero = divide_by_zero_r;
    assign quotient       = quotient_r;
    assign remainder      = remainder_r;

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
            busy_r            <= 1'b0;
            done_r            <= 1'b0;
            divide_by_zero_r  <= 1'b0;
            sign_quotient_r   <= 1'b0;
            sign_remainder_r  <= 1'b0;
            count_r           <= {COUNT_WIDTH{1'b0}};
            divisor_mag_r     <= {XLEN{1'b0}};
            dividend_shift_r  <= {XLEN{1'b0}};
            quotient_mag_r    <= {XLEN{1'b0}};
            remainder_mag_r   <= {XLEN{1'b0}};
            quotient_r        <= {XLEN{1'b0}};
            remainder_r       <= {XLEN{1'b0}};
        end else begin
            done_r           <= 1'b0;
            divide_by_zero_r <= 1'b0;

            if (start && !busy_r) begin
                if (divisor == {XLEN{1'b0}}) begin
                    // Degenerate case: flag divide-by-zero and return early
                    divide_by_zero_r <= 1'b1;
                    done_r           <= 1'b1;
                    quotient_r       <= {XLEN{1'b0}};
                    remainder_r      <= dividend;
                end else begin
                    // Initialise restoring division with unsigned magnitudes
                    busy_r           <= 1'b1;
                    sign_quotient_r  <= signed_mode && (dividend[XLEN-1] ^ divisor[XLEN-1]);
                    sign_remainder_r <= signed_mode && dividend[XLEN-1];
                    count_r          <= XLEN;
                    divisor_mag_r    <= signed_mode ? abs_signed(divisor) : divisor;
                    dividend_shift_r <= signed_mode ? abs_signed(dividend) : dividend;
                    quotient_mag_r   <= {XLEN{1'b0}};
                    remainder_mag_r  <= {XLEN{1'b0}};
                end
            end else if (busy_r) begin
                if (last_cycle) begin
                    // Final cycle: latch magnitudes and apply sign corrections
                    busy_r          <= 1'b0;
                    done_r          <= 1'b1;
                    quotient_mag_r  <= quotient_shift;
                    remainder_mag_r <= remainder_next;

                    if (sign_quotient_r) begin
                        quotient_r <= (~quotient_shift) + {{(XLEN-1){1'b0}}, 1'b1};
                    end else begin
                        quotient_r <= quotient_shift;
                    end

                    if (sign_remainder_r) begin
                        remainder_r <= (~remainder_next) + {{(XLEN-1){1'b0}}, 1'b1};
                    end else begin
                        remainder_r <= remainder_next;
                    end

                    count_r          <= {COUNT_WIDTH{1'b0}};
                    divisor_mag_r    <= {XLEN{1'b0}};
                    dividend_shift_r <= {XLEN{1'b0}};
                end else begin
                    // Iterate: shift in next dividend bit and conditionally subtract divisor
                    quotient_mag_r   <= quotient_shift;
                    remainder_mag_r  <= remainder_next;
                    dividend_shift_r <= dividend_shift;
                    count_r          <= count_r - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                end
            end
        end
    end

endmodule
