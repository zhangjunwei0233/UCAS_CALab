`ifndef MACRO
    `define MACRO

    // Exception/ERTN pipeline fields: {ex_valid, ecode[5:0], esubcode[8:0], is_ertn}
    `define EX_FIELDS_LEN 17

    // CSR pipleline fields: {csr_read, csr_we, csr_num[13:0], csr_wmask[31:0], csr_wvalue[31:0]}
    `define CSR_FIELDS_LEN 80

    // ECODE definitions (subset for exp12)
    `define ECODE_SYS 6'd11
    `define ESUBCODE_NONE 9'd0

    `define IF2ID_LEN (64)    // {inst, pc}
    `define ID2EXE_LEN (158 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)  // {..., ex_fields}
    `define EXE2MEM_LEN (75 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)  // {..., ex_fields}
    `define MEM2WB_LEN (70 + `CSR_FIELDS_LEN + `EX_FIELDS_LEN)   // {..., ex_fields}
`endif
