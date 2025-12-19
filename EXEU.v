`include "macros.h"
module EXEU(
    input wire                       clk,
    input wire                       resetn,

    // Global flush from WB (exception/ertn)
    input wire                       flush,

    // Pipeline interface with ID stage
    output wire                      exe_allowin,
    input wire                       id_to_exe_valid,
    input wire [`ID2EXE_LEN - 1:0]   id_to_exe_zip,

    // Pipeline interface with MEM stage
    input wire                       mem_allowin,
    output wire                      exe_to_mem_valid,
    output wire [`EXE2MEM_LEN - 1:0] exe_to_mem_zip,

    // Data Cache interface
    output wire                      data_valid,
    output wire                      data_op,
    output wire [ 7:0]               data_index,
    output wire [19:0]               data_tag,
    output wire [ 3:0]               data_offset,
    output wire [ 3:0]               data_wstrb,
    output wire [31:0]               data_wdata,
    output wire                      data_uncache,
    input wire                       data_addr_ok,
    input wire                       data_data_ok,
    input wire [31:0]                data_rdata,

    // Data forwarding to ID stage
    output wire [39:0]               exe_rf_zip, // {exe_res_from_mem, exe_rf_we, exe_rf_waddr, exe_alu_result}

    // Exception signal forwarding from MEM and WB stage
    input wire                       mem_ex,
    input wire                       wb_ex,

    // CSR helper signals
    input wire [18:0]                csr_tlbehi_vppn,
    input wire [9:0]                 csr_asid_asid,
    input wire                       csr_crmd_da_value,
    input wire                       csr_crmd_pg_value,
    input wire [1:0]                 csr_crmd_plv_value,
    input wire [1:0]                 csr_crmd_datm_value,
    input wire [31:0]                csr_dmw0_value,
    input wire [31:0]                csr_dmw1_value,

    // TLB related (Port 1)
    output wire [18:0]               s1_vppn,
    output wire                      s1_va_bit12,
    output wire [9:0]                s1_asid,
    input wire                       s1_found,
    input wire [3:0]                 s1_index,
    input wire [19:0]                s1_ppn,
    input wire [5:0]                 s1_ps,
    input wire [1:0]                 s1_plv,
    input wire [1:0]                 s1_mat,
    input wire                       s1_d,
    input wire                       s1_v,
    // TLB invalid
    output wire                      tlb_invtlb_valid,
    output wire [4:0]                tlb_invtlb_op
);

    // Pipeline control
    reg         exe_valid;

    reg  [31:0] exe_pc;
    reg  [18:0] exe_alu_op;
    reg  [31:0] exe_alu_src1;
    reg  [31:0] exe_alu_src2;
    reg         exe_res_from_mem;
    reg  [ 3:0] exe_mem_op;
    reg  [31:0] exe_rkd_value;
    reg         exe_rf_we;
    reg  [ 4:0] exe_rf_waddr;
    // CNT inst pipeline fields
    reg         exe_rdcntvl;
    reg         exe_rdcntvh;
    // CSR pipeline fields
    reg         exe_csr_read;
    reg         exe_csr_we;
    reg  [13:0] exe_csr_num;
    reg  [31:0] exe_csr_wmask;
    reg  [31:0] exe_csr_wvalue;
    // TLB pipeline fields
    reg  [2:0]  exe_tlb_op;
    reg  [4:0]  exe_invtlb_op;
    // Exception pipeline fields
    reg         exe_ex_valid;
    reg  [5:0]  exe_ecode;
    reg  [8:0]  exe_esubcode;
    reg         exe_is_ertn;

    wire [31:0] exe_alu_result;
    wire [31:0] final_result;

    // 64-bit stable clock counter
    reg [63:0] stable_clk_counter;
    
    // Multiply/Divide control signals
    wire        mul_busy;
    wire        mul_done;
    wire        div_busy;
    wire        div_done;
    wire [63:0] mul_product;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    wire        div_by_zero;
    
    // Multi-cycle operation detection
    wire        is_mul_op;
    wire        is_div_op;
    wire        is_multicycle_op;
    
    // Multi-cycle execution state machine
    reg         multicycle_executing;
    wire        exe_ready_go;

    // Execute multicycle operation only if there is no exception
    // Including: mul, div, memory
    wire   exe_multicycle_ok = exe_valid & ~(mem_ex | wb_ex | exe_to_mem_ex_valid | exe_to_mem_is_ertn);
    
    assign is_mul_op = exe_alu_op[12] | exe_alu_op[13] | exe_alu_op[14];
    assign is_div_op = exe_alu_op[15] | exe_alu_op[16] | exe_alu_op[17] | exe_alu_op[18];
    assign is_multicycle_op = is_mul_op | is_div_op;

    // Pipeline state control with proper timing
    always @(posedge clk) begin
        if (~resetn) begin
            multicycle_executing <= 1'b0;
        end else begin
            if (start_multicycle) begin
                // Start multi-cycle execution
                multicycle_executing <= 1'b1;
            end else if (multicycle_executing) begin
                // Wait for completion of multi-cycle operation
                if ((is_mul_op & mul_done) | (is_div_op & div_done))
                    multicycle_executing <= 1'b0;
            end
        end
    end
        
    wire   start_multicycle;
    assign start_multicycle = is_multicycle_op & start_exe & exe_multicycle_ok;  // Special time stamp
    
    // EXE ready_go: no pending multicycle ops and memory request done
    assign exe_ready_go = ~start_multicycle & ~multicycle_executing & (~exe_mem_req | exe_mem_req & data_addr_ok);
    assign exe_allowin = ~exe_valid | (exe_ready_go & mem_allowin);
    assign exe_to_mem_valid = exe_valid & exe_ready_go;

    always @(posedge clk) begin
        if (~resetn)
            exe_valid <= 1'b0;
        else if (flush)
            exe_valid <= 1'b0;
        else if (multicycle_executing | start_multicycle)
            exe_valid <= 1'b1;
        else if (exe_allowin)
            exe_valid <= id_to_exe_valid;
    end

    // Pipeline register updates
    reg start_exe;
    always @(posedge clk) begin
        if (id_to_exe_valid & exe_allowin) begin
            {exe_alu_op, exe_res_from_mem, exe_alu_src1, exe_alu_src2, exe_mem_op, exe_rf_we, exe_rf_waddr,
             exe_rkd_value, exe_pc,
             exe_rdcntvl, exe_rdcntvh,
             exe_csr_read, exe_csr_we, exe_csr_num, exe_csr_wmask, exe_csr_wvalue,
             exe_ex_valid, exe_ecode, exe_esubcode, exe_is_ertn,
             exe_tlb_op, exe_invtlb_op} <= id_to_exe_zip;
            start_exe <= 1'b1;
        end else
            start_exe <= 1'b0;
    end

    // Address Translation
    wire is_dmw0 =
         (exe_alu_result[31:29] == csr_dmw0_value[31:29]) &&
         ((csr_crmd_plv_value == 2'd0) && (csr_dmw0_value[0]) ||
          (csr_crmd_plv_value == 2'd3) && (csr_dmw0_value[3]));
    wire is_dmw1 =
         (exe_alu_result[31:29] == csr_dmw1_value[31:29]) &&
         ((csr_crmd_plv_value == 2'd0) && (csr_dmw1_value[0]) ||
          (csr_crmd_plv_value == 2'd3) && (csr_dmw1_value[3]));
    wire [31:0] paddr =
                csr_crmd_pg_value ?
                ( is_dmw0 ? {csr_dmw0_value[27:25], exe_alu_result[28:0]} :
                  is_dmw1 ? {csr_dmw1_value[27:25], exe_alu_result[28:0]} :
                  ( (s1_ps == 12) ?
                    {s1_ppn[19:0], exe_alu_result[11:0]} :
                    {s1_ppn[19:9], exe_alu_result[20:0]} )
                 ) : exe_alu_result;

    // Exception generation
    // Address alignment check for memory operations
    wire is_mem_op = (exe_mem_op != 4'd0);
    wire is_half_op = (exe_mem_op == 4'd1) | (exe_mem_op == 4'd5) | (exe_mem_op == 4'd9); // ld.h, st.h, ld.hu
    wire is_word_op = (exe_mem_op == 4'd2) | (exe_mem_op == 4'd6); // ld.w, st.w
    
    wire addr_align_error    = is_mem_op & ((is_half_op & paddr[0]) |        // Half-word must be 2-byte aligned
                                            (is_word_op & (|paddr[1:0]))     // Word must be 4-byte aligned
                                            );
    wire tlb_gen_error       = is_mem_op & csr_crmd_pg_value & !is_dmw0 & !is_dmw1;
    wire tlb_refill_error    = tlb_gen_error & !s1_found;
    wire load_invalid_error  = tlb_gen_error & !is_store & s1_found & !s1_v;
    wire store_invalid_error = tlb_gen_error &  is_store & s1_found & !s1_v;
    wire tlb_plv_error       = tlb_gen_error & s1_found & s1_v & (csr_crmd_plv_value > s1_plv);
    wire tlb_modify_error    = tlb_gen_error & s1_found & s1_v & is_store & !s1_d;
    
    wire        exe_gen_ex_valid =
                addr_align_error   | tlb_refill_error    |
                load_invalid_error | store_invalid_error |
                tlb_plv_error      | tlb_modify_error;
    wire [5:0]  exe_gen_ecode    =
                addr_align_error    ? `ECODE_ALE  :
                tlb_refill_error    ? `ECODE_TLBR :
                load_invalid_error  ? `ECODE_PIL  :
                store_invalid_error ? `ECODE_PIS  :
                tlb_plv_error       ? `ECODE_PPI  :
                tlb_modify_error    ? `ECODE_PME  :
                6'd0;
    wire [8:0]  exe_gen_esubcode = `ESUBCODE_NONE;

    wire        exe_to_mem_ex_valid = exe_gen_ex_valid ? 1'b1 : exe_ex_valid;
    wire [5:0]  exe_to_mem_ecode    = exe_gen_ex_valid ? exe_gen_ecode : exe_ecode;
    wire [8:0]  exe_to_mem_esubcode = exe_gen_ex_valid ? exe_gen_esubcode : exe_esubcode;
    wire        exe_to_mem_is_ertn  = exe_is_ertn;

    // 64-bit stable clock counter for rdcntvl.w and rdcntvh.w instructions
    always @(posedge clk) begin
        if (~resetn) begin
            stable_clk_counter <= 64'd0;
        end else begin
            stable_clk_counter <= stable_clk_counter + 1'b1;
        end
    end

    // ALU instantiation (only handles first 12 bits for regular ALU operations)
    alu u_alu(
        .alu_op     (exe_alu_op[11:0]),
        .alu_src1   (exe_alu_src1),
        .alu_src2   (exe_alu_src2),
        .alu_result (exe_alu_result)
    );
    
    // Start signals for multiply/divide operations
    reg mul_start;
    reg div_start;
    
    always @(posedge clk) begin
        if (~resetn) begin
            mul_start <= 1'b0;
            div_start <= 1'b0;
        end else begin
            // Start signal active for one cycle when new multicycle instruction arrives
            mul_start <= is_mul_op & start_multicycle;
            div_start <= is_div_op & start_multicycle;
        end
    end
    
    // Multiply module instantiation
    mul u_mul(
        .clk         (clk),
        .resetn      (resetn),
        .start       (mul_start),
        .signed_mode (exe_alu_op[12] | exe_alu_op[13]), // signed for MUL.W and MULH.W
        .op_a        (exe_alu_src1),
        .op_b        (exe_alu_src2),
        .busy        (mul_busy),
        .done        (mul_done),
        .product     (mul_product)
    );
    
    // Divide module instantiation  
    div u_div(
        .clk           (clk),
        .resetn        (resetn),
        .start         (div_start),
        .signed_mode   (exe_alu_op[15] | exe_alu_op[16]), // signed for DIV.W and MOD.W
        .dividend      (exe_alu_src1),
        .divisor       (exe_alu_src2),
        .busy          (div_busy),
        .done          (div_done),
        .divide_by_zero(div_by_zero),
        .quotient      (div_quotient),
        .remainder     (div_remainder)
    );

    // Result selection logic for multiply/divide/cnt operations
    assign final_result = exe_alu_op[12] ? mul_product[31:0] :         // MUL.W: low 32 bits
                          exe_alu_op[13] ? mul_product[63:32] :        // MULH.W: high 32 bits (signed)
                          exe_alu_op[14] ? mul_product[63:32] :        // MULH.WU: high 32 bits (unsigned)
                          exe_alu_op[15] ? div_quotient :              // DIV.W: quotient (signed)
                          exe_alu_op[16] ? div_remainder :             // MOD.W: remainder (signed)
                          exe_alu_op[17] ? div_quotient :              // DIV.WU: quotient (unsigned)
                          exe_alu_op[18] ? div_remainder :             // MOD.WU: remainder (unsigned)
                          exe_rdcntvl    ? stable_clk_counter[31: 0] : // RDCNTVL: stable counter low 32 bits
                          exe_rdcntvh    ? stable_clk_counter[63:32] : // RDCNTVH: stable counter high 32 bits
                          exe_alu_result;                              // Regular ALU result

    // TLB search / INVTLB interface (port 1)
    assign s1_vppn     = (exe_tlb_op == `TLB_OP_SRCH) ? csr_tlbehi_vppn :
                         (exe_tlb_op == `TLB_OP_INV ) ? exe_rkd_value[31:13] :
                         is_mem_op                    ? exe_alu_result[31:13] :
                         19'd0;
    assign s1_va_bit12 = (exe_tlb_op == `TLB_OP_SRCH) ? 1'b0 :
                         (exe_tlb_op == `TLB_OP_INV ) ? exe_rkd_value[12] :
                         is_mem_op                    ? exe_alu_result[12] :
                         1'b0;
    assign s1_asid     = (exe_tlb_op == `TLB_OP_SRCH) ? csr_asid_asid :
                         (exe_tlb_op == `TLB_OP_INV ) ? exe_alu_src1[9:0] :
                         is_mem_op                    ? csr_asid_asid :
                         10'd0;
    assign tlb_invtlb_op  = exe_invtlb_op;
    assign tlb_invtlb_valid = exe_to_mem_valid & (exe_tlb_op == `TLB_OP_INV);

    // DCache interface
    wire addr0 = (paddr[1:0] == 2'd0);
    wire addr1 = (paddr[1:0] == 2'd1);
    wire addr2 = (paddr[1:0] == 2'd2);
    wire addr3 = (paddr[1:0] == 2'd3);

    wire is_byte_op = (exe_mem_op == 4'd0) | (exe_mem_op == 4'd4) | (exe_mem_op == 4'd8);  // ld.b, st.b, ld.bu
    wire is_store = exe_mem_op[2];  // st.b, st.h, st.w

    // Only send request when MEM stage allows in (simplified design)
    wire   exe_mem_req;
    assign exe_mem_req = (exe_res_from_mem | is_store) & exe_multicycle_ok;

    wire [1:0] data_mat = 
               !csr_crmd_pg_value ? csr_crmd_datm_value : // DA mode: cacheable by default
               ( is_dmw0 ? csr_dmw0_value[5:4] :     // DMW0 MAT
                 is_dmw1 ? csr_dmw1_value[5:4] :     // DMW1 MAT
                 s1_mat                              // TLB MAT
                 );
    
    assign data_valid = exe_mem_req & exe_valid & mem_allowin;
    assign data_op    = is_store;
    assign data_wstrb =   // st.b
                          (exe_mem_op == 4'd4) ?
                          ( addr0 ? 4'b0001 :
                            addr1 ? 4'b0010 :
                            addr2 ? 4'b0100 :
                            addr3 ? 4'b1000 :
                            4'b0000) :
                          // st.h
                          (exe_mem_op == 4'd5) ?
                          ( (addr0 | addr1) ? 4'b0011 :
                            (addr2 | addr3) ? 4'b1100 :
                            4'b0000 ) :
                          // st.w
                          (exe_mem_op == 4'd6) ?
                          ( 4'b1111 ) : 4'b0000;
    assign data_index  = paddr[11: 4];
    assign data_tag    = paddr[31:12];
    assign data_offset = paddr[ 3:0];
    assign data_wdata  = // st.b
                         (exe_mem_op == 4'd4) ?
                         ( addr0 ? {24'd0, exe_rkd_value[7:0]       } :
                           addr1 ? {16'd0, exe_rkd_value[7:0],  8'd0} :
                           addr2 ? { 8'd0, exe_rkd_value[7:0], 16'd0} :
                           addr3 ? {       exe_rkd_value[7:0], 24'd0} :
                           32'd0 ) :
                         // st.h
                         (exe_mem_op == 4'd5) ?
                         ( (addr0 | addr1) ? {16'd0, exe_rkd_value[15:0]} :
                           (addr2 | addr3) ? {exe_rkd_value[15:0], 16'd0} :
                           32'd0 ) :
                         // st.w
                         (exe_mem_op == 4'd6) ?
                         ( exe_rkd_value ) :
                         // default
                         32'd0;
    assign data_uncache = (data_mat == 2'b00);  // SUC (MAT=0): uncached

    // CSR value adjustment for TLB search
    // TLBSRCH only updates NE (bit 31) and Index (bit 3:0), PS field is preserved
    // Use combinational signals directly from TLB module, not pipeline registers
    wire [31:0] tlbsrch_wvalue = {~s1_found, 7'd0, 20'd0, s1_index};
    wire [31:0] tlbsrch_wmask  = 32'h8000_000f;  // Only update bit 31 (NE) and bit 3:0 (Index)
    wire [13:0] exe_csr_num_final    = (exe_tlb_op == `TLB_OP_SRCH) ? `CSR_TLBIDX : exe_csr_num;
    wire        exe_csr_we_final     = (exe_tlb_op == `TLB_OP_SRCH) ? 1'b1        : exe_csr_we;
    wire        exe_csr_read_final   = (exe_tlb_op == `TLB_OP_SRCH) ? 1'b0        : exe_csr_read;
    wire [31:0] exe_csr_wmask_final  = (exe_tlb_op == `TLB_OP_SRCH) ? tlbsrch_wmask : exe_csr_wmask;
    wire [31:0] exe_csr_wvalue_final = (exe_tlb_op == `TLB_OP_SRCH) ? tlbsrch_wvalue : exe_csr_wvalue;

    // Forward data to IDU
    assign exe_rf_zip = {
            exe_valid & (exe_csr_read_final | exe_csr_we_final),
            exe_valid & exe_res_from_mem,
            exe_valid & exe_rf_we,
            exe_rf_waddr,
            final_result
    };

    // Output assignment
    assign exe_to_mem_zip = {
            exe_mem_req,
            exe_res_from_mem,
            exe_rf_we,
            exe_rf_waddr,
            final_result,
            exe_mem_op,
            exe_pc,

            exe_csr_read_final,
            exe_csr_we_final,
            exe_csr_num_final,
            exe_csr_wmask_final,
            exe_csr_wvalue_final,
            
            exe_ex_valid ? exe_pc : exe_alu_result,  // vaddr for BADV register

            exe_to_mem_ex_valid,
            exe_to_mem_ecode,
            exe_to_mem_esubcode,
            exe_to_mem_is_ertn,

            exe_tlb_op,
            exe_invtlb_op
    };

endmodule
