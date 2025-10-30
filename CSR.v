module CSR
  (
   input wire         clk,
   input wire         resetn,

   input wire         csr_re,
   input wire [13:0]  csr_num,
   output wire [31:0] csr_rvalue,
   input wire         csr_we,
   input wire [31:0]  csr_wmask,
   input wire [31:0]  csr_wvalue,

   input wire [7:0]   hw_int_in,
   input wire         ipi_int_in,

   output wire [31:0] ex_entry,
   output wire        has_int,
   input wire         ertn_flush,
   input wire         wb_ex,
   input wire [31:0]  wb_pc,
   input wire [5:0]   wb_ecode,
   input wire [7:0]   wb_esubcode
   );

`define CSR_CRMD        0
`define CSR_CRMD_PLV    1:0
`define CSR_CRMD_IE     2
    reg [1:0] csr_crmd_plv;
    reg       csr_crmd_ie;
    always @(posedge clk) begin
        if (~resetn) begin
            csr_crmd_plv <= 2'b0;
            csr_crmd_ie  <= 1'b0;
        end else if (wb_ex) begin
            csr_crmd_plv <= 2'b0;
            csr_crmd_ie  <= 1'b0;
        end else if (ertn_flush) begin
            csr_crmd_plv <= csr_prmd_pplv;
            csr_crmd_ie  <= csr_prmd_pie;
        end else if (csr_we && csr_num == `CSR_CRMD) begin
            csr_crmd_plv <= ( csr_wmask[`CSR_CRMD_PLV] & csr_wvalue[`CSR_CRMD_PLV]) |
                            (~csr_wmask[`CSR_CRMD_PLV] & csr_crmd_plv);
            csr_crmd_ie  <= ( csr_wmask[`CSR_CRMD_IE]  & csr_wvalue[`CSR_CRMD_IE] ) |
                            (~csr_wmask[`CSR_CRMD_IE]  & csr_crmd_ie );
        end
    end

    wire       csr_crmd_da   = 1'b1;
    wire       csr_crmd_pg   = 1'b0;
    wire [1:0] csr_crmd_datf = 2'b0;
    wire [1:0] csr_crmd_datm = 2'b0;

    wire [31:0] csr_crmd =
                // 31:9           8:7            6:5            4            3            2           1:0
                {23'd0, csr_crmd_datm, csr_crmd_datf, csr_crmd_pg, csr_crmd_da, csr_crmd_ie, csr_crmd_plv};

`define CSR_PRMD        1
`define CSR_PRMD_PPLV   1:0
`define CSR_PRMD_PIE    2
    reg [1:0] csr_prmd_pplv;
    reg       csr_prmd_pie;
    always @(posedge clk) begin
        if (wb_ex) begin
            csr_prmd_pplv <= csr_crmd_plv;
            csr_prmd_pie  <= csr_crmd_ie;
        end else if (csr_we && csr_num == `CSR_PRMD) begin
            csr_prmd_pplv <= ( csr_wmask[`CSR_PRMD_PPLV] & csr_wvalue[`CSR_PRMD_PPLV]) |
                             (~csr_wmask[`CSR_PRMD_PPLV] & csr_prmd_pplv);
            csr_prmd_pie  <= ( csr_wmask[`CSR_PRMD_PIE]  & csr_wvalue[`CSR_PRMD_PIE] ) |
                             (~csr_wmask[`CSR_PRMD_PIE]  & csr_prmd_pie );
        end
    end

    wire [31:0] csr_prmd =
                // 31:3            2            1:0
                {29'd0, csr_prmd_pie, csr_prmd_pplv};

`define CSR_ECFG        4
`define CSR_ECFG_LIE    12:0
    reg [12:0] csr_ecfg_lie;
    always @(posedge clk) begin
        if (~resetn) begin
            csr_ecfg_lie <= 13'b0;
        end else if (csr_we && csr_num == `CSR_ECFG) begin
            // bit 10 is always 0, 0x1bff = 0b1_1011_1111_1111
            csr_ecfg_lie <= ( csr_wmask[`CSR_ECFG_LIE] & 13'h1bff & csr_wvalue[`CSR_ECFG_LIE]) |
                            (~csr_wmask[`CSR_ECFG_LIE] & 13'h1bff & csr_ecfg_lie);
        end
    end

    wire [31:0] csr_ecfg = {19'd0, csr_ecfg_lie};

`define CSR_ESTAT               5
`define CSR_ESTAT_IS            12:0
`define CSR_ESTAT_IS10          1:0
`define CSR_ESTAT_Ecode         21:16
`define CSR_ESTAT_EsubCode      30:22
`define CSR_TICLR               68 // 0x44
`define CSR_TICLR_CLR           0
    reg [12:0] csr_estat_is;
    reg [5:0]  csr_estat_ecode;
    reg [8:0]  csr_estat_esubcode;
    always @(posedge clk) begin
        if (~resetn) begin
            csr_estat_is[1:0] <= 2'b0;
        end else if (csr_we && csr_num == `CSR_ESTAT) begin
            csr_estat_is[1:0] <= ( csr_wmask[`CSR_ESTAT_IS10] & csr_wvalue[`CSR_ESTAT_IS10]) |
                                 (~csr_wmask[`CSR_ESTAT_IS10] & csr_estat_is[1:0]);
        end
        
        csr_estat_is[9:2] <= hw_int_in[7:0];
        csr_estat_is[10]  <= 1'b0;
        
        if (timer_cnt[31:0] == 32'b0) begin
            csr_estat_is[11] <= 1'b1;
        end else if (csr_we && csr_num == `CSR_TICLR &&
                     csr_wmask[`CSR_TICLR_CLR] && csr_wvalue[`CSR_TICLR_CLR]) begin
            csr_estat_is[11] <= 1'b0;
        end
        csr_estat_is[12] <= ipi_int_in;

        if (wb_ex) begin
            csr_estat_ecode    <= wb_ecode;
            csr_estat_esubcode <= wb_esubcode;
        end
    end

    wire [31:0] csr_estat =
                // 31               30:22            21:16  15:13         12:0
                {1'd0, csr_estat_esubcode, csr_estat_ecode, 3'd0, csr_estat_is};

`define CSR_ERA         6
`define CSR_ERA_PC      31:0
    reg [31:0] csr_era_pc;
    always @(posedge clk) begin
        if (wb_ex) begin
            csr_era_pc <= wb_pc;
        end else if (csr_we && csr_num == `CSR_ERA) begin
            csr_era_pc <= ( csr_wmask[`CSR_ERA_PC] & csr_wvalue[`CSR_ERA_PC]) |
                          (~csr_wmask[`CSR_ERA_PC] & csr_era_pc);
        end
    end

    wire [31:0] csr_era = csr_era_pc;

`define CSR_EENTRY      12
`define CSR_EENTRY_VA   31:6
    reg [25:0] csr_eentry_va;
    always @(posedge clk) begin
        if (csr_we && csr_num == `CSR_EENTRY) begin
            csr_eentry_va <= ( csr_wmask[`CSR_EENTRY_VA] & csr_wvalue[`CSR_EENTRY_VA]) |
                             (~csr_wmask[`CSR_EENTRY_VA] & csr_eentry_va);
        end
    end

    wire [31:0] csr_eentry = {csr_eentry_va, 6'd0};

`define CSR_SAVE0       48
`define CSR_SAVE1       49
`define CSR_SAVE2       50
`define CSR_SAVE3       51
`define CSR_SAVE_DATA   31:0
    reg [31:0] csr_save0;
    reg [31:0] csr_save1;
    reg [31:0] csr_save2;
    reg [31:0] csr_save3;
    always @(posedge clk) begin
        if (csr_we && csr_num == `CSR_SAVE0) begin
            csr_save0 <= ( csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]) |
                         (~csr_wmask[`CSR_SAVE_DATA] & csr_save0);
        end
        if (csr_we && csr_num == `CSR_SAVE1) begin
            csr_save1 <= ( csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]) |
                         (~csr_wmask[`CSR_SAVE_DATA] & csr_save1);
        end
        if (csr_we && csr_num == `CSR_SAVE2) begin
            csr_save2 <= ( csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]) |
                         (~csr_wmask[`CSR_SAVE_DATA] & csr_save2);
        end
        if (csr_we && csr_num == `CSR_SAVE3) begin
            csr_save3 <= ( csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]) |
                         (~csr_wmask[`CSR_SAVE_DATA] & csr_save3);
        end
    end

    reg [31:0]  timer_cnt;


    assign csr_rvalue = {32{csr_re}} &
                        (({32{csr_num == `CSR_CRMD  }} & csr_crmd  ) |
                         ({32{csr_num == `CSR_PRMD  }} & csr_prmd  ) |
                         ({32{csr_num == `CSR_ESTAT }} & csr_estat ) |
                         ({32{csr_num == `CSR_ESTAT }} & csr_estat ) |
                         ({32{csr_num == `CSR_ERA   }} & csr_era   ) |
                         ({32{csr_num == `CSR_EENTRY}} & csr_eentry) );

    assign ex_entry = {csr_eentry_va, 6'd0};
    assign has_int = csr_crmd_ie;

endmodule // CSR

