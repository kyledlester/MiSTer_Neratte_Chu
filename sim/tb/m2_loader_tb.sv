// M2 bench: ROM loader -> SDRAM arbiter -> vendored sdram.sv -> SDRAM model.
// A synthetic stream (byte k = hash(k)) is downloaded through an hps_io-like ioctl driver
// (WIDE=1, honours ioctl_wait, random gaps); then the bench reads back through a second arbiter
// client: every 8-byte group of the stream, the zero-filled extrom padding, and the zeroed
// character RAM (the model returns 0xA5C3 for never-written cells, so zero proves the fill).
// It also checks the fixed-ROM BRAM mirror writes (stream bytes < 0x8000). Sizes are scaled down
// by parameters so the fill completes quickly; the RTL is identical.
`timescale 1ns/1ps
module m2_loader_tb;
    localparam int STREAM   = 'h9000;        // crosses the 0x8000 fixed-ROM boundary
    localparam int EXT_END  = 'hA000;
    localparam int CHA_BASE = 'h10000;
    localparam int CHA_END  = 'h10800;

    logic clk = 0;
    always #4.989 clk = ~clk;
    logic init = 1;

    function automatic logic [7:0] hb(int k);
        return 8'((k * 37) ^ (k >> 8) ^ (k >> 13) ^ 8'h5A);
    endfunction

    // ioctl driver
    logic        dl = 0, wr = 0;
    logic [26:0] ioa = 0;
    logic [15:0] iod = 0;
    logic        iowait;

    // loader
    logic        l_req, l_ack; logic [24:0] l_addr; logic [15:0] l_wdata;
    logic        from_we; logic [13:0] from_addr; logic [15:0] from_data;
    logic        rom_ready, loading; logic [24:0] sbytes;
    nrc_loader #(.EXTROM_END(EXT_END), .CHA_BASE(CHA_BASE), .CHA_END(CHA_END)) loader (
        .clk(clk), .init(init), .ioctl_download(dl), .ioctl_index(16'd0), .ioctl_wr(wr),
        .ioctl_addr(ioa), .ioctl_dout(iod), .ioctl_wait(iowait),
        .m_req(l_req), .m_addr(l_addr), .m_wdata(l_wdata), .m_ack(l_ack),
        .from_we(from_we), .from_addr(from_addr), .from_data(from_data),
        .rom_ready(rom_ready), .loading(loading), .stream_bytes(sbytes));

    // read-back client
    logic        r_req = 0; logic [24:0] r_addr = 0; logic r_ack;
    logic [1:0] ack; logic [63:0] rdata;
    logic [26:1] sd_addr; logic [15:0] sd_din; logic [1:0] sd_be; logic sd_req, sd_rnw, sd_ready;
    logic [63:0] sd_dout;
    nrc_sdram_arb #(.N(2)) arb (
        .clk(clk), .rst(init), .req({r_req, l_req}), .we({1'b0, 1'b1}),
        .addr('{r_addr, l_addr}), .wdata('{16'h0, l_wdata}), .be('{2'b11, 2'b11}),
        .ack(ack), .rdata(rdata), .owner(), .busy(),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready));
    assign l_ack = ack[0];
    assign r_ack = ack[1];

    wire [15:0] DQ; wire [12:0] A; wire [1:0] BA;
    wire DQML, DQMH, nCS, nWE, nRAS, nCAS, CKE, SCLK;
    sdram #(.CYCLES_PER_REFRESH(14'd780)) ctl (
        .init(init), .clk(clk),
        .SDRAM_DQ(DQ), .SDRAM_A(A), .SDRAM_DQML(DQML), .SDRAM_DQMH(DQMH), .SDRAM_BA(BA),
        .SDRAM_nCS(nCS), .SDRAM_nWE(nWE), .SDRAM_nRAS(nRAS), .SDRAM_nCAS(nCAS), .SDRAM_CKE(CKE),
        .SDRAM_CLK(SCLK),
        .ch1_addr(sd_addr), .ch1_dout(sd_dout), .ch1_din(sd_din), .ch1_be(sd_be), .ch1_req(sd_req),
        .ch1_rnw(sd_rnw), .ch1_ready(sd_ready),
        .ch2_addr('0), .ch2_dout(), .ch2_din('0), .ch2_req(1'b0), .ch2_rnw(1'b1), .ch2_ready(),
        .ch3_addr('0), .ch3_dout(), .ch3_din('0), .ch3_req(1'b0), .ch3_rnw(1'b1), .ch3_ready());
    sdr_sdram_model #(.TCK_NS(9.978)) chip (
        .clk(SCLK), .cke(CKE), .csn(nCS), .rasn(nRAS), .casn(nCAS), .wen(nWE),
        .ba(BA), .a(A), .dqml(DQML), .dqmh(DQMH), .dq(DQ));

    int errors = 0, checks = 0;
    task automatic check(bit c, string m);
        checks++;
        if (!c) begin errors++; if (errors <= 10) $display("FAIL: %s", m); end
    endtask

    // fixed-ROM mirror capture
    logic [15:0] from_mem [16384];
    int from_writes = 0;
    always @(posedge clk) if (from_we) begin from_mem[from_addr] = from_data; from_writes++; end

    task automatic rd8(input int addr, output logic [63:0] d);
        @(posedge clk); r_addr <= 25'(addr); r_req <= 1;
        @(posedge clk iff r_ack); d = rdata; r_req <= 0;
    endtask

    int seed = 7;
    initial begin
        logic [63:0] d;
        repeat (20) @(posedge clk);
        init = 0;
        repeat (13000) @(posedge clk);   // SDRAM controller startup
        // download
        dl <= 1;
        repeat (5) @(posedge clk);
        for (int k = 0; k < STREAM; k += 2) begin
            @(posedge clk iff !iowait);
            wr <= 1; ioa <= k; iod <= {hb(k + 1), hb(k)};
            @(posedge clk); wr <= 0;
            repeat ($urandom(seed) % 4) @(posedge clk);
        end
        @(posedge clk iff !iowait);
        repeat (3) @(posedge clk);
        dl <= 0;
        fork
            begin @(posedge clk iff rom_ready); end
            begin repeat (5_000_000) @(posedge clk); $display("FAIL M2 LOADER: timeout waiting for rom_ready"); $finish; end
        join_any
        disable fork;
        check(sbytes == STREAM, $sformatf("stream_bytes %0h", sbytes));
        check(from_writes == 'h8000 / 2, $sformatf("fixed ROM mirror writes %0d", from_writes));
        for (int w = 0; w < 'h4000; w++)
            check(from_mem[w] == {hb(2 * w + 1), hb(2 * w)}, $sformatf("fixed ROM word %0h", w));
        for (int g = 0; g < STREAM; g += 8) begin
            rd8(g, d);
            for (int b = 0; b < 8; b++) check(d[8*b +: 8] == hb(g + b), $sformatf("stream byte %0h = %02h exp %02h", g + b, d[8*b +: 8], hb(g + b)));
        end
        for (int g = STREAM; g < EXT_END; g += 8) begin rd8(g, d); check(d == 0, $sformatf("extrom pad %0h = %016h", g, d)); end
        for (int g = CHA_BASE; g < CHA_END; g += 8) begin rd8(g, d); check(d == 0, $sformatf("charram %0h = %016h", g, d)); end
        rd8(CHA_END, d);
        check(d == {4{16'hA5C3}}, "fill stops at CHA_END (untouched cell)");
        check(chip.errors == 0, $sformatf("SDRAM protocol errors %0d", chip.errors));
        if (errors == 0) $display("PASS M2 LOADER: %0d checks (stream %0h bytes, pad, charram, fixed-ROM mirror)", checks, STREAM);
        else $display("FAIL M2 LOADER: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
