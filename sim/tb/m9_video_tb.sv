// M9/M18 bench: measure nrc_core's native video output (what arcade_video passes to the analog
// output with Scandoubler Fx = None, and what the HDMI scaler samples).
// Measured over whole frames, in clk_sys cycles and real time (clk_sys = 100.227272 MHz):
//   line period, frame period (lines), hsync width/position, vsync width/position, active dots
//   per line, active lines per frame, sync polarity (active high).
// Twice: with the system held in reset during an ioctl download (the MiSTer loading screen) and
// with the download finished; sync must be present and identical in both.
`timescale 1ns/1ps
module m9_video_tb;
    localparam real FCLK = 100.227272e6;
    logic clk = 0;
    always #4.989 clk = ~clk;
    logic init = 1, reset = 1, dl = 0;
    logic ce_pix, hb, vb, hs, vs, rom_ready, iowait;
    logic [23:0] rgb;
    logic [26:1] sd_addr; logic [15:0] sd_din; logic [1:0] sd_be; logic sd_req, sd_rnw;

    nrc_core dut (
        .clk(clk), .init(init), .reset(reset), .sim_turbo(1'b0),
        .ioctl_download(dl), .ioctl_index(16'd0), .ioctl_wr(1'b0), .ioctl_addr('0), .ioctl_dout('0),
        .ioctl_wait(iowait),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout('0), .sd_ready(1'b0),
        .joy0('0), .joy1('0), .dbg_overlay(1'b0),
        .ce_pix(ce_pix), .rgb(rgb), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
        .snd_l(), .snd_r(), .rom_ready(rom_ready),
        .dbg_pc(), .dbg_frames(), .dbg_render_ms100(), .dbg_snap_drops(), .dbg_irqs(), .dbg_nmis());

    int errors = 0, checks = 0;
    task automatic check(bit c, string m);
        checks++; if (!c) begin errors++; $display("FAIL: %s", m); end
    endtask

    // measure one full frame starting at a vsync rising edge
    task automatic measure(string tag);
        longint t0, t_line0, n;
        int lines, hs_len, hs_start_dot, dots, act_dots_max, act_lines, vs_lines, vs_first;
        int hsw_min, hsw_max, lp_min, lp_max, lastrise;
        logic phs, pvs, line_active;
        // align to vsync rise
        @(posedge clk iff ce_pix && vs); @(posedge clk iff ce_pix && !vs); @(posedge clk iff ce_pix && vs);
        lines = 0; act_lines = 0; vs_lines = 0; hsw_min = 1 << 30; hsw_max = 0; lp_min = 1 << 30; lp_max = 0;
        act_dots_max = 0; lastrise = -1; n = 0; phs = hs; pvs = 1; hs_len = 0; dots = 0; line_active = 0;
        t0 = 0;
        forever begin
            @(posedge clk); n++;
            if (ce_pix) begin
                if (hs && !phs) begin            // hsync rise = line boundary
                    if (lastrise >= 0) begin
                        if (n - lastrise < lp_min) lp_min = n - lastrise;
                        if (n - lastrise > lp_max) lp_max = n - lastrise;
                    end
                    lastrise = n;
                    lines++;
                    if (dots > act_dots_max) act_dots_max = dots;
                    if (dots > 0) act_lines++;
                    if (vs) vs_lines++;
                    dots = 0;
                end
                if (hs) hs_len++;
                if (!hs && phs) begin
                    if (hs_len < hsw_min) hsw_min = hs_len;
                    if (hs_len > hsw_max) hsw_max = hs_len;
                    hs_len = 0;
                end
                if (!hb && !vb) dots++;
                if (vs && !pvs) break;           // next frame's vsync rise
                phs = hs; pvs = vs;
            end
        end
        $display("%s: frame %0d clk = %.4f ms = %.4f Hz; %0d lines; line %0d clk = %.3f us = %.3f kHz",
                 tag, n, n / FCLK * 1e3, FCLK / n, lines, lp_min, lp_min / FCLK * 1e6, FCLK / lp_min / 1e3);
        $display("%s: hsync %0d dots (%.2f us), vsync %0d lines, active %0d x %0d",
                 tag, hsw_min, hsw_min * 14 / FCLK * 1e6, vs_lines, act_dots_max, act_lines);
        check(lp_min == lp_max && lp_min == 455 * 14, $sformatf("%s line period %0d..%0d clk (expect 6370)", tag, lp_min, lp_max));
        check(lines == 262, $sformatf("%s lines/frame %0d", tag, lines));
        check(n == 262 * 455 * 14, $sformatf("%s frame %0d clk", tag, n));
        check(hsw_min == 34 && hsw_max == 34, $sformatf("%s hsync width %0d..%0d dots", tag, hsw_min, hsw_max));
        check(vs_lines == 3, $sformatf("%s vsync %0d lines", tag, vs_lines));
        check(act_dots_max == 320 && (tag != "RUN" || act_lines == 240), $sformatf("%s active %0d x %0d", tag, act_dots_max, act_lines));
    endtask

    initial begin
        repeat (10) @(posedge clk); init = 0;
        repeat (10) @(posedge clk); reset = 0;
        // 1. download in progress: system held in reset (rom_ready = 0), raster must run
        dl = 1; reset = 1;
        measure("DOWNLOAD");
        check(!rom_ready, "system held during download");
        // 2. download done, reset released (no ROM: CPU stays held by !rom_ready, raster same)
        dl = 0; reset = 0;
        measure("RUN");
        if (errors == 0) $display("PASS M9 VIDEO: %0d checks (15.734 kHz / 60.05 Hz, 320x240, sync during download)", checks);
        else $display("FAIL M9 VIDEO: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
