`ifndef MACRO
    `define MACRO

    `define IF2ID_LEN 64    // {inst, pc}
    `define ID2EXE_LEN 158  // {alu_op, res_from_mem, alu_src1, alu_src2, mem_op, rf_we, rf_waddr, rkd_value, pc}
    `define EXE2MEM_LEN 75  // {res_from_mem, rf_we,  rf_waddr, alu_result, mem_op, pc}
    `define MEM2WB_LEN 70   // {rf_we, rf_waddr, rf_wdata, pc}
`endif
