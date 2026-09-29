// M0 bench: clock enables and raster timing.
// Checks over two full frames of clk_sys:
//   - ce_pix every 14 clk_sys
//   - 455 x 262 raster, 320 x 240 active, vblank_start at line 256, one frame_start per frame
//   - tick8 rate = 176/2205 of clk_sys (exact over a frame, +/- 1)
//   - ce_cpu: with cpu_stall pulsing, total ce_cpu == total tick8 minus final credits, gap >= 3
`timescale 1ns/1ps
module m0_timing_tb;
    logic clk = 0, rst = 1;
    always #4.989 clk = ~clk;   // ~100.227 MHz

    logic ce_pix, tick8, ce_snd, ce_cpu, stall;
    logic [7:0] credits; logic [15:0] lost;
    logic [8:0] hcnt, vcnt, x; logic [7:0] y;
    logic hblank, vblank, hsync, vsync, vbs, fs;

    nrc_clocks clocks(.clk(clk), .rst(rst), .rst_video(rst), .cpu_stall(stall), .turbo(1'b0), .ce_pix(ce_pix), .tick8(tick8),
        .ce_snd(ce_snd), .ce_cpu(ce_cpu), .credits(credits), .lost_credits(lost));
    nrc_video_timing timing(.clk(clk), .rst(rst), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
        .x(x), .y(y), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
        .vblank_start(vbs), .frame_start(fs));

    int errors = 0, checks = 0;
    task automatic check(bit c, string m);
        checks++;
        if (!c) begin errors++; if (errors < 10) $display("FAIL: %s (t=%0t)", m, $time); end
    endtask

    longint clks = 0, pixs = 0, ticks = 0, cpus = 0, snds = 0, active = 0, frames = 0, vbss = 0;
    int last_pix = -1, last_cpu = -100, mingap = 1000;
    int lfsr = 1;
    always @(posedge clk) begin
        lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end
    assign stall = lfsr[3] & lfsr[7];   // random 25 % stall

    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        @(posedge clk iff fs);   // align to a frame start
        clks = 0; pixs = 0; ticks = 0; cpus = 0; snds = 0; active = 0; frames = 0; vbss = 0;
        repeat (2) begin
            do begin
                @(posedge clk);
                clks++;
                if (ce_pix) begin
                    if (last_pix >= 0) check(clks - last_pix == 14, "ce_pix period 14");
                    last_pix = clks; pixs++;
                    if (!hblank && !vblank) active++;
                end
                if (tick8) ticks++;
                if (ce_snd) snds++;
                if (ce_cpu) begin
                    if (clks - last_cpu < mingap) mingap = clks - last_cpu;
                    last_cpu = clks; cpus++;
                end
                if (vbs) begin vbss++; check(vcnt == 256 && hcnt == 0, "vblank_start at (0,256)"); end
            end while (!fs);
            frames++;
        end
        check(pixs == 2 * 455 * 262, $sformatf("dots per 2 frames %0d", pixs));
        check(active == 2 * 320 * 240, $sformatf("active dots %0d", active));
        check(vbss == 2, "one vblank_start per frame");
        check(ticks >= (clks * 176) / 2205 - 1 && ticks <= (clks * 176) / 2205 + 1,
              $sformatf("tick8 count %0d for %0d clks", ticks, clks));
        check(snds >= ticks / 128 - 1 && snds <= ticks / 128 + 1, "ce_snd = tick8/128");
        check(mingap >= 3, $sformatf("ce_cpu min gap %0d", mingap));
        check(cpus + credits >= ticks - 1 && cpus + credits <= ticks + 1, $sformatf("ce_cpu %0d + credits %0d vs ticks %0d", cpus, credits, ticks));
        check(lost == 0, "no lost credits");
        $display("M0: clks=%0d dots=%0d ticks8=%0d ce_cpu=%0d credits=%0d snd=%0d (%.4f MHz cpu @100.227)",
                 clks, pixs, ticks, cpus, credits, snds, cpus * 100.227272 / clks);
        if (errors == 0) $display("PASS M0 TIMING: %0d checks", checks);
        else $display("FAIL M0 TIMING: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
