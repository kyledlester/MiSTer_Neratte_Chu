// M10/M12 bench: sprite renderer vs the Python golden model on real MAME state dumps.
//   +SPR=<f>_spr.bin +VREG=<f>_vreg.bin +CHA=<f>_cha.bin +OUT=<out.bin>
// Sprite RAM is written through nrc_spriteram's CPU port (exercising the write FIFO and snapshot),
// then a snapshot starts the renderer; character RAM is a behavioural SDRAM client with random
// 6..20-cycle latency. The finished framebuffer (320x240, 16-bit LE pens) is written to +OUT for
// scripts/research/st0016_ref.py --cmpidx.
`timescale 1ns/1ps
module m10_render_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1;

    string fspr, fvreg, fcha, fout;
    logic [16:0] dump_addr = 0;
    logic [7:0] cha [0:2097151];
    logic [7:0] vreg [0:255];

    // sprite RAM
    logic [15:0] c_addr = 0; logic c_we = 0; logic [7:0] c_wd = 0; logic c_busy;
    logic snap = 0, go, rdone;
    logic [12:0] raddr; logic [63:0] rdata;
    nrc_spriteram spram (.clk(clk), .reset(reset), .cpu_addr(c_addr), .cpu_we(c_we), .cpu_wdata(c_wd),
        .cpu_rdata(), .cpu_busy(c_busy), .snap(snap), .render_go(go), .render_done(rdone),
        .render_active(), .r_addr(raddr), .r_data(rdata), .snap_drops(), .fifo_max());

    logic [7:0] scroll [32];
    logic [7:0] tm_base [8];
    logic [7:0] tm_prio, tm_merge;
    logic m_req, m_ack = 0; logic [24:0] m_addr; logic [63:0] m_rdata;
    logic [16:0] fb_raddr, fb_waddr; logic [10:0] fb_rdata, fb_wdata; logic fb_we;
    logic [15:0] st_tiles, st_fetched; logic [23:0] st_cycles;
    nrc_render #(.CHA_BASE(25'h0800000)) render (
        .clk(clk), .reset(reset), .go(go), .done(rdone), .busy(), .scroll(scroll), .tm_base(tm_base), .tm_prio(tm_prio), .tm_merge(tm_merge),
        .spr_addr(raddr), .spr_data(rdata),
        .m_req(m_req), .m_addr(m_addr), .m_ack(m_ack), .m_rdata(m_rdata),
        .fb_raddr(fb_raddr), .fb_rdata(fb_rdata), .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata),
        .st_tiles(st_tiles), .st_fetched(st_fetched), .st_cycles(st_cycles));
    logic [16:0] d_addr = 0; logic [10:0] d_data;
    nrc_framebuffer fb (.clk(clk), .r_buf(1'b0), .r_addr(fb_raddr), .r_rdata(fb_rdata), .r_we(fb_we),
        .r_waddr(fb_waddr), .r_wdata(fb_wdata), .d_addr(d_addr), .d_data(d_data));

    // behavioural char RAM client
    int seed = 11;
    always @(posedge clk) begin
        m_ack <= 0;
        if (m_req && !m_ack) begin
            int lat; lat = 6 + $urandom(seed) % 15;
            repeat (lat) @(posedge clk);
            for (int k = 0; k < 8; k++) m_rdata[8*k +: 8] <= cha[((m_addr - 25'h0800000) & ~25'd7) + k];
            m_ack <= 1;
        end
    end

    initial begin
        int fd, n;
        if (!$value$plusargs("SPR=%s", fspr) || !$value$plusargs("VREG=%s", fvreg) ||
            !$value$plusargs("CHA=%s", fcha) || !$value$plusargs("OUT=%s", fout)) begin
            $display("FAIL M10 RENDER: missing plusargs"); $finish;
        end
        fd = $fopen(fcha, "rb"); n = $fread(cha, fd); $fclose(fd);
        fd = $fopen(fvreg, "rb"); n = $fread(vreg, fd); $fclose(fd);
        for (int i = 0; i < 32; i++) scroll[i] = vreg[8'h40 + i];
        for (int j = 0; j < 8; j++) begin
            tm_base[j]  = vreg[8 * j + 1];
            tm_prio[j]  = (vreg[8 * j + 3] == 8'hFF);
            tm_merge[j] = (vreg[8 * j + 7] == 8'h12);
        end
        repeat (5) @(posedge clk); reset = 0;
        begin
            logic [7:0] spr [0:65535];
            fd = $fopen(fspr, "rb"); n = $fread(spr, fd); $fclose(fd);
            for (int i = 0; i < 65536; i++) begin
                @(posedge clk iff !c_busy); c_addr <= i; c_wd <= spr[i]; c_we <= 1;
                @(posedge clk); c_we <= 0;
            end
        end
        @(posedge clk); snap <= 1; @(posedge clk); snap <= 0;
        fork
            @(posedge clk iff rdone);
            begin repeat (20_000_000) @(posedge clk); $display("FAIL M10 RENDER: timeout"); $finish; end
        join_any
        disable fork;
        // dump framebuffer: buffer 0 is the render buffer; display port reads buffer 1, so read
        // back through the render port's read address instead (renderer idle now).
        fd = $fopen(fout, "wb");
        force render.fb_raddr = dump_addr;
        for (int i = 0; i < 76800; i++) begin
            dump_addr = 17'(i);
            @(posedge clk); @(posedge clk); #1;
            $fwrite(fd, "%c%c", fb_rdata[7:0], {5'd0, fb_rdata[10:8]});
        end
        release render.fb_raddr;
        $fclose(fd);
        $display("RENDER STATS tiles=%0d fetched=%0d cycles=%0d (%.2f ms @100.227 MHz)",
                 st_tiles, st_fetched, st_cycles, st_cycles / 100227.272);
        $display("PASS M10 RENDER: frame written to %s (compare with st0016_ref.py --cmpidx)", fout);
        $finish;
    end
endmodule
