module bridge
  ( output wire        clk,
    output wire        resetn,
    // ICache interface (Cache-AXI protocol)
    input wire         icache_rd_req,
    input wire [ 2:0]  icache_rd_type,
    input wire [31:0]  icache_rd_addr,
    output wire        icache_rd_rdy,
    output wire        icache_ret_valid,
    output wire        icache_ret_last,
    output wire [31:0] icache_ret_data,
    output wire        icache_wr_rdy,      // Always 1 for ICache (no write)
    // data sram-like interface
    input wire         data_sram_req,
    input wire         data_sram_wr,
    input wire [ 1:0]  data_sram_size,
    input wire [31:0]  data_sram_addr,
    input wire [ 3:0]  data_sram_wstrb,
    input wire [31:0]  data_sram_wdata,
    output wire        data_sram_addr_ok,
    output wire        data_sram_data_ok,
    output wire [31:0] data_sram_rdata,
    // AXI
    input wire         aclk,
    input wire         aresetn,
    // AR
    output wire [3:0]  arid,
    output wire [31:0] araddr,
    output wire [7:0]  arlen,
    output wire [2:0]  arsize,
    output wire [1:0]  arburst,
    output wire [1:0]  arlock,
    output wire [3:0]  arcache,
    output wire [2:0]  arprot,
    output wire        arvalid,
    input wire         arready,
    // R
    input wire [3:0]   rid,
    input wire [31:0]  rdata,
    input wire [1:0]   rresp,
    input wire         rlast,
    input wire         rvalid,
    output wire        rready,
    // AW
    output wire [3:0]  awid,
    output wire [31:0] awaddr,
    output wire [7:0]  awlen,
    output wire [2:0]  awsize,
    output wire [1:0]  awburst,
    output wire [1:0]  awlock,
    output wire [3:0]  awcache,
    output wire [2:0]  awprot,
    output wire        awvalid,
    input wire         awready,
    // W
    output wire [3:0]  wid,
    output wire [31:0] wdata,
    output wire [3:0]  wstrb,
    output wire        wlast,
    output wire        wvalid,
    input wire         wready,
    // B
    input wire [3:0]   bid,
    input wire [1:0]   bresp,
    input wire         bvalid,
    output wire        bready
    );

    assign clk    = aclk;
    assign resetn = aresetn;

    // State machine states
    localparam S_IDLE = 5'b00001;
    localparam S_AR   = 5'b00010;
    localparam S_R    = 5'b00100;
    localparam S_AW   = 5'b01000;
    localparam S_B    = 5'b10000;

    reg [4:0] state;
    reg [1:0] wready_buf;      // Track AW and W handshakes
    reg [1:0] grant;           // 0 = icache_rd, 1 = data_rd, 2 = data_wr
    reg [1:0] last_grant;      // For round-robin arbitration
    
    // Burst transfer support
    reg [2:0] burst_len;       // Number of beats in burst (0-3 for 1-4 beats)
    reg [2:0] burst_cnt;       // Current beat counter
    wire      is_burst;
    wire      burst_finish;
    
    assign is_burst = (grant == 2'd0) && (icache_rd_type == 3'b100); // Cache line read
    assign burst_finish = (burst_cnt == burst_len);

    // Request type decode for ICache
    wire [7:0] icache_arlen;
    wire [2:0] icache_arsize;
    assign icache_arlen  = (icache_rd_type == 3'b100) ? 8'd3 :  // Cache line: 4 beats
                           8'd0;                                 // Single word
    assign icache_arsize = (icache_rd_type == 3'b100) ? 3'b010 : // 4 bytes per beat
                           (icache_rd_type == 3'b010) ? 3'b010 : // word
                           (icache_rd_type == 3'b001) ? 3'b001 : // halfword
                           3'b000;                                // byte

    // Arbitration: priority ICache > Data
    wire icache_rd_req_valid = icache_rd_req;
    wire data_rd_req_valid   = data_sram_req && !data_sram_wr;
    wire data_wr_req_valid   = data_sram_req && data_sram_wr;

    // Handshake signals
    wire ar_hs, aw_hs, w_hs, b_hs, r_hs;
    wire aw_done, w_done;
    wire aw_done_next, w_done_next;
    
    assign aw_done      = wready_buf[0];
    assign w_done       = wready_buf[1];
    assign ar_hs        = (state == S_AR) && arvalid && arready;
    assign aw_hs        = (state == S_AW) && awvalid && awready;
    assign w_hs         = (state == S_AW) && wvalid && wready;
    assign b_hs         = (state == S_B) && bvalid && bready;
    assign r_hs         = (state == S_R) && rvalid && rready;
    assign aw_done_next = aw_done | aw_hs;
    assign w_done_next  = w_done | w_hs;

    // State machine
    always @(posedge aclk) begin
        if (!aresetn) begin
            state      <= S_IDLE;
            wready_buf <= 2'b00;
            grant      <= 2'd0;
            last_grant <= 2'd2;
            burst_len  <= 3'd0;
            burst_cnt  <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    wready_buf <= 2'b00;
                    burst_cnt  <= 3'd0;
                    
                    // Arbitration with priority: ICache read > Data read > Data write
                    if (icache_rd_req_valid) begin
                        grant <= 2'd0;
                        state <= S_AR;
                        burst_len <= (icache_rd_type == 3'b100) ? 3'd3 : 3'd0;
                    end else if (data_rd_req_valid) begin
                        grant <= 2'd1;
                        state <= S_AR;
                        burst_len <= 3'd0;
                    end else if (data_wr_req_valid) begin
                        grant <= 2'd2;
                        state <= S_AW;
                        burst_len <= 3'd0;
                    end
                end

                S_AR: begin
                    if (ar_hs) begin
                        state <= S_R;
                    end
                end

                S_R: begin
                    if (r_hs) begin
                        if (rlast || burst_finish) begin
                            state <= S_IDLE;
                            burst_cnt <= 3'd0;
                        end else begin
                            burst_cnt <= burst_cnt + 3'd1;
                        end
                    end
                end

                S_AW: begin
                    if (aw_hs) wready_buf[0] <= 1'b1;
                    if (w_hs)  wready_buf[1] <= 1'b1;
                    if (aw_done_next && w_done_next) begin
                        state <= S_B;
                    end
                end

                S_B: begin
                    wready_buf <= 2'b00;
                    if (b_hs) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ICache interface outputs
    assign icache_rd_rdy    = (state == S_AR) && (grant == 2'd0) && arready;
    assign icache_ret_valid = (state == S_R) && (grant == 2'd0) && rvalid;
    assign icache_ret_last  = (state == S_R) && (grant == 2'd0) && rvalid && burst_finish;
    assign icache_ret_data  = rdata;
    assign icache_wr_rdy    = 1'b1; // ICache never writes

    // Data SRAM interface outputs
    assign data_sram_addr_ok = ((state == S_AR) && (grant == 2'd1) && arready) ||
                               ((state == S_AW) && (grant == 2'd2) && aw_done_next && w_done_next);
    assign data_sram_data_ok = ((state == S_R) && (grant == 2'd1) && rvalid) ||
                               ((state == S_B) && (grant == 2'd2) && bvalid);
    assign data_sram_rdata   = rdata;

    // AR channel
    assign arid    = {2'b00, grant};
    assign araddr  = (grant == 2'd0) ? icache_rd_addr : data_sram_addr;
    assign arlen   = (grant == 2'd0) ? icache_arlen : 8'd0;
    assign arsize  = (grant == 2'd0) ? icache_arsize : {1'b0, data_sram_size};
    assign arburst = 2'b01; // INCR
    assign arlock  = 2'b00;
    assign arcache = 4'b0000;
    assign arprot  = 3'b000;
    assign arvalid = (state == S_AR);

    // R channel
    assign rready  = (state == S_R);

    // AW channel
    assign awid    = {2'b00, grant};
    assign awaddr  = data_sram_addr;
    assign awlen   = 8'd0;
    assign awsize  = {1'b0, data_sram_size};
    assign awburst = 2'b01;
    assign awlock  = 2'b00;
    assign awcache = 4'b0000;
    assign awprot  = 3'b000;
    assign awvalid = (state == S_AW) && !aw_done;

    // W channel
    assign wid     = {2'b00, grant};
    assign wdata   = data_sram_wdata;
    assign wstrb   = data_sram_wstrb;
    assign wlast   = 1'b1;
    assign wvalid  = (state == S_AW) && !w_done;

    // B channel
    assign bready  = (state == S_B);
    
endmodule
