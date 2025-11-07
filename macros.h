`ifndef MACRO
    `define MACRO

    // Exception/ERTN pipeline fields: {ex_valid, ecode[5:0], esubcode[8:0], is_ertn}
    `define EX_FIELDS_LEN 17

    // CSR pipleline fields: {csr_read, csr_we, csr_num[13:0], csr_wmask[31:0], csr_wvalue[31:0]}
    `define CSR_FIELDS_LEN 80

    // Counter instruction fields: {inst_rdcntvl, inst_rdcntvh}
    `define CNT_INST_FIELDS_LEN 2

    // ECODE definitions (for exp13)
    `define ECODE_INT  6'd0    // Interrupt
    `define ECODE_ADE  6'd8    // Address Error
    `define ECODE_ALE  6'd9    // Address aLignment Error  
    `define ECODE_SYS  6'd11   // System call
    `define ECODE_BRK  6'd12   // BReaK point
    `define ECODE_INE  6'd13   // Instruction Not Exist

    // ESUBCODE definitions
    `define ESUBCODE_NONE  9'd0
    `define ESUBCODE_ADEF  9'd0    // Address error for instruction fetch

    `define IF2ID_LEN (64 + `EX_FIELDS_LEN)    // {inst, pc, ex_fields}
    `define ID2EXE_LEN (158 + `CNT_INST_FIELDS_LEN +`CSR_FIELDS_LEN + `EX_FIELDS_LEN)  // {..., ex_fields}
    `define EXE2MEM_LEN (75 + 32 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)  // {..., vaddr, ex_fields}
    `define MEM2WB_LEN (70 + 32 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)   // {..., vaddr, ex_fields}

    // CSR registers
    `define CSR_CRMD        0
    `define CSR_CRMD_PLV    1:0
    `define CSR_CRMD_IE     2

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
`endif
