module bridge
  ( output wire        clk,
    output wire        resetn,
    // inst sram-like interface
    input wire         inst_sram_req,
    input wire         inst_sram_wr,
    input wire [ 1:0]  inst_sram_size,
    input wire [31:0]  inst_sram_addr,
    input wire [ 3:0]  inst_sram_wstrb,
    input wire [31:0]  inst_sram_wdata,
    output wire        inst_sram_addr_ok,
    output wire        inst_sram_data_ok,
    output wire [31:0] inst_sram_rdata,
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

`define S_IDLE 5'b00001
`define S_AR   5'b00010
`define S_R    5'b00100
`define S_AW   5'b01000
`define S_B    5'b10000

    reg [4:0] state;
    reg [1:0] wready_buf; // Track AW and W handshakes
    reg       grant;      // 0 = inst, 1 = data
    reg       last_grant; // For round-robin when both request

    // Shortcut arrays for the two masters
    wire        sram_req   [1:0];
    wire        sram_wr    [1:0];
    wire [ 1:0] sram_size  [1:0];
    wire [31:0] sram_addr  [1:0];
    wire [ 3:0] sram_wstrb [1:0];
    wire [31:0] sram_wdata [1:0];
    assign sram_req[0]   = inst_sram_req;
    assign sram_req[1]   = data_sram_req;
    assign sram_wr[0]    = inst_sram_wr;
    assign sram_wr[1]    = data_sram_wr;
    assign sram_size[0]  = inst_sram_size;
    assign sram_size[1]  = data_sram_size;
    assign sram_addr[0]  = inst_sram_addr;
    assign sram_addr[1]  = data_sram_addr;
    assign sram_wstrb[0] = inst_sram_wstrb;
    assign sram_wstrb[1] = data_sram_wstrb;
    assign sram_wdata[0] = inst_sram_wdata;
    assign sram_wdata[1] = data_sram_wdata;

    // Handshake detection
    wire ar_hs, aw_hs, w_hs, b_hs, r_hs;
    wire aw_done, w_done;
    wire aw_done_next, w_done_next;
    assign aw_done      = wready_buf[0];
    assign w_done       = wready_buf[1];
    assign ar_hs        = (state == `S_AR) && sram_req[grant] && arready;
    assign aw_hs        = (state == `S_AW) && sram_req[grant] && awready && !aw_done;
    assign w_hs         = (state == `S_AW) && sram_req[grant] && wready  && !w_done;
    assign b_hs         = (state == `S_B)  && bvalid;
    assign r_hs         = (state == `S_R)  && rvalid;
    assign aw_done_next = aw_done | aw_hs;
    assign w_done_next  = w_done  | w_hs;

    // Master-visible handshakes
    wire        sram_addr_ok;
    wire        sram_data_ok;
    wire [31:0] sram_rdata;
    assign inst_sram_addr_ok = (grant == 1'b0) && sram_addr_ok;
    assign data_sram_addr_ok = (grant == 1'b1) && sram_addr_ok;
    assign inst_sram_data_ok = (grant == 1'b0) && sram_data_ok;
    assign data_sram_data_ok = (grant == 1'b1) && sram_data_ok;
    assign inst_sram_rdata   = sram_rdata;
    assign data_sram_rdata   = sram_rdata;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state      <= `S_IDLE;
            wready_buf <= 2'b00;
            grant      <= 1'b0;
            last_grant <= 1'b1; // so first tie-break favors inst (0)
        end else begin
            case (1'b1)
              state[0]: begin
                  // Idle: pick next request with simple round-robin to avoid starvation
                  wready_buf <= 2'b00;
                  if (sram_req[0] && sram_req[1]) begin
                      // Both asserted: alternate
                      grant <= ~last_grant;
                      state <= sram_wr[~last_grant] ? `S_AW : `S_AR;
                  end else if (sram_req[0]) begin
                      grant <= 1'b0;
                      state <= sram_wr[0] ? `S_AW : `S_AR;
                  end else if (sram_req[1]) begin
                      grant <= 1'b1;
                      state <= sram_wr[1] ? `S_AW : `S_AR;
                  end
              end
              state[1]: begin
                  // AR
                  if (!sram_req[grant]) begin
                      state <= `S_IDLE;          // cancelled before addr_ok
                  end else if (ar_hs) begin
                      state <= `S_R;
                  end
              end
              state[2]: begin
                  // R
                  if (r_hs) state <= `S_IDLE;
              end
              state[3]: begin
                  // AW/W
                  if (!sram_req[grant]) begin
                      wready_buf <= 2'b00;
                      state <= `S_IDLE;          // cancelled before addr_ok
                  end else begin
                      if (aw_hs) wready_buf[0] <= 1'b1;
                      if (w_hs)  wready_buf[1] <= 1'b1;
                      if (aw_done_next && w_done_next) begin
                          wready_buf <= 2'b00;
                          state <= `S_B;
                      end
                  end
              end
              state[4]: begin
                  // B
                  if (b_hs) state <= `S_IDLE;
              end
            endcase

            // Remember last granted master when a request is accepted
            if (sram_addr_ok)
                last_grant <= grant;
        end
    end

    assign sram_addr_ok = ar_hs | (aw_done_next & w_done_next);
    assign sram_data_ok = r_hs | b_hs;
    assign sram_rdata   = rdata;

    // AR channel
    assign arid    = {3'b000, grant};
    assign araddr  = sram_addr[grant];
    assign arlen   = 8'b0;
    assign arsize  = {1'b0, sram_size[grant]}; // map 1/2/4-byte to AXI size
    assign arburst = 2'b01;
    assign arlock  = 2'b00;
    assign arcache = 4'b0000;
    assign arprot  = 3'b000;
    assign arvalid = (state == `S_AR) && sram_req[grant];

    // R channel
    assign rready  = (state == `S_R);

    // AW channel
    assign awid    = {3'b000, grant};
    assign awaddr  = sram_addr[grant];
    assign awlen   = 8'b0;
    assign awsize  = {1'b0, sram_size[grant]};
    assign awburst = 2'b01;
    assign awlock  = 2'b00;
    assign awcache = 4'b0000;
    assign awprot  = 3'b000;
    assign awvalid = (state == `S_AW) && !aw_done && sram_req[grant];

    // W channel
    assign wid     = {3'b000, grant};
    assign wdata   = sram_wdata[grant];
    assign wstrb   = sram_wstrb[grant];
    assign wlast   = 1'b1;
    assign wvalid  = (state == `S_AW) && !w_done && sram_req[grant];

    // B channel
    assign bready  = (state == `S_B);
    
endmodule
