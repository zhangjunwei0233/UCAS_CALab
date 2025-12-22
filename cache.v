// tagv_ram: 256×21bit, Use ENA Pin, Byte Write Not Enable
// data_bank_ram: 256×32bit, Use ENA Pin, Byte Write Enable (Byte Size 8)
// All RAMs Initialize to 0
module cache(
    input  wire        clk,
    input  wire        resetn,
    input  wire        cache_is_icache,

    // Interface between Cache and CPU
    input  wire        valid,       // Valid signal for CPU cache access request
    input  wire        op,          // Read or Write (1: WRITE, 0: READ)
    input  wire [ 7:0] index,       // vaddr[11:4] index
    input  wire [19:0] tag,         // paddr[31:12] tag
    input  wire [ 3:0] offset,      // vaddr[3:0] offset
    input  wire [ 3:0] wstrb,       // Byte write enable
    input  wire [31:0] wdata,       // Write data
    input  wire        uncache,     // Uncached access flag
    
    output wire        addr_ok,     // Address transfer completion signal
    output wire        data_ok,     // Data transfer completion signal
    output wire [31:0] rdata,       // Cache read data

    // Interface between Cache and Bus
    output wire        rd_req,      // Read request valid signal
    output wire [ 2:0] rd_type,     // Read request type
    output wire [31:0] rd_addr,     // Read request start address
    input  wire        rd_rdy,      // Whether read request is accepted
    input  wire        ret_valid,   // Return data valid
    input  wire        ret_last,    // Last return data of read request
    input  wire [31:0] ret_data,    // Read return data

    output wire        wr_req,      // Write request valid signal
    output wire [ 2:0] wr_type,     // Write request type
    output wire [31:0] wr_addr,     // Write request start address
    output wire [ 3:0] wr_wstrb,    // Write operation byte mask
    output wire [127:0] wr_data,    // Write data
    input  wire        wr_rdy,      // Whether write request can be accepted

    // CACOP interface
    input  wire        cacop_valid,
    input  wire [4:0]  cacop_code,
    output wire        cacop_rdy,
    output wire        cacop_done,
    input  wire [31:0] cacop_paddr,
    input  wire [7:0]  cacop_vaddr_index,
    input  wire        cacop_vaddr_bit0
);

    // CPU-->cache request type (op)
    localparam OP_READ  = 1'b0;
    localparam OP_WRITE = 1'b1;

    // cache-->memory read request type (rd_type)
    localparam RD_TYPE_BYTE     = 3'b000;
    localparam RD_TYPE_HALFWORD = 3'b001;
    localparam RD_TYPE_WORD     = 3'b010;
    localparam RD_TYPE_BLOCK    = 3'b100;

    // cache-->memory write request type (wr_type)
    localparam WR_TYPE_BYTE     = 3'b000;
    localparam WR_TYPE_HALFWORD = 3'b001;
    localparam WR_TYPE_WORD     = 3'b010;
    localparam WR_TYPE_BLOCK    = 3'b100;

    // Main state machine states
    localparam STATE_IDLE    = 5'b00001;
    localparam STATE_LOOKUP  = 5'b00010;
    localparam STATE_MISS    = 5'b00100;
    localparam STATE_REPLACE = 5'b01000;
    localparam STATE_REFILL  = 5'b10000;

    // Write Buffer state machine states
    localparam WB_STATE_IDLE  = 2'b01;
    localparam WB_STATE_WRITE = 2'b10;

    // TAGV RAM interface signals
    wire [ 7:0] tagv_addr;
    wire [20:0] tagv_wdata;
    wire [20:0] tagv_way0_rdata;
    wire [20:0] tagv_way1_rdata;
    wire        tagv_way0_en;
    wire        tagv_way1_en;
    wire        tagv_way0_we;
    wire        tagv_way1_we;

    // DATA Bank RAM interface signals
    wire [ 7:0] data_addr;
    wire [31:0] data_wdata;
    wire [31:0] data_way0_bank0_rdata;
    wire [31:0] data_way0_bank1_rdata;
    wire [31:0] data_way0_bank2_rdata;
    wire [31:0] data_way0_bank3_rdata;
    wire [31:0] data_way1_bank0_rdata;
    wire [31:0] data_way1_bank1_rdata;
    wire [31:0] data_way1_bank2_rdata;
    wire [31:0] data_way1_bank3_rdata;
    wire        data_way0_bank0_en;
    wire        data_way0_bank1_en;
    wire        data_way0_bank2_en;
    wire        data_way0_bank3_en;
    wire        data_way1_bank0_en;
    wire        data_way1_bank1_en;
    wire        data_way1_bank2_en;
    wire        data_way1_bank3_en;
    wire [ 3:0] data_way0_bank0_we;
    wire [ 3:0] data_way0_bank1_we;
    wire [ 3:0] data_way0_bank2_we;
    wire [ 3:0] data_way0_bank3_we;
    wire [ 3:0] data_way1_bank0_we;
    wire [ 3:0] data_way1_bank1_we;
    wire [ 3:0] data_way1_bank2_we;
    wire [ 3:0] data_way1_bank3_we;

    // Cache RAM instantiation
    // TAGV RAM - Way 0
    tagv_ram tagv_way0_inst (
        .clka   (clk),
        .ena    (tagv_way0_en),
        .wea    (tagv_way0_we),
        .addra  (tagv_addr),
        .dina   (tagv_wdata),
        .douta  (tagv_way0_rdata)
    );

    // TAGV RAM - Way 1
    tagv_ram tagv_way1_inst (
        .clka   (clk),
        .ena    (tagv_way1_en),
        .wea    (tagv_way1_we),
        .addra  (tagv_addr),
        .dina   (tagv_wdata),
        .douta  (tagv_way1_rdata)
    );

    // DATA Bank RAM - Way 0
    data_bank_ram data_way0_bank0_inst (
        .clka   (clk),
        .ena    (data_way0_bank0_en),
        .wea    (data_way0_bank0_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way0_bank0_rdata)
    );

    data_bank_ram data_way0_bank1_inst (
        .clka   (clk),
        .ena    (data_way0_bank1_en),
        .wea    (data_way0_bank1_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way0_bank1_rdata)
    );

    data_bank_ram data_way0_bank2_inst (
        .clka   (clk),
        .ena    (data_way0_bank2_en),
        .wea    (data_way0_bank2_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way0_bank2_rdata)
    );

    data_bank_ram data_way0_bank3_inst (
        .clka   (clk),
        .ena    (data_way0_bank3_en),
        .wea    (data_way0_bank3_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way0_bank3_rdata)
    );

    // DATA Bank RAM - Way 1
    data_bank_ram data_way1_bank0_inst (
        .clka   (clk),
        .ena    (data_way1_bank0_en),
        .wea    (data_way1_bank0_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way1_bank0_rdata)
    );

    data_bank_ram data_way1_bank1_inst (
        .clka   (clk),
        .ena    (data_way1_bank1_en),
        .wea    (data_way1_bank1_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way1_bank1_rdata)
    );

    data_bank_ram data_way1_bank2_inst (
        .clka   (clk),
        .ena    (data_way1_bank2_en),
        .wea    (data_way1_bank2_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way1_bank2_rdata)
    );

    data_bank_ram data_way1_bank3_inst (
        .clka   (clk),
        .ena    (data_way1_bank3_en),
        .wea    (data_way1_bank3_we),
        .addra  (data_addr),
        .dina   (data_wdata),
        .douta  (data_way1_bank3_rdata)
    );

    // Dirty bit table
    // Implemented using registers, 256 entries per way
    reg [255:0] dirty_way0;
    reg [255:0] dirty_way1;

    // CACOP request buffer and control
    wire        cacop_op_impl = cacop_valid && (cacop_code[4:3] == 2'b11);
    reg         cacop_req_valid;
    reg  [4:0]  cacop_req_code;
    reg  [7:0]  cacop_req_index;
    reg  [19:0] cacop_req_tag;
    reg         cacop_req_way;
    reg         cacop_req_is_query;
    reg         cacop_wb_pending;
    reg         cacop_wb_way;
    reg  [19:0] cacop_wb_tag;

    // State machines
    reg [4:0] main_state;
    reg [4:0] main_next_state;
    reg [1:0] wb_state;
    reg [1:0] wb_next_state;

    // Request Buffer
    reg        req_op;
    reg [ 7:0] req_index;
    reg [19:0] req_tag;
    reg [ 3:0] req_offset;
    reg [ 3:0] req_wstrb;
    reg [31:0] req_wdata;
    reg        req_uncache;

    // Miss Buffer
    reg [ 1:0] refill_word_cnt;     // Count of words returned
    reg        replace_way_reg;     // Record the way to replace

    // Write Buffer
    reg        write_way;
    reg [ 1:0] write_bank;
    reg [ 7:0] write_index;
    reg [ 3:0] write_strb;
    reg [31:0] write_data;

    // LFSR (pseudo-random replacement algorithm)
    reg [2:0] lfsr;
    always @(posedge clk) begin
        if (~resetn) begin
            lfsr <= 3'b111;
        end else if (ret_valid && ret_last) begin
            // Linear feedback shift register update
            lfsr <= {lfsr[0], lfsr[1] ^ lfsr[0], lfsr[2]};
        end
    end

    // CACOP request capture
    wire cacop_accept = cacop_valid && cacop_rdy && !cacop_op_impl;
    wire cacop_use_req = cacop_req_valid || cacop_accept;
    wire cacop_req_op_init = (cacop_req_code[4:3] == 2'b00);
    wire cacop_req_op_idx  = (cacop_req_code[4:3] == 2'b01);
    wire cacop_req_op_qry  = (cacop_req_code[4:3] == 2'b10);
    wire cacop_done_pulse;
    wire cacop_wb_active;

    always @(posedge clk) begin
        if (~resetn) begin
            cacop_req_valid <= 1'b0;
            cacop_req_code <= 5'b0;
            cacop_req_index <= 8'b0;
            cacop_req_tag <= 20'b0;
            cacop_req_way <= 1'b0;
            cacop_req_is_query <= 1'b0;
        end else begin
            if (cacop_accept) begin
                cacop_req_valid <= 1'b1;
                cacop_req_code <= cacop_code;
                if (cacop_code[4:3] == 2'b10) begin
                    cacop_req_index <= cache_is_icache ? cacop_vaddr_index : cacop_paddr[11:4];
                    cacop_req_tag <= cacop_paddr[31:12];
                    cacop_req_way <= 1'b0;
                    cacop_req_is_query <= 1'b1;
                end else begin
                    cacop_req_index <= cacop_vaddr_index;
                    cacop_req_tag <= 20'b0;
                    cacop_req_way <= cacop_vaddr_bit0;
                    cacop_req_is_query <= 1'b0;
                end
            end else if (cacop_done_pulse) begin
                cacop_req_valid <= 1'b0;
            end
        end
    end

    // Tag Compare
    wire        way0_v;
    wire        way0_d;
    wire [19:0] way0_tag;
    wire        way1_v;
    wire        way1_d;
    wire [19:0] way1_tag;
    wire        way0_hit_req;
    wire        way1_hit_req;
    wire        way0_hit_cacop;
    wire        way1_hit_cacop;
    wire        cache_hit;

    wire [7:0] dirty_index = cacop_req_valid ? cacop_req_index : req_index;

    assign {way0_tag, way0_v} = tagv_way0_rdata;
    assign {way1_tag, way1_v} = tagv_way1_rdata;
    assign way0_d = dirty_way0[dirty_index];
    assign way1_d = dirty_way1[dirty_index];

    assign way0_hit_req = way0_v && (way0_tag == req_tag) && !req_uncache;
    assign way1_hit_req = way1_v && (way1_tag == req_tag) && !req_uncache;
    assign cache_hit = (way0_hit_req || way1_hit_req) && !req_uncache;

    assign way0_hit_cacop = way0_v && (way0_tag == cacop_req_tag);
    assign way1_hit_cacop = way1_v && (way1_tag == cacop_req_tag);

    // Data Select
    wire [127:0] way0_load_block;
    wire [127:0] way1_load_block;
    wire [ 31:0] way0_load_word;
    wire [ 31:0] way1_load_word;
    wire [ 31:0] load_result;

    assign way0_load_block = {data_way0_bank3_rdata, data_way0_bank2_rdata, 
                              data_way0_bank1_rdata, data_way0_bank0_rdata};
    assign way1_load_block = {data_way1_bank3_rdata, data_way1_bank2_rdata, 
                              data_way1_bank1_rdata, data_way1_bank0_rdata};
    
    assign way0_load_word = way0_load_block[req_offset[3:2] * 32 +: 32];
    assign way1_load_word = way1_load_block[req_offset[3:2] * 32 +: 32];

    assign load_result = ({32{way0_hit_req}} & way0_load_word) |
                         ({32{way1_hit_req}} & way1_load_word) |
                         ({32{main_state == STATE_REFILL}} & ret_data);

    // Replace selection
    wire         replace_way;
    wire [127:0] replace_data;
    wire         replace_dirty;

    assign replace_way = (main_state == STATE_MISS) ? lfsr[0] : replace_way_reg;
    assign replace_data = replace_way ? way1_load_block : way0_load_block;
    assign replace_dirty = (replace_way == 1'b0 && dirty_way0[req_index] && way0_v) ||
                           (replace_way == 1'b1 && dirty_way1[req_index] && way1_v);

    // Conflict detection
    wire cacop_block = cacop_req_valid || cacop_accept;
    wire valid_normal = valid && !cacop_block;

    // Conflict case 1: Write Buffer is writing, and new request is read operation, accessing the same bank
    wire conflict_case1 = (wb_state == WB_STATE_WRITE) &&
                          valid_normal && (op == OP_READ) &&
                          (offset[3:2] == write_bank);

    // Conflict case 2: Write hit detected in LOOKUP state, and new request is read operation, accessing the same address
    wire conflict_case2 = (main_state == STATE_LOOKUP) &&
                          (req_op == OP_WRITE) &&
                          valid_normal && (op == OP_READ) &&
                          ({tag, index, offset[3:2]} == {req_tag, req_index, req_offset[3:2]});

    // CACOP lookup helpers
    wire cacop_lookup = (main_state == STATE_LOOKUP) && cacop_req_valid;
    wire cacop_lookup_way0 = cacop_req_is_query ? way0_hit_cacop : (cacop_req_way == 1'b0);
    wire cacop_lookup_way1 = cacop_req_is_query ? way1_hit_cacop : (cacop_req_way == 1'b1);
    wire cacop_lookup_hit = cacop_lookup_way0 || cacop_lookup_way1;
    wire cacop_need_wb_lookup = cacop_lookup && !cache_is_icache &&
                                (cacop_req_op_idx || cacop_req_op_qry) &&
                                cacop_lookup_hit &&
                                ((cacop_lookup_way0 && way0_v && way0_d) ||
                                 (cacop_lookup_way1 && way1_v && way1_d));

    // Main state machine
    always @(posedge clk) begin
        if (~resetn) begin
            main_state <= STATE_IDLE;
        end else begin
            main_state <= main_next_state;
        end
    end

    always @(*) begin
        case (main_state)
            STATE_IDLE: begin
                if (cacop_req_valid || (cacop_valid && !cacop_op_impl)) begin
                    main_next_state = STATE_LOOKUP;
                end else if (valid_normal && !conflict_case1) begin
                    main_next_state = STATE_LOOKUP;
                end else begin
                    main_next_state = STATE_IDLE;
                end
            end
            STATE_LOOKUP: begin
                if (cacop_req_valid) begin
                    if (cacop_need_wb_lookup) begin
                        main_next_state = STATE_MISS;
                    end else begin
                        main_next_state = STATE_IDLE;
                    end
                end else if (!cache_hit || req_uncache) begin
                    main_next_state = STATE_MISS;
                end else if (!valid_normal || conflict_case1 || conflict_case2) begin
                    main_next_state = STATE_IDLE;
                end else begin
                    main_next_state = STATE_LOOKUP;
                end
            end
            STATE_MISS: begin
                if (cacop_wb_active) begin
                    if (wr_rdy) begin
                        main_next_state = STATE_IDLE;
                    end else begin
                        main_next_state = STATE_MISS;
                    end
                end else if (req_uncache && req_op && wr_rdy) begin
                    main_next_state = STATE_IDLE;
                end else if (wr_rdy || (req_uncache && !req_op) ||
                             (!req_uncache && !replace_dirty)) begin
                    main_next_state = STATE_REPLACE;
                end else begin
                    main_next_state = STATE_MISS;
                end
            end
            STATE_REPLACE: begin
                if (rd_rdy) begin
                    main_next_state = STATE_REFILL;
                end else begin
                    main_next_state = STATE_REPLACE;
                end
            end
            STATE_REFILL: begin
                if (ret_valid && ret_last) begin
                    main_next_state = STATE_IDLE;
                end else begin
                    main_next_state = STATE_REFILL;
                end
            end
            default: begin
                main_next_state = STATE_IDLE;
            end
        endcase
    end

    // Write Buffer state machine
    always @(posedge clk) begin
        if (~resetn) begin
            wb_state <= WB_STATE_IDLE;
        end else begin
            wb_state <= wb_next_state;
        end
    end

    always @(*) begin
        case (wb_state)
            WB_STATE_IDLE: begin
                if ((main_state == STATE_LOOKUP) && (req_op == OP_WRITE) && cache_hit) begin
                    wb_next_state = WB_STATE_WRITE;
                end else begin
                    wb_next_state = WB_STATE_IDLE;
                end
            end
            WB_STATE_WRITE: begin
                if ((main_state == STATE_LOOKUP) && (req_op == OP_WRITE) && cache_hit) begin
                    wb_next_state = WB_STATE_WRITE;
                end else begin
                    wb_next_state = WB_STATE_IDLE;
                end
            end
            default: begin
                wb_next_state = WB_STATE_IDLE;
            end
        endcase
    end

    // Cache operation types
    wire lookup;
    wire hitwrite;
    wire replace;
    wire replace_normal;
    wire refill;
    wire lookup_en;

    assign lookup = ((main_state == STATE_IDLE) && valid_normal && !conflict_case1) ||
                    ((main_state == STATE_LOOKUP) && valid_normal && cache_hit && 
                     !conflict_case1 && !conflict_case2);
    assign hitwrite = (wb_state == WB_STATE_WRITE);
    assign replace_normal = (main_state == STATE_MISS) || (main_state == STATE_REPLACE);
    assign replace = replace_normal && !cacop_wb_active;
    assign refill = (main_state == STATE_REFILL);

    // lookup_en is used for RAM chip select, avoiding combinational loops
    assign lookup_en = ((main_state == STATE_IDLE) && valid_normal && !conflict_case1) ||
                       ((main_state == STATE_LOOKUP) && valid_normal && 
                        !conflict_case1 && !conflict_case2);

    // Request Buffer update
    always @(posedge clk) begin
        if (~resetn) begin
            req_op      <= 1'b0;
            req_index   <= 8'b0;
            req_tag     <= 20'b0;
            req_offset  <= 4'b0;
            req_wstrb   <= 4'b0;
            req_wdata   <= 32'b0;
            req_uncache <= 1'b0;
        end else if (lookup) begin
            req_op      <= op;
            req_index   <= index;
            req_tag     <= tag;
            req_offset  <= offset;
            req_wstrb   <= wstrb;
            req_wdata   <= wdata;
            req_uncache <= uncache;
        end
    end

    // CACOP writeback tracking
    always @(posedge clk) begin
        if (~resetn) begin
            cacop_wb_pending <= 1'b0;
            cacop_wb_way <= 1'b0;
            cacop_wb_tag <= 20'b0;
        end else begin
            if (cacop_need_wb_lookup) begin
                cacop_wb_pending <= 1'b1;
                cacop_wb_way <= cacop_lookup_way1;
                cacop_wb_tag <= cacop_lookup_way1 ? way1_tag : way0_tag;
            end else if (cacop_done_pulse) begin
                cacop_wb_pending <= 1'b0;
            end
        end
    end

    // Miss Buffer update
    always @(posedge clk) begin
        if (~resetn) begin
            refill_word_cnt <= 2'b0;
            replace_way_reg <= 1'b0;
        end else begin
            if (main_state == STATE_MISS && main_next_state == STATE_REPLACE) begin
                replace_way_reg <= lfsr[0];
            end
            
            if (main_state == STATE_REPLACE && main_next_state == STATE_REFILL) begin
                refill_word_cnt <= 2'b0;
            end else if (main_state == STATE_REFILL && ret_valid) begin
                refill_word_cnt <= refill_word_cnt + 2'b1;
            end
        end
    end

    // Write Buffer update
    always @(posedge clk) begin
        if (~resetn) begin
            write_way   <= 1'b0;
            write_bank  <= 2'b0;
            write_index <= 8'b0;
            write_strb  <= 4'b0;
            write_data  <= 32'b0;
        end else if ((main_state == STATE_LOOKUP) && (req_op == OP_WRITE) && cache_hit) begin
            write_way   <= way1_hit_req;
            write_bank  <= req_offset[3:2];
            write_index <= req_index;
            write_strb  <= req_wstrb;
            write_data  <= req_wdata;
        end
    end

    // Refill data preparation
    wire [31:0] refill_word;
    wire [31:0] mixed_word;

    // If miss caused by write operation, need to mix write data and return data
    assign mixed_word = {
        req_wstrb[3] ? req_wdata[31:24] : ret_data[31:24],
        req_wstrb[2] ? req_wdata[23:16] : ret_data[23:16],
        req_wstrb[1] ? req_wdata[15: 8] : ret_data[15: 8],
        req_wstrb[0] ? req_wdata[ 7: 0] : ret_data[ 7: 0]
    };

    assign refill_word = ((refill_word_cnt == req_offset[3:2]) && (req_op == OP_WRITE)) ?
                         mixed_word : ret_data;

    // CACOP invalidate/writeback control
    wire cacop_done_lookup = cacop_lookup && !cacop_need_wb_lookup;
    wire cacop_wb_fire = (main_state == STATE_MISS) && cacop_wb_active && wr_rdy;
    assign cacop_done_pulse = cacop_done_lookup || cacop_wb_fire;

    wire cacop_do_invalidate_lookup = cacop_done_lookup && cacop_lookup_hit;
    wire cacop_do_invalidate_miss = cacop_wb_fire;
    wire cacop_clear_way0 = (cacop_do_invalidate_lookup && cacop_lookup_way0) ||
                            (cacop_do_invalidate_miss && !cacop_wb_way);
    wire cacop_clear_way1 = (cacop_do_invalidate_lookup && cacop_lookup_way1) ||
                            (cacop_do_invalidate_miss &&  cacop_wb_way);
    assign cacop_wb_active = cacop_wb_pending && cacop_req_valid;
    wire cacop_wb_read = cacop_wb_active;
    wire cacop_wb_way0 = cacop_wb_read && (cacop_wb_way == 1'b0);
    wire cacop_wb_way1 = cacop_wb_read && (cacop_wb_way == 1'b1);

    // TAGV RAM control signals
    assign tagv_way0_en = lookup_en || ((replace || refill) && (replace_way == 1'b0)) ||
                          cacop_use_req || cacop_clear_way0;
    assign tagv_way1_en = lookup_en || ((replace || refill) && (replace_way == 1'b1)) ||
                          cacop_use_req || cacop_clear_way1;
    
    assign tagv_way0_we = (refill && (replace_way == 1'b0) && ret_valid &&
                          (refill_word_cnt == req_offset[3:2]) && !req_uncache) ||
                          cacop_clear_way0;
    assign tagv_way1_we = (refill && (replace_way == 1'b1) && ret_valid &&
                          (refill_word_cnt == req_offset[3:2]) && !req_uncache) ||
                          cacop_clear_way1;
    
    assign tagv_wdata = (cacop_clear_way0 || cacop_clear_way1) ? {20'b0, 1'b0} : {req_tag, 1'b1};
    assign tagv_addr = cacop_use_req ? (cacop_req_valid ? cacop_req_index :
                        (cacop_code[4:3] == 2'b10 ?
                         (cache_is_icache ? cacop_vaddr_index : cacop_paddr[11:4]) :
                         cacop_vaddr_index)) :
                        (lookup_en ? index : req_index);

    // DATA Bank RAM control signals
    // Way 0 Bank enable
    assign data_way0_bank0_en = (lookup_en && (offset[3:2] == 2'b00)) ||
                                (hitwrite && (write_way == 1'b0)) ||
                                ((replace || refill) && (replace_way == 1'b0)) ||
                                cacop_wb_way0;
    assign data_way0_bank1_en = (lookup_en && (offset[3:2] == 2'b01)) ||
                                (hitwrite && (write_way == 1'b0)) ||
                                ((replace || refill) && (replace_way == 1'b0)) ||
                                cacop_wb_way0;
    assign data_way0_bank2_en = (lookup_en && (offset[3:2] == 2'b10)) ||
                                (hitwrite && (write_way == 1'b0)) ||
                                ((replace || refill) && (replace_way == 1'b0)) ||
                                cacop_wb_way0;
    assign data_way0_bank3_en = (lookup_en && (offset[3:2] == 2'b11)) ||
                                (hitwrite && (write_way == 1'b0)) ||
                                ((replace || refill) && (replace_way == 1'b0)) ||
                                cacop_wb_way0;

    // Way 1 Bank enable
    assign data_way1_bank0_en = (lookup_en && (offset[3:2] == 2'b00)) ||
                                (hitwrite && (write_way == 1'b1)) ||
                                ((replace || refill) && (replace_way == 1'b1)) ||
                                cacop_wb_way1;
    assign data_way1_bank1_en = (lookup_en && (offset[3:2] == 2'b01)) ||
                                (hitwrite && (write_way == 1'b1)) ||
                                ((replace || refill) && (replace_way == 1'b1)) ||
                                cacop_wb_way1;
    assign data_way1_bank2_en = (lookup_en && (offset[3:2] == 2'b10)) ||
                                (hitwrite && (write_way == 1'b1)) ||
                                ((replace || refill) && (replace_way == 1'b1)) ||
                                cacop_wb_way1;
    assign data_way1_bank3_en = (lookup_en && (offset[3:2] == 2'b11)) ||
                                (hitwrite && (write_way == 1'b1)) ||
                                ((replace || refill) && (replace_way == 1'b1)) ||
                                cacop_wb_way1;

    // Way 0 Bank write enable
    assign data_way0_bank0_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b00)}} & write_strb |
                                {4{refill && (replace_way == 1'b0) && (refill_word_cnt == 2'b00) && ret_valid && !req_uncache}};
    assign data_way0_bank1_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b01)}} & write_strb |
                                {4{refill && (replace_way == 1'b0) && (refill_word_cnt == 2'b01) && ret_valid && !req_uncache}};
    assign data_way0_bank2_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b10)}} & write_strb |
                                {4{refill && (replace_way == 1'b0) && (refill_word_cnt == 2'b10) && ret_valid && !req_uncache}};
    assign data_way0_bank3_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b11)}} & write_strb |
                                {4{refill && (replace_way == 1'b0) && (refill_word_cnt == 2'b11) && ret_valid && !req_uncache}};

    // Way 1 Bank write enable
    assign data_way1_bank0_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b00)}} & write_strb |
                                {4{refill && (replace_way == 1'b1) && (refill_word_cnt == 2'b00) && ret_valid && !req_uncache}};
    assign data_way1_bank1_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b01)}} & write_strb |
                                {4{refill && (replace_way == 1'b1) && (refill_word_cnt == 2'b01) && ret_valid && !req_uncache}};
    assign data_way1_bank2_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b10)}} & write_strb |
                                {4{refill && (replace_way == 1'b1) && (refill_word_cnt == 2'b10) && ret_valid && !req_uncache}};
    assign data_way1_bank3_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b11)}} & write_strb |
                                {4{refill && (replace_way == 1'b1) && (refill_word_cnt == 2'b11) && ret_valid && !req_uncache}};

    // DATA address and data
    assign data_wdata = refill ? refill_word :
                        (hitwrite ? write_data : 32'b0);
    assign data_addr = cacop_wb_read ? cacop_req_index :
                       (replace || refill) ? req_index :
                       (hitwrite ? write_index :
                       (lookup_en ? index : 8'b0));

    // Dirty table update
    always @(posedge clk) begin
        if (~resetn) begin
            dirty_way0 <= 256'b0;
            dirty_way1 <= 256'b0;
        end else begin
            if (hitwrite) begin
                if (way0_hit_req) begin
                    dirty_way0[write_index] <= 1'b1;
                end else if (way1_hit_req) begin
                    dirty_way1[write_index] <= 1'b1;
                end
            end else if (refill && ret_valid && (refill_word_cnt == req_offset[3:2]) && !req_uncache) begin
                if (replace_way == 1'b0) begin
                    dirty_way0[req_index] <= req_op;  // Set to 1 for write operation, set to 0 for read operation
                end else begin
                    dirty_way1[req_index] <= req_op;
                end
            end else if (cacop_clear_way0) begin
                dirty_way0[cacop_req_index] <= 1'b0;
            end else if (cacop_clear_way1) begin
                dirty_way1[cacop_req_index] <= 1'b0;
            end
        end
    end

    // Cache --> CPU output signals
    assign addr_ok = (!cacop_block && (main_state == STATE_IDLE)) ||
                     ((main_state == STATE_LOOKUP) && cache_hit &&
                      valid_normal && !conflict_case1 && !conflict_case2);

    assign data_ok = !cacop_block &&
                     (((main_state == STATE_LOOKUP) && (cache_hit || (req_op == OP_WRITE))) ||
                      ((main_state == STATE_REFILL) && ret_valid &&
                       ((req_uncache && (req_op == OP_READ)) ||  // Uncache: return immediately
                        (!req_uncache && (refill_word_cnt == req_offset[3:2]) && (req_op == OP_READ)))));

    assign rdata = load_result;

    // CACOP output signals
    assign cacop_rdy = (main_state == STATE_IDLE) && !cacop_req_valid;
    assign cacop_done = cacop_done_pulse || (cacop_valid && cacop_op_impl);

    // Cache --> AXI output signals
    assign rd_req  = (main_state == STATE_REPLACE) && (!req_uncache || !req_op);
    assign rd_type = req_uncache ? RD_TYPE_WORD : RD_TYPE_BLOCK;  // Uncache uses word access
    assign rd_addr = req_uncache ? {req_tag, req_index, req_offset} :  // Full address for uncache
                                    {req_tag, req_index, 4'b0};          // Cache line address

    assign wr_req   = (main_state == STATE_MISS) &&
                      (replace_dirty || (req_uncache && req_op) || cacop_wb_active);
    assign wr_type  = cacop_wb_active ? WR_TYPE_BLOCK :
                      (req_uncache ? WR_TYPE_WORD : WR_TYPE_BLOCK);
    assign wr_addr  = cacop_wb_active ? {cacop_wb_tag, cacop_req_index, 4'b0} :
                      req_uncache ? {req_tag, req_index, req_offset}:
                      replace_way ? {way1_tag, req_index, 4'b0} :
                                    {way0_tag, req_index, 4'b0};
    assign wr_wstrb = cacop_wb_active ? 4'b1111 :
                      (req_uncache ? req_wstrb : 4'b1111);
    assign wr_data  = cacop_wb_active ? (cacop_wb_way ? way1_load_block : way0_load_block) :
                      req_uncache ? {96'd0, req_wdata} : replace_data;

endmodule
