`include "macros.h"

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
   input wire [31:0]  coreid_in,

   output wire [31:0] ex_entry,
   output wire [31:0] era,
   output wire        has_int,
   input wire         ertn_flush,
   input wire         wb_ex,
   input wire [31:0]  wb_pc,
   input wire [31:0]  wb_vaddr,
   input wire [5:0]   wb_ecode,
   input wire [8:0]   wb_esubcode
   );

    // CRMD
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

    // PRMD
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

    // ECFG
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

    // ESTAT
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

    // ERA
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

    // EENTRY
    reg [25:0] csr_eentry_va;
    always @(posedge clk) begin
        if (csr_we && csr_num == `CSR_EENTRY) begin
            csr_eentry_va <= ( csr_wmask[`CSR_EENTRY_VA] & csr_wvalue[`CSR_EENTRY_VA]) |
                             (~csr_wmask[`CSR_EENTRY_VA] & csr_eentry_va);
        end
    end

    wire [31:0] csr_eentry = {csr_eentry_va, 6'd0};

    // BADV
    reg [31:0] csr_badv_vaddr;
    wire wb_ex_addr_err = wb_ecode == `ECODE_ADE || wb_ecode == `ECODE_ALE;
    always @(posedge clk) begin
        if (wb_ex && wb_ex_addr_err) begin
            csr_badv_vaddr <= (wb_ecode == `ECODE_ADE && wb_esubcode == `ESUBCODE_ADEF) ? wb_pc : wb_vaddr;
        end
    end

    wire [31:0] csr_badv = csr_badv_vaddr;

    // SAVE0~3
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

    // TID
    reg [31:0] csr_tid_tid;
    always @(posedge clk) begin
        if (~resetn) begin
            csr_tid_tid <= coreid_in;
        end else if (csr_we && csr_num == `CSR_TID) begin
            csr_tid_tid <= ( csr_wmask[`CSR_TID_TID] & csr_wvalue[`CSR_TID_TID]) |
                           (~csr_wmask[`CSR_TID_TID] & csr_tid_tid);
        end
    end

    wire [31:0] csr_tid = csr_tid_tid;

    // TCFG
    reg        csr_tcfg_en;
    reg        csr_tcfg_periodic;
    reg [29:0] csr_tcfg_initval;
    always @(posedge clk) begin
        if (~resetn) begin
            csr_tcfg_en <= 1'b0;
        end else if (csr_we && csr_num == `CSR_TCFG) begin
            csr_tcfg_en <= ( csr_wmask[`CSR_TCFG_EN] & csr_wvalue[`CSR_TCFG_EN]) |
                           (~csr_wmask[`CSR_TCFG_EN] & csr_tcfg_en);
        end

        if (csr_we && csr_num == `CSR_TCFG) begin
            csr_tcfg_periodic <= ( csr_wmask[`CSR_TCFG_PERIOD] & csr_wvalue[`CSR_TCFG_PERIOD]) |
                                 (~csr_wmask[`CSR_TCFG_PERIOD] & csr_tcfg_periodic);
            csr_tcfg_initval  <= ( csr_wmask[`CSR_TCFG_INITV] & csr_wvalue[`CSR_TCFG_INITV]) |
                                 (~csr_wmask[`CSR_TCFG_INITV] & csr_tcfg_initval);
        end
    end

    wire [31:0] csr_tcfg = {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};

    // TVAL
    wire [31:0] tcfg_next_value;
    reg  [31:0] timer_cnt;

    assign tcfg_next_value = ( csr_wmask[31:0] & csr_wvalue[31:0]) |
                             (~csr_wmask[31:0] & {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en});

    always @(posedge clk) begin
        if (~resetn) begin
            timer_cnt <= 32'hffffffff;
        end else if (csr_we && csr_num == `CSR_TCFG && tcfg_next_value[`CSR_TCFG_EN]) begin
            timer_cnt <= {tcfg_next_value[`CSR_TCFG_INITV], 2'b0};
        end else if (csr_tcfg_en && timer_cnt != 32'hffffffff) begin
            if (timer_cnt[31:0] == 32'b0 && csr_tcfg_periodic) begin
                timer_cnt <= {csr_tcfg_initval, 2'b0};
            end else begin
                timer_cnt <= timer_cnt - 1'b1;
            end
        end
    end

    wire [31:0] csr_tval = timer_cnt[31:0];

    // TICLR - "W1"
    wire csr_ticlr_clr = 1'b0;
    wire [31:0] csr_ticlr = {31'd0, csr_ticlr_clr};


    assign csr_rvalue = {32{csr_num == `CSR_CRMD  }} & csr_crmd
                      | {32{csr_num == `CSR_PRMD  }} & csr_prmd
                      | {32{csr_num == `CSR_ECFG  }} & csr_ecfg
                      | {32{csr_num == `CSR_ESTAT }} & csr_estat
                      | {32{csr_num == `CSR_ERA   }} & csr_era
                      | {32{csr_num == `CSR_BADV  }} & csr_badv
                      | {32{csr_num == `CSR_EENTRY}} & csr_eentry
                      | {32{csr_num == `CSR_SAVE0 }} & csr_save0
                      | {32{csr_num == `CSR_SAVE1 }} & csr_save1
                      | {32{csr_num == `CSR_SAVE2 }} & csr_save2
                      | {32{csr_num == `CSR_SAVE3 }} & csr_save3
                      | {32{csr_num == `CSR_TID   }} & csr_tid
                      | {32{csr_num == `CSR_TCFG  }} & csr_tcfg
                      | {32{csr_num == `CSR_TVAL  }} & csr_tval
                      | {32{csr_num == `CSR_TICLR }} & csr_ticlr;

    assign ex_entry = {csr_eentry_va, 6'd0};
    assign era = csr_era;
    assign has_int = (|(csr_estat_is & csr_ecfg_lie)) & csr_crmd_ie;

endmodule // CSR
