`include "macros.h"
module IDU(
    input  wire        clk,
    input  wire        resetn,

    // Pipeline interface with IF stage
    output wire        id_allowin,
    input  wire        if_to_id_valid,
    output wire        br_taken,
    output wire [31:0] br_target,
    input  wire [`IF2ID_LEN - 1:0] if_to_id_zip,

    // Pipeline interface with EXE stage
    input  wire        exe_allowin,
    output wire        id_to_exe_valid,
    output wire [`ID2EXE_LEN - 1:0] id_to_exe_zip,

    // Data forwarding to resolve data relevance
    input  wire [37:0] wb_rf_zip,   // {wb_rf_we, wb_rf_waddr, wb_rf_wdata}
    input  wire [37:0] mem_rf_zip,  // {mem_rf_we, mem_rf_waddr, mem_rf_wdata}
    input  wire [38:0] exe_rf_zip   // {exe_res_from_mem, exe_rf_we, exe_rf_waddr, exe_alu_result}
);

    // Pipeline control
    wire        id_ready_go;
    wire        id_stall;
    reg         id_valid;
    reg  [31:0] inst;
    reg  [31:0] id_pc;

    // ALU control (extended to 19 bits for multiply/divide operations)
    wire [18:0] alu_op;
    wire [31:0] alu_src1, alu_src2;
    wire        src1_is_pc, src2_is_imm;

    // Control signals
    wire        res_from_mem, dst_is_r1, gr_we;
    wire [3: 0] mem_op;
    wire        src_reg_is_rd;
    wire [4: 0] dest;

    // Register file and immediate values
    wire [31:0] rj_value, rkd_value, imm;
    wire [31:0] br_offs, jirl_offs;

    // Instruction field extraction
    wire [ 5:0] op_31_26;
    wire [ 3:0] op_25_22;
    wire [ 1:0] op_21_20;
    wire [ 4:0] op_19_15;
    wire [ 4:0] rd, rj, rk;
    wire [11:0] i12;
    wire [19:0] i20;
    wire [15:0] i16;
    wire [25:0] i26;

    // Decoded operation fields
    wire [63:0] op_31_26_d;
    wire [15:0] op_25_22_d;
    wire [ 3:0] op_21_20_d;
    wire [31:0] op_19_15_d;

    // Immediate type control
    wire        need_ui5, need_si12, need_ui12, need_si16, need_si20, need_si26;
    wire        src2_is_4;

    // Register file interface
    wire [ 4:0] rf_raddr1, rf_raddr2;
    wire [31:0] rf_rdata1, rf_rdata2;
    wire        id_rf_we;
    wire [ 4:0] id_rf_waddr;

    // Data forwarding signals
    wire        wb_rf_we, mem_rf_we, exe_rf_we;
    wire [ 4:0] wb_rf_waddr, mem_rf_waddr, exe_rf_waddr;
    wire [31:0] wb_rf_wdata, mem_rf_wdata, exe_rf_wdata;
    wire        exe_res_from_mem;

    // Data conflict signals
    wire        conflict_r1_wb, conflict_r2_wb;
    wire        conflict_r1_mem, conflict_r2_mem;
    wire        conflict_r1_exe, conflict_r2_exe;
    wire        need_r1, need_r2;


    // Pipeline state control
    assign id_ready_go = ~id_stall;
    assign id_allowin = ~id_valid | (id_ready_go & exe_allowin);
    assign id_to_exe_valid = id_valid & id_ready_go;

    assign id_stall = exe_res_from_mem & ((conflict_r1_exe & need_r1) | (conflict_r2_exe & need_r2));

    always @(posedge clk) begin
        if (~resetn)
            id_valid <= 1'b0;
        else if (br_taken)
            id_valid <= 1'b0;
        else if (id_allowin)
            id_valid <= if_to_id_valid;
        // else: keep current id_valid (maintain instruction during stall)
    end

    // Pipeline register updates
    always @(posedge clk) begin
        if (if_to_id_valid & id_allowin) begin
            {inst, id_pc} <= if_to_id_zip;
        end
    end

    // Branch control
    wire rj_eq_rd  = (rj_value == rkd_value);
    wire rj_lt_rd  = ($signed(rj_value) < $signed(rkd_value));
    wire rj_ltu_rd = (rj_value < rkd_value);
    assign br_taken = ((inst_beq  &  rj_eq_rd ) |
                       (inst_bne  & ~rj_eq_rd ) |
                       (inst_blt  &  rj_lt_rd ) |
                       (inst_bge  & ~rj_lt_rd ) |
                       (inst_bltu &  rj_ltu_rd) |
                       (inst_bgeu & ~rj_ltu_rd) |
                       inst_jirl | inst_bl | inst_b) & id_valid;
    assign br_target = (ty_B & ~inst_jirl) ? (id_pc + br_offs) :
                       (rj_value + jirl_offs);

    assign op_31_26 = inst[31:26];
    assign op_25_22 = inst[25:22];
    assign op_21_20 = inst[21:20];
    assign op_19_15 = inst[19:15];

    assign rd = inst[4:0];
    assign rj = inst[9:5];
    assign rk = inst[14:10];

    assign i12 = inst[21:10];
    assign i20 = inst[24:5];
    assign i16 = inst[25:10];
    assign i26 = {inst[9:0], inst[25:10]};

    // Instruction field decoders
    decoder_6_64 u_dec0(.in(op_31_26), .out(op_31_26_d));
    decoder_4_16 u_dec1(.in(op_25_22), .out(op_25_22_d));
    decoder_2_4  u_dec2(.in(op_21_20), .out(op_21_20_d));
    decoder_5_32 u_dec3(.in(op_19_15), .out(op_19_15_d));

    // Instruction decode logic
    
    // Instruction types:
    // R: Reg-Reg Arithmetic
    //   add.w sub.w slt sltu nor and or xor sll.w srl.w sra.w
    wire ty_R       = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1];
    wire inst_add_w = ty_R & op_21_20_d[1] & op_19_15_d[ 0];
    wire inst_sub_w = ty_R & op_21_20_d[1] & op_19_15_d[ 2];
    wire inst_slt   = ty_R & op_21_20_d[1] & op_19_15_d[ 4];
    wire inst_sltu  = ty_R & op_21_20_d[1] & op_19_15_d[ 5];
    wire inst_nor   = ty_R & op_21_20_d[1] & op_19_15_d[ 8];
    wire inst_and   = ty_R & op_21_20_d[1] & op_19_15_d[ 9];
    wire inst_or    = ty_R & op_21_20_d[1] & op_19_15_d[10];
    wire inst_xor   = ty_R & op_21_20_d[1] & op_19_15_d[11];
    wire inst_sll_w = ty_R & op_21_20_d[1] & op_19_15_d[14];
    wire inst_srl_w = ty_R & op_21_20_d[1] & op_19_15_d[15];
    wire inst_sra_w = ty_R & op_21_20_d[1] & op_19_15_d[16];
    
    // MD: Multiply/Divide instructions
    //   mul.w mulh.w mulh.wu div.w mod.w div.wu mod.wu
    wire ty_MD        = op_31_26_d[0] & op_25_22_d[0] & ((inst[21:18] == 4'b0111) | (inst[21:18] == 4'b1000));
    wire inst_mul_w   = ty_MD & op_21_20_d[1] & (inst[17:15] == 3'b000); 
    wire inst_mulh_w  = ty_MD & op_21_20_d[1] & (inst[17:15] == 3'b001); 
    wire inst_mulh_wu = ty_MD & op_21_20_d[1] & (inst[17:15] == 3'b010); 
    wire inst_div_w   = ty_MD & op_21_20_d[2] & (inst[17:15] == 3'b000); 
    wire inst_mod_w   = ty_MD & op_21_20_d[2] & (inst[17:15] == 3'b001); 
    wire inst_div_wu  = ty_MD & op_21_20_d[2] & (inst[17:15] == 3'b010); 
    wire inst_mod_wu  = ty_MD & op_21_20_d[2] & (inst[17:15] == 3'b011); 
    // S: Reg-Imm Shift
    //   slli.w srli.w srai.w
    wire ty_S        = op_31_26_d[0] & op_25_22_d[1];
    wire inst_slli_w = ty_S & op_21_20_d[0] & op_19_15_d[ 1];
    wire inst_srli_w = ty_S & op_21_20_d[0] & op_19_15_d[ 9];
    wire inst_srai_w = ty_S & op_21_20_d[0] & op_19_15_d[17];
    // I: Reg-Imm Arithmetic
    //   slti sltui addi.w andi ori xori
    wire ty_I        = op_31_26_d[0] & inst[25];
    wire inst_slti   = ty_I & op_25_22_d[ 8];
    wire inst_sltui  = ty_I & op_25_22_d[ 9];
    wire inst_addi_w = ty_I & op_25_22_d[10];
    wire inst_andi   = ty_I & op_25_22_d[13];
    wire inst_ori    = ty_I & op_25_22_d[14];
    wire inst_xori   = ty_I & op_25_22_d[15];
    // M: Memory
    //   ld.b ld.h ld.w ld.bu ld.hu st.b st.h st.w
    wire ty_M       = op_31_26_d[10];
    wire ty_M_LD    = ty_M & ~inst[24];
    wire ty_M_ST    = ty_M &  inst[24];
    wire inst_ld_b  = ty_M & op_25_22_d[0];
    wire inst_ld_h  = ty_M & op_25_22_d[1];
    wire inst_ld_w  = ty_M & op_25_22_d[2];
    wire inst_st_b  = ty_M & op_25_22_d[4];
    wire inst_st_h  = ty_M & op_25_22_d[5];
    wire inst_st_w  = ty_M & op_25_22_d[6];
    wire inst_ld_bu = ty_M & op_25_22_d[8];
    wire inst_ld_hu = ty_M & op_25_22_d[9];
    // U: Upper Immediate
    //   lu12i.w pcaddu12i.w
    wire ty_U           = op_31_26_d[5] | op_31_26_d[7];
    wire inst_lu12i_w   = ty_U & ~inst[27];
    wire inst_pcaddu12i = ty_U &  inst[27];
    // B: Branch
    //   jirl b bl beq bne blt bge bltu bgeu
    wire ty_B      = inst[30];
    wire ty_B_COND = ty_B & (|op_31_26_d[27:22]);
    wire inst_jirl = ty_B & op_31_26_d[19];
    wire inst_b    = ty_B & op_31_26_d[20];
    wire inst_bl   = ty_B & op_31_26_d[21];
    wire inst_beq  = ty_B & op_31_26_d[22];
    wire inst_bne  = ty_B & op_31_26_d[23];
    wire inst_blt  = ty_B & op_31_26_d[24];
    wire inst_bge  = ty_B & op_31_26_d[25];
    wire inst_bltu = ty_B & op_31_26_d[26];
    wire inst_bgeu = ty_B & op_31_26_d[27];

    // ALU operation encoding (extended to 18 bits for multiply/divide)
    assign alu_op[0]  = inst_add_w | inst_addi_w | ty_M |
                        inst_jirl  | inst_bl     | inst_pcaddu12i;
    assign alu_op[1]  = inst_sub_w;
    assign alu_op[2]  = inst_slt   | inst_slti;
    assign alu_op[3]  = inst_sltu  | inst_sltui;
    assign alu_op[4]  = inst_and   | inst_andi;
    assign alu_op[5]  = inst_nor;
    assign alu_op[6]  = inst_or    | inst_ori;
    assign alu_op[7]  = inst_xor   | inst_xori;
    assign alu_op[8]  = inst_sll_w | inst_slli_w;
    assign alu_op[9]  = inst_srl_w | inst_srli_w;
    assign alu_op[10] = inst_sra_w | inst_srai_w;
    assign alu_op[11] = inst_lu12i_w;
    // Multiply/Divide operation encoding
    assign alu_op[12] = inst_mul_w;    // MUL.W: 32x32->32 (low part)
    assign alu_op[13] = inst_mulh_w;   // MULH.W: 32x32->32 (high part, signed)
    assign alu_op[14] = inst_mulh_wu;  // MULH.WU: 32x32->32 (high part, unsigned)
    assign alu_op[15] = inst_div_w;    // DIV.W: signed division
    assign alu_op[16] = inst_mod_w;    // MOD.W: signed modulo
    assign alu_op[17] = inst_div_wu;   // DIV.WU: unsigned division
    assign alu_op[18] = inst_mod_wu;   // MOD.WU: unsigned modulo

    // Immediate type selection
    assign need_ui5  = ty_S;
    assign need_si12 = (ty_I & ~inst_andi & ~inst_ori & ~inst_xori) | ty_M;
    assign need_ui12 = inst_andi | inst_ori | inst_xori;
    assign need_si16 = ty_B & ~(inst_b | inst_bl);
    assign need_si20 = ty_U;
    assign need_si26 = inst_b | inst_bl;
    assign src2_is_4 = inst_jirl | inst_bl;

    // Immediate value generation
    assign imm = src2_is_4 ? 32'h4 :
                 need_si20 ? {i20[19:0], 12'b0} :
                 need_si12 ? {{20{i12[11]}}, i12[11:0]} :
                 need_ui12 ? {20'd0, i12[11:0]} :
                 need_ui5  ? {27'd0, inst[14:10]} :
                 32'd0;

    assign br_offs   = need_si26 ? {{4{i26[25]}}, i26[25:0], 2'b0} :
                                   {{14{i16[15]}}, i16[15:0], 2'b0};
    assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    // Control signal generation
    assign src_reg_is_rd = ty_B_COND | ty_M_ST;
    assign src1_is_pc = inst_jirl | inst_bl | inst_pcaddu12i;
    assign src2_is_imm = ty_S | ty_I | ty_M | ty_U | inst_jirl | inst_bl;

    assign res_from_mem = ty_M_LD;
    assign dst_is_r1 = inst_bl;
    assign gr_we = ~(ty_M_ST | ty_B_COND | inst_b) & id_valid;
    assign mem_op = {4{ty_M}} & op_25_22;
    assign dest = dst_is_r1 ? 5'd1 : rd;

    // ALU source selection
    assign alu_src1 = src1_is_pc ? id_pc : rj_value;
    assign alu_src2 = src2_is_imm ? imm : rkd_value;

    // Register file interface
    assign rf_raddr1 = rj;
    assign rf_raddr2 = src_reg_is_rd ? rd : rk;
    assign id_rf_we = gr_we;
    assign id_rf_waddr = dest;

    // Decode dataforwarding data
    assign {wb_rf_we, wb_rf_waddr, wb_rf_wdata} = wb_rf_zip;
    assign {mem_rf_we, mem_rf_waddr, mem_rf_wdata} = mem_rf_zip;
    assign {exe_res_from_mem, exe_rf_we, exe_rf_waddr, exe_rf_wdata} = exe_rf_zip;

    regfile u_regfile(
        .clk    (clk),
        .raddr1 (rf_raddr1),
        .rdata1 (rf_rdata1),
        .raddr2 (rf_raddr2),
        .rdata2 (rf_rdata2),
        .we     (wb_rf_we),
        .waddr  (wb_rf_waddr),
        .wdata  (wb_rf_wdata)
    );

    assign conflict_r1_wb   = (|rf_raddr1) & (rf_raddr1 == wb_rf_waddr) & wb_rf_we;
    assign conflict_r2_wb   = (|rf_raddr2) & (rf_raddr2 == wb_rf_waddr) & wb_rf_we;
    assign conflict_r1_mem  = (|rf_raddr1) & (rf_raddr1 == mem_rf_waddr) & mem_rf_we;
    assign conflict_r2_mem  = (|rf_raddr2) & (rf_raddr2 == mem_rf_waddr) & mem_rf_we;
    assign conflict_r1_exe  = (|rf_raddr1) & (rf_raddr1 == exe_rf_waddr) & exe_rf_we;
    assign conflict_r2_exe  = (|rf_raddr2) & (rf_raddr2 == exe_rf_waddr) & exe_rf_we;
    assign need_r1          = ~src1_is_pc & (|alu_op);
    assign need_r2          = ~src2_is_imm & ((|alu_op[11:0]) | ty_MD);
    assign rj_value  =  conflict_r1_exe ? exe_rf_wdata:
                        conflict_r1_mem ? mem_rf_wdata:
                        conflict_r1_wb  ? wb_rf_wdata : rf_rdata1;
    assign rkd_value =  conflict_r2_exe ? exe_rf_wdata:
                        conflict_r2_mem ? mem_rf_wdata:
                        conflict_r2_wb  ? wb_rf_wdata : rf_rdata2;

    // Output assignments
    //                      19      1             32        32        4       1         5            32         32
    assign id_to_exe_zip = {alu_op, res_from_mem, alu_src1, alu_src2, mem_op, id_rf_we, id_rf_waddr, rkd_value, id_pc};

endmodule
