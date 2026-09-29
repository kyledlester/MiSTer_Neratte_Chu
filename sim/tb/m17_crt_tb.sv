// M17/M18 bench: CRT Adjust (nrc_crt_adjust + vendored crt_adjust.sv) on the Neratte Chu raster.
// Source: nrc_video_timing with a pattern whose colour encodes its own position: R = y, G = x[7:0],
// B = 0x80 | x[8] (never black). For every setting in the sweep, after one settling frame, one full
// frame of the adjusted output is checked:
//   - HSync period constant 6370 clk (455 dots) and pulse width 34 dots; 262 lines per frame;
//     VSync width 3 lines (the line/frame frequency the CRT locks to never changes);
//   - no picture pixel while HSync is active;
//   - exactly 240 picture lines, each carrying one source line, all source lines 0..239 present;
//   - within a line the source x never decreases and includes x = 0 and x = 319 (whole picture);
//   - Off: output == native stream (bypass).
`timescale 1ns/1ps
module m17_crt_tb;
    logic clk = 0;
    always #4.989 clk = ~clk;
    logic rst = 1;
    logic ce_pix, tick8, ce_snd, ce_cpu;
    logic [8:0] hcnt, vcnt, x; logic [7:0] y;
    logic hb, vb, hs, vs, vbs, fs;
    nrc_clocks clocks(.clk(clk), .rst(rst), .rst_video(rst), .cpu_stall(1'b0), .turbo(1'b0), .pause(1'b0),
        .ce_pix(ce_pix), .tick8(tick8), .ce_snd(ce_snd), .ce_cpu(ce_cpu), .credits(), .lost_credits());
    nrc_video_timing timing(.clk(clk), .rst(rst), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt), .x(x), .y(y),
        .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .vblank_start(vbs), .frame_start(fs));

    // registered like nrc_core's output stage
    logic [23:0] rgb; logic ohb, ovb, ohs, ovs, ovn;
    always_ff @(posedge clk) if (ce_pix) begin
        ohb <= hb; ovb <= vb; ohs <= hs; ovs <= vs;
        ovn <= !((vcnt + 9'd1 >= 9'd16) && (vcnt + 9'd1 < 9'd256));
        rgb <= (hb || vb) ? 24'h0 : {y, x[7:0], 7'b1000000, x[8]};
    end

    logic on = 0; logic [4:0] hsz = 0; logic [3:0] hp = 0, vsh = 0;
    logic ce_o, a_hb, a_vb, a_hs, a_vs, act; logic [23:0] a_rgb;
    nrc_crt_adjust dut(.clk_sys(clk), .ce_pix(ce_pix), .frame_event(fs),
        .osd_on(on), .osd_hsize(hsz), .osd_hpos(hp), .osd_vshift(vsh), .sd_off(1'b1),
        .rgb_in(rgb), .hblank_in(ohb), .vblank_in(ovb), .hsync_in(ohs), .vsync_in(ovs), .vb_next_in(ovn),
        .ce_out(ce_o), .rgb_out(a_rgb), .hblank_out(a_hb), .vblank_out(a_vb),
        .hsync_out(a_hs), .vsync_out(a_vs), .active(act));

    int errors = 0, checks = 0, settings = 0;
    task automatic check(bit c, string m);
        checks++; if (!c) begin errors++; if (errors < 25) $display("FAIL: %s", m); end
    endtask

    task automatic measure(string tag);
        int lines, pic_lines, hs_len, hsw_min, hsw_max, vs_lines, bad_sync;
        longint n, lastrise, lp_min, lp_max;
        int cur_y, xmin, xmax, lastx, nondec, line_has;
        bit seen [240];
        int err0;
        logic phs, pvs;
        err0 = errors;
        // settle: two frame starts, then align on an output VSync rise
        repeat (2) @(posedge clk iff fs);
        @(posedge clk iff !a_vs); @(posedge clk iff a_vs);
        foreach (seen[i]) seen[i] = 0;
        lines = 0; pic_lines = 0; hs_len = 0; hsw_min = 1 << 30; hsw_max = 0; vs_lines = 0; bad_sync = 0;
        n = 0; lastrise = -1; lp_min = 1 << 30; lp_max = 0; phs = a_hs; pvs = 1;
        cur_y = -1; line_has = 0; nondec = 1; lastx = -1; xmin = 999; xmax = -1;
        forever begin
            @(posedge clk); n++;
            if (a_hs && !phs) begin
                if (lastrise >= 0) begin
                    if (n - lastrise < lp_min) lp_min = n - lastrise;
                    if (n - lastrise > lp_max) lp_max = n - lastrise;
                end
                lastrise = n; lines++;
                if (a_vs) vs_lines++;
                if (line_has) begin
                    pic_lines++;
                    check(xmin == 0 && xmax == 319 && nondec,
                          $sformatf("%s src line %0d: x %0d..%0d monotonic %0d", tag, cur_y, xmin, xmax, nondec));
                    if (cur_y >= 0 && cur_y < 240) begin
                        check(!seen[cur_y], $sformatf("%s src line %0d shown twice", tag, cur_y));
                        seen[cur_y] = 1;
                    end
                end
                cur_y = -1; line_has = 0; nondec = 1; lastx = -1; xmin = 999; xmax = -1;
            end
            if (ce_o) begin
                if (a_hs) hs_len++;
                else if (hs_len) begin
                    if (hs_len < hsw_min) hsw_min = hs_len;
                    if (hs_len > hsw_max) hsw_max = hs_len;
                    hs_len = 0;
                end
                if (!a_hb && !a_vb && a_rgb[7]) begin
                    int px;
                    px = {a_rgb[0], a_rgb[15:8]};
                    if (a_hs) bad_sync++;
                    if (cur_y < 0) cur_y = a_rgb[23:16];
                    else check(a_rgb[23:16] == cur_y, $sformatf("%s mixed lines %0d/%0d", tag, cur_y, a_rgb[23:16]));
                    if (px < lastx) nondec = 0;
                    lastx = px; line_has = 1;
                    if (px < xmin) xmin = px;
                    if (px > xmax) xmax = px;
                end
            end
            if (a_vs && !pvs) break;
            phs = a_hs; pvs = a_vs;
        end
        check(lp_min == 6370 && lp_max == 6370, $sformatf("%s line period %0d..%0d", tag, lp_min, lp_max));
        check(lines == 262, $sformatf("%s lines %0d", tag, lines));
        check(vs_lines == 3, $sformatf("%s vsync lines %0d", tag, vs_lines));
        check(bad_sync == 0, $sformatf("%s %0d picture pixels during HSync", tag, bad_sync));
        check(pic_lines == 240, $sformatf("%s picture lines %0d", tag, pic_lines));
        for (int i = 0; i < 240; i++) if (!seen[i]) begin check(0, $sformatf("%s source line %0d missing", tag, i)); break; end
        settings++;
        $display("SETTING %-24s %s (errors so far %0d)", tag, (errors == err0) ? "ok" : "FAIL", errors);
    endtask

    function automatic logic [4:0] hsize_idx(int h); return (h >= 0) ? 5'(h) : 5'(23 + h); endfunction

    initial begin
        repeat (10) @(posedge clk); rst = 0;
        on = 0; measure("OFF");
        on = 1;
        // every H-Size at both H-Position extremes, then a mid grid, then V-Shift
        for (int h = -12; h <= 10; h++) begin
            hsz = hsize_idx(h); hp = 4'(-8); vsh = 0; measure($sformatf("H-Size %0d H-Pos -8", h));
            hsz = hsize_idx(h); hp = 4'(7);  vsh = 0; measure($sformatf("H-Size %0d H-Pos 7", h));
        end
        for (int hi = 0; hi < 3; hi++) begin
            int h; h = (hi == 0) ? -6 : (hi == 1) ? 0 : 5;
            for (int pi = 0; pi < 3; pi++) begin
                int p; p = (pi == 0) ? -4 : (pi == 1) ? 0 : 4;
                hsz = hsize_idx(h); hp = 4'(p); vsh = 0;
                measure($sformatf("H-Size %0d H-Pos %0d", h, p));
            end
        end
        for (int vi = 0; vi < 3; vi++) begin
            int v; v = (vi == 0) ? -8 : (vi == 1) ? -1 : 7;
            hsz = 0; hp = 0; vsh = 4'(v);
            measure($sformatf("V-Shift %0d", v));
        end
        if (errors == 0) $display("PASS M17 CRT ADJUST: %0d settings, %0d checks", settings, checks);
        else $display("FAIL M17 CRT ADJUST: %0d of %0d checks failed over %0d settings", errors, checks, settings);
        $finish;
    end
endmodule
