`ifndef MACRO
    `define MACRO

    // Exception/ERTN pipeline fields: {ex_valid, ecode[5:0], esubcode[8:0], is_ertn}
    `define EX_FIELDS_LEN 17

    // CSR pipleline fields: {csr_read, csr_we, csr_num[13:0], csr_wmask[31:0], csr_wvalue[31:0]}
    `define CSR_FIELDS_LEN 80

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
    `define ID2EXE_LEN (158 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)  // {..., ex_fields}
    `define EXE2MEM_LEN (75 + 32 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)  // {..., vaddr, ex_fields}
    `define MEM2WB_LEN (70 + 32 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)   // {..., vaddr, ex_fields}
`endif
