module tlb
#(
    parameter TLBNUM = 16
) ( 
    input wire clk,

    // search port 0 (for fetch)
    input  wire [              18:0] s0_vppn,       // Virtual Page Number (Double Page)
    input  wire                      s0_va_bit12,   // bit 12 of Virtual Addr
    input  wire [               9:0] s0_asid,       // Process ID
    output wire                      s0_found,
    output wire [$clog2(TLBNUM)-1:0] s0_index,
    output wire [              19:0] s0_ppn,        // Physical Page Numebr (Single Page)
    output wire [               5:0] s0_ps,         // Page Size
    output wire [               1:0] s0_plv,        // Privilege level
    output wire [               1:0] s0_mat,        // Mem Access Type (1 - Coherent Cached, 0 - Strongly-ordered UnCached)
    output wire                      s0_d,          // Dirty
    output wire                      s0_v,          // Valid

    // search port 1 (for load/store)
    input  wire [              18:0] s1_vppn,
    input  wire                      s1_va_bit12,
    input  wire [               9:0] s1_asid,
    output wire                      s1_found,
    output wire [$clog2(TLBNUM)-1:0] s1_index,
    output wire [              19:0] s1_ppn,
    output wire [               5:0] s1_ps,
    output wire [               1:0] s1_plv,
    output wire [               1:0] s1_mat,
    output wire                      s1_d,
    output wire                      s1_v,

    // invtlb opcode
    input  wire                      invtlb_valid,
    input  wire [               4:0] invtlb_op,

    // write port
    input  wire                      we, //w(rite) e(nable)
    input  wire [$clog2(TLBNUM)-1:0] w_index,
    input  wire                      w_e,
    input  wire [              18:0] w_vppn,
    input  wire [               5:0] w_ps,
    input  wire [               9:0] w_asid,
    input  wire                      w_g,           // Global. Skip ASID check when set
    input  wire [              19:0] w_ppn0,
    input  wire [               1:0] w_plv0,
    input  wire [               1:0] w_mat0,
    input  wire                      w_d0,
    input  wire                      w_v0,
    input  wire [              19:0] w_ppn1, 
    input  wire [               1:0] w_plv1,
    input  wire [               1:0] w_mat1,
    input  wire                      w_d1,
    input  wire                      w_v1,

    // read port
    input  wire [$clog2(TLBNUM)-1:0] r_index,
    output wire                      r_e,
    output wire [              18:0] r_vppn,
    output wire [               5:0] r_ps,
    output wire [               9:0] r_asid,
    output wire                      r_g,
    output wire [              19:0] r_ppn0,
    output wire [               1:0] r_plv0,
    output wire [               1:0] r_mat0,
    output wire                      r_d0,
    output wire                      r_v0,
    output wire [              19:0] r_ppn1,
    output wire [               1:0] r_plv1,
    output wire [               1:0] r_mat1,
    output wire                      r_d1,
    output wire                      r_v1
);
    /*==============================================*/
    // TLB Registers
    /*==============================================*/

    reg [TLBNUM - 1:0] tlb_e;
    reg [TLBNUM - 1:0] tlb_ps4MB; //pagesize 1:4MB, 0:4KB
    reg [        18:0] tlb_vppn [TLBNUM - 1:0];
    reg [         9:0] tlb_asid [TLBNUM - 1:0];
    reg                tlb_g    [TLBNUM - 1:0];

    reg [        19:0] tlb_ppn0 [TLBNUM - 1:0];
    reg [         1:0] tlb_plv0 [TLBNUM - 1:0];
    reg [         1:0] tlb_mat0 [TLBNUM - 1:0];
    reg                tlb_d0   [TLBNUM - 1:0];
    reg                tlb_v0   [TLBNUM - 1:0];

    reg [        19:0] tlb_ppn1 [TLBNUM - 1:0];
    reg [         1:0] tlb_plv1 [TLBNUM - 1:0];
    reg [         1:0] tlb_mat1 [TLBNUM - 1:0];
    reg                tlb_d1   [TLBNUM - 1:0];
    reg                tlb_v1   [TLBNUM - 1:0];

    /*==============================================*/
    // Search and INVTLB Query
    /*==============================================*/

    wire [TLBNUM - 1:0] s0_match;
    wire [TLBNUM - 1:0] s1_match;
    wire                s0_select_second_page;
    wire                s1_select_second_page;

    wire [TLBNUM - 1:0] inv_match;

    wire [TLBNUM - 1:0] cond1;      // G == 0
    wire [TLBNUM - 1:0] cond2;      // G == 1
    wire [TLBNUM - 1:0] s0_cond3;   // s0_asid == ASID
    wire [TLBNUM - 1:0] s1_cond3;   // s1_asid == ASID
    wire [TLBNUM - 1:0] s0_cond4;   // s0_vppn match
    wire [TLBNUM - 1:0] s1_cond4;   // s1_vppn match


    genvar i;
    generate
        for (i = 0; i < TLBNUM; i = i + 1) begin
            assign    cond1[i] =  (tlb_g[i] == 1'b0);
            assign    cond2[i] =  (tlb_g[i] == 1'b1);
            assign s0_cond3[i] =  (s0_asid == tlb_asid[i]);
            assign s1_cond3[i] =  (s1_asid == tlb_asid[i]);
            assign s0_cond4[i] =  (s0_vppn[18:9] == tlb_vppn[i][18:9])
                               && (tlb_ps4MB[i] || (s0_vppn[8:0] == tlb_vppn[i][8:0]));
            assign s1_cond4[i] =  (s1_vppn[18:9] == tlb_vppn[i][18:9])
                               && (tlb_ps4MB[i] || (s1_vppn[8:0] == tlb_vppn[i][8:0]));

            assign s0_match[i]  =  tlb_e[i] && s0_cond4[i] && (s0_cond3[i] || cond2[i]);
            assign s1_match[i]  =  tlb_e[i] && s1_cond4[i] && (s1_cond3[i] || cond2[i]);
            assign inv_match[i] =  (invtlb_op == 5'h0 || invtlb_op == 5'h1) && (cond1[i] || cond2[i])
                                || (invtlb_op == 5'h2)                      && (cond2[i])
                                || (invtlb_op == 5'h3)                      && (cond1[i])
                                || (invtlb_op == 5'h4)                      && (cond1[i] && s1_cond3[i])
                                || (invtlb_op == 5'h5)                      && (cond1[i] && s1_cond3[i] && s1_cond4[i])
                                || (invtlb_op == 5'h6)                      && s1_match[i];
        end
    endgenerate

    /*==============================================*/
    // Assign Search Result
    /*==============================================*/

    // Search result for port 0
    assign s0_found = |s0_match;
    assign s0_index = {4{s0_match[ 0]}} & 4'd0
                    | {4{s0_match[ 1]}} & 4'd1
                    | {4{s0_match[ 2]}} & 4'd2
                    | {4{s0_match[ 3]}} & 4'd3
                    | {4{s0_match[ 4]}} & 4'd4
                    | {4{s0_match[ 5]}} & 4'd5
                    | {4{s0_match[ 6]}} & 4'd6
                    | {4{s0_match[ 7]}} & 4'd7
                    | {4{s0_match[ 8]}} & 4'd8
                    | {4{s0_match[ 9]}} & 4'd9
                    | {4{s0_match[10]}} & 4'd10
                    | {4{s0_match[11]}} & 4'd11
                    | {4{s0_match[12]}} & 4'd12
                    | {4{s0_match[13]}} & 4'd13
                    | {4{s0_match[14]}} & 4'd14
                    | {4{s0_match[15]}} & 4'd15;
    assign s0_select_second_page = tlb_ps4MB[s0_index] ? s0_vppn[8] : s0_va_bit12;
    assign s0_ppn = s0_select_second_page ? tlb_ppn1[s0_index] : tlb_ppn0[s0_index];
    assign s0_ps  = tlb_ps4MB[s0_index]   ?              6'd21 :              6'd12;
    assign s0_plv = s0_select_second_page ? tlb_plv1[s0_index] : tlb_plv0[s0_index];
    assign s0_mat = s0_select_second_page ? tlb_mat1[s0_index] : tlb_mat0[s0_index];
    assign s0_d   = s0_select_second_page ?   tlb_d1[s0_index] :   tlb_d0[s0_index];
    assign s0_v   = s0_select_second_page ?   tlb_v1[s0_index] :   tlb_v0[s0_index];

    // Search result for port 1
    assign s1_found = |s1_match;
    assign s1_index = {4{s1_match[ 0]}} & 4'd0
                    | {4{s1_match[ 1]}} & 4'd1
                    | {4{s1_match[ 2]}} & 4'd2
                    | {4{s1_match[ 3]}} & 4'd3
                    | {4{s1_match[ 4]}} & 4'd4
                    | {4{s1_match[ 5]}} & 4'd5
                    | {4{s1_match[ 6]}} & 4'd6
                    | {4{s1_match[ 7]}} & 4'd7
                    | {4{s1_match[ 8]}} & 4'd8
                    | {4{s1_match[ 9]}} & 4'd9
                    | {4{s1_match[10]}} & 4'd10
                    | {4{s1_match[11]}} & 4'd11
                    | {4{s1_match[12]}} & 4'd12
                    | {4{s1_match[13]}} & 4'd13
                    | {4{s1_match[14]}} & 4'd14
                    | {4{s1_match[15]}} & 4'd15;
    assign s1_select_second_page = tlb_ps4MB[s1_index] ? s1_vppn[8] : s1_va_bit12;
    assign s1_ppn = s1_select_second_page ? tlb_ppn1[s1_index] : tlb_ppn0[s1_index];
    assign s1_ps  = tlb_ps4MB[s1_index]   ?              6'd21 :              6'd12;
    assign s1_plv = s1_select_second_page ? tlb_plv1[s1_index] : tlb_plv0[s1_index];
    assign s1_mat = s1_select_second_page ? tlb_mat1[s1_index] : tlb_mat0[s1_index];
    assign s1_d   = s1_select_second_page ?   tlb_d1[s1_index] :   tlb_d0[s1_index];
    assign s1_v   = s1_select_second_page ?   tlb_v1[s1_index] :   tlb_v0[s1_index];

    /*==============================================*/
    // Assign Read Result
    /*==============================================*/

    assign r_e    =     tlb_e[r_index];
    assign r_vppn =  tlb_vppn[r_index];
    assign r_ps   = tlb_ps4MB[r_index] ? 6'd21 : 6'd12;
    assign r_asid =  tlb_asid[r_index];
    assign r_g    =     tlb_g[r_index];
    assign r_ppn0 =  tlb_ppn0[r_index];
    assign r_plv0 =  tlb_plv0[r_index];
    assign r_mat0 =  tlb_mat0[r_index];
    assign r_d0   =    tlb_d0[r_index];
    assign r_v0   =    tlb_v0[r_index];
    assign r_ppn1 =  tlb_ppn1[r_index];
    assign r_plv1 =  tlb_plv1[r_index];
    assign r_mat1 =  tlb_mat1[r_index];
    assign r_d1   =    tlb_d1[r_index];
    assign r_v1   =    tlb_v1[r_index];

    /*==============================================*/
    // Write and INVTLB Operation
    /*==============================================*/

    // tlb_e register
    integer j;
    always @(posedge clk) begin
        if (we) begin
            tlb_e[w_index] <= w_e;
        end else if (invtlb_valid) begin
            for (j = 0; j < TLBNUM; j = j + 1) begin
                if (inv_match[j]) tlb_e[j] <= 1'b0;
            end
        end
    end

    // Other registers
    always @(posedge clk) begin
        if (we) begin
            tlb_vppn[w_index]  <= w_vppn;
            tlb_ps4MB[w_index] <= (w_ps == 6'd21);
            tlb_asid[w_index]  <= w_asid;
            tlb_g[w_index]     <= w_g;
            tlb_ppn0[w_index]  <= w_ppn0;
            tlb_plv0[w_index]  <= w_plv0;
            tlb_mat0[w_index]  <= w_mat0;
            tlb_d0[w_index]    <= w_d0;
            tlb_v0[w_index]    <= w_v0;
            tlb_ppn1[w_index]  <= w_ppn1;
            tlb_plv1[w_index]  <= w_plv1;
            tlb_mat1[w_index]  <= w_mat1;
            tlb_d1[w_index]    <= w_d1;
            tlb_v1[w_index]    <= w_v1;
        end
    end

endmodule