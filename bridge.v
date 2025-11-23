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
    reg [1:0] wready_buf; // Wait for both awready and wready
    
    reg         grant;
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
            state <= `S_IDLE;
            wready_buf <= 2'b00;
        end else begin
            case (1'b1)
              state[0]: begin
                  // Idle
                  wready_buf <= 2'b00;
                  if (sram_req[1]) begin
                      grant <= 1'b1;
                      state <= sram_wr[1] ? `S_AW : `S_AR;
                  end else if (sram_req[0]) begin
                      grant <= 1'b0;
                      state <= sram_wr[0] ? `S_AW : `S_AR;
                  end
              end
              state[1]: begin
                  // AR
                  if (sram_addr_ok) state <= `S_R;
              end
              state[2]: begin
                  // R
                  if (sram_data_ok) state <= `S_IDLE;
              end
              state[3]: begin
                  // AW
                  if (awready) wready_buf[0] <= 1'b1;
                  if (wready)  wready_buf[1] <= 1'b1;
                  if (sram_addr_ok) state <= `S_B;
              end
              state[4]: begin
                  // B
                  if (sram_data_ok) state <= `S_IDLE;
              end
            endcase
        end
    end
    assign sram_addr_ok = (state[1] && arready) ||
                          (state[3] && (awready || wready_buf[0]) && (wready || wready_buf[1]));
    assign sram_data_ok = (state[2] && rvalid) ||
                          (state[4] && bvalid);
    assign sram_rdata = rdata;

    assign arid    = {2'b00, grant};
    assign araddr  = sram_addr[grant];
    assign arlen   = 8'b0;
    assign arsize  = 3'b100;
    assign arburst = 2'b01;
    assign arlock  = 2'b00;
    assign arcache = 4'b0000;
    assign arprot  = 3'b000;
    assign arvalid = (state == `S_AR);

    assign rready  = (state == `S_R);

    assign awid    = {2'b00, grant};
    assign awaddr  = sram_addr[grant];
    assign awlen   = 8'b0;
    assign awsize  = 3'b100;
    assign awburst = 2'b01;
    assign awlock  = 2'b00;
    assign awcache = 4'b0000;
    assign awprot  = 3'b000;
    assign awvalid = (state == `S_AW) && !wready_buf[0];

    assign wid     = {2'b00, grant};
    assign wdata   = sram_wdata[grant];
    assign wstrb   = sram_wstrb[grant];
    assign wlast   = (state == `S_AW) && !wready_buf[1];
    assign wvalid  = (state == `S_AW) && !wready_buf[1];

    assign bready  = (state == `S_B);
    
endmodule
