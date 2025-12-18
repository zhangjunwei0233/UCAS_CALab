`ifndef MACRO
    `define MACRO

    // Exception/ERTN pipeline fields: {ex_valid, ecode[5:0], esubcode[8:0], is_ertn}
    `define EX_FIELDS_LEN 17

    // CSR pipleline fields: {csr_read, csr_we, csr_num[13:0], csr_wmask[31:0], csr_wvalue[31:0]}
    `define CSR_FIELDS_LEN 80

    // Counter instruction fields: {inst_rdcntvl, inst_rdcntvh}
    `define CNT_INST_FIELDS_LEN 2

    // TLB pipeline fields
    // ID->EXE: {tlb_op[2:0], invtlb_op[4:0]}
    `define ID_TLB_FIELDS_LEN 8
    // EXE->MEM / MEM->WB: {tlb_op[2:0], invtlb_op[4:0]}
    // Note: TLBSRCH result is handled in CSR write path directly, not in pipeline fields
    `define EXE_TLB_FIELDS_LEN 8

    // ECODE definitions (for exp13)
    `define ECODE_INT  6'd0    // Interrupt
    `define ECODE_PIL  6'd1    // Page Invalid Load
    `define ECODE_PIS  6'd2    // Page Invalid Store
    `define ECODE_PIF  6'd3    // Page Invalid Fetch
    `define ECODE_PME  6'd4    // Page Modified
    `define ECODE_PPI  6'd7    // Page Privilige Invalid
    `define ECODE_ADE  6'd8    // Address Error
    `define ECODE_ALE  6'd9    // Address aLignment Error  
    `define ECODE_SYS  6'd11   // System call
    `define ECODE_BRK  6'd12   // BReaK point
    `define ECODE_INE  6'd13   // Instruction Not Exist
    `define ECODE_TLBR 6'd63   // TLB Refill
    `define ECODE_REFR 6'd60   // Custom Refresh Exception

    // ESUBCODE definitions
    `define ESUBCODE_NONE  9'd0

    `define IF2ID_LEN (64 + `EX_FIELDS_LEN)    // {inst, pc, ex_fields}
    `define ID2EXE_LEN (158 + `CNT_INST_FIELDS_LEN +`CSR_FIELDS_LEN + `EX_FIELDS_LEN + `ID_TLB_FIELDS_LEN)  // {..., ex_fields, tlb}
    `define EXE2MEM_LEN (76 + 32 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN + `EXE_TLB_FIELDS_LEN)  // {..., vaddr, ex_fields, tlb}
    `define MEM2WB_LEN (70 + 32 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN + `EXE_TLB_FIELDS_LEN)   // {..., vaddr, ex_fields, tlb}

    // CSR registers
    `define CSR_CRMD        0
    `define CSR_CRMD_PLV    1:0
    `define CSR_CRMD_IE     2
    `define CSR_CRMD_DA     3
    `define CSR_CRMD_PG     4
    `define CSR_CRMD_DATF   6:5
    `define CSR_CRMD_DATM   8:7

    `define CSR_PRMD        1
    `define CSR_PRMD_PPLV   1:0
    `define CSR_PRMD_PIE    2

    `define CSR_ECFG        4
    `define CSR_ECFG_LIE    12:0

    `define CSR_ESTAT               5
    `define CSR_ESTAT_IS            12:0
    `define CSR_ESTAT_IS10          1:0
    `define CSR_ESTAT_Ecode         21:16
    `define CSR_ESTAT_EsubCode      30:22
    `define CSR_TICLR               68 // 0x44
    `define CSR_TICLR_CLR           0

    `define CSR_ERA         6
    `define CSR_ERA_PC      31:0

    `define CSR_EENTRY      12
    `define CSR_EENTRY_VA   31:6

    // TLB related CSRs
    `define CSR_TLBIDX            16   // 0x10
    `define CSR_TLBIDX_INDEX      3:0
    `define CSR_TLBIDX_PS         29:24
    `define CSR_TLBIDX_NE         31

    `define CSR_TLBEHI            17   // 0x11
    `define CSR_TLBEHI_VPPN       31:13

    `define CSR_TLBELO0           18   // 0x12
    `define CSR_TLBELO1           19   // 0x13
    `define CSR_TLBELO_V          0
    `define CSR_TLBELO_D          1
    `define CSR_TLBELO_PLV        3:2
    `define CSR_TLBELO_MAT        5:4
    `define CSR_TLBELO_G          6
    `define CSR_TLBELO_PPN        27:8

    `define CSR_ASID              24   // 0x18
    `define CSR_ASID_ASID         9:0
    `define CSR_ASID_ASIDBITS     23:16

    `define CSR_TLBRENTRY         136  // 0x88
    `define CSR_TLBRENTRY_PA      31:6

    `define CSR_BADV        7
    `define CSR_BADV_VAddr  31:0

    `define CSR_SAVE0       48
    `define CSR_SAVE1       49
    `define CSR_SAVE2       50
    `define CSR_SAVE3       51
    `define CSR_SAVE_DATA   31:0

    `define CSR_TID         64
    `define CSR_TID_TID     31:0

    `define CSR_TCFG        65
    `define CSR_TCFG_EN     0
    `define CSR_TCFG_PERIOD 1
    `define CSR_TCFG_INITV  31:2

    `define CSR_TVAL        66
    `define CSR_TVAL_VAL    31:0

    `define CSR_DMW0        384
    `define CSR_DMW1        385
    `define CSR_DMW_PLV0    0
    `define CSR_DMW_PLV3    3
    `define CSR_DMW_MAT     5:4
    `define CSR_DMW_PSEG    27:25
    `define CSR_DMW_VSEG    31:29

    // TLB op encoding
    `define TLB_OP_NONE  3'd0
    `define TLB_OP_SRCH  3'd1
    `define TLB_OP_RD    3'd2
    `define TLB_OP_WR    3'd3
    `define TLB_OP_FILL  3'd4
    `define TLB_OP_INV   3'd5
`endif
