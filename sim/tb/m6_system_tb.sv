// M6/M16 system bench: nrc_core running Neratte Chu from reset into the interrupt-driven phase.
//   +EXTROM=<4 MiB image> +FRAMES=<real-time frames after the first EI> [+SHOT=<frame>:<file>]
// The CPU runs in simulation turbo (nrc_core sim_turbo) until the game first enables interrupts
// (T80 IFF1 = 1, MAME frame ~150), then at the exact 8 MHz time base. Per frame it prints IRQ/NMI
// counts, NMIs skipped by the IFF1 gate, render time and snapshot drops. +SHOT dumps the displayed
// framebuffer (320x240 pens, 16-bit LE) after the given real-time frame for comparison with MAME.
`timescale 1ns/1ps
module m6_system_tb;
    logic clk = 0;
    always #4.989 clk = ~clk;
    logic init = 1, reset = 1, turbo = 1;

    logic        dl = 0, wr = 0, iowait;
    logic [26:0] ioa = 0;
    logic [15:0] iod = 0;
    logic [26:1] sd_addr; logic [15:0] sd_din; logic [1:0] sd_be; logic sd_req, sd_rnw;
    logic [63:0] sd_dout; logic sd_ready = 0;
    logic ce_pix, hb, vb, hs, vs, rom_ready;
    logic [23:0] rgb;
    logic [15:0] pc, frames, rt, drops, irqs, nmis;

    nrc_core #(.EXTROM_END(25'h0008000), .CHA_BASE(25'h0800000), .CHA_END(25'h0800000)) dut (
        .clk(clk), .init(init), .reset(reset), .sim_turbo(turbo),
        .ioctl_download(dl), .ioctl_index(16'd0), .ioctl_wr(wr), .ioctl_addr(ioa), .ioctl_dout(iod),
        .ioctl_wait(iowait),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready),
        .joy0(32'd0), .joy1(32'd0), .dbg_overlay(1'b0), .pause(1'b0),
        .ce_pix(ce_pix), .rgb(rgb), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .vb_next(),
        .snd_l(), .snd_r(), .rom_ready(rom_ready),
        .dbg_pc(pc), .dbg_frames(frames), .dbg_render_ms100(rt), .dbg_snap_drops(drops),
        .dbg_irqs(irqs), .dbg_nmis(nmis));

    // behavioural SDRAM
    logic [7:0] mem [0:32'h0A00000 - 1];
    int seed = 3;
    always @(posedge clk) begin
        if (sd_req) begin
            logic [26:1] a; logic rnw; logic [15:0] d; logic [1:0] be;
            a = sd_addr; rnw = sd_rnw; d = sd_din; be = sd_be;
            repeat (8 + $urandom(seed) % 7) @(posedge clk);
            if (rnw) for (int k = 0; k < 8; k++) sd_dout[8*k +: 8] <= mem[{a, 1'b0} + k];
            else begin
                if (be[0]) mem[{a, 1'b0}]     = d[7:0];
                if (be[1]) mem[{a, 1'b0} + 1] = d[15:8];
            end
            sd_ready <= 1;
            @(posedge clk); sd_ready <= 0;
        end
    end

    int rtframes = 0, nf = 0, shot_at = -1, maxf = 20;
    string fext, shot_file;
    logic [15:0] last_irqs = 0, last_nmis = 0, last_skip = 0;
    always @(posedge clk) begin
        if (turbo && rom_ready && dut.st0016.iff1) begin
            turbo <= 0;
            $display("M6: first EI at t=%0t (frame %0d, pc=%04x) - real-time from here", $time, nf, pc);
        end
        if (rom_ready && dut.vblank_start) begin
            nf++;
            if (!turbo) begin
                rtframes++;
                $display("M6 FRAME %0d (rt %0d): irq+%0d nmi+%0d skip+%0d pc=%04x shown=%0d render=%0d0us drops=%0d",
                    nf, rtframes, irqs - last_irqs, nmis - last_nmis, dut.st0016.irq.nmi_skipped - last_skip,
                    pc, frames, rt, drops);
            end
            last_irqs <= irqs; last_nmis <= nmis; last_skip <= dut.st0016.irq.nmi_skipped;
        end
    end

    initial begin
        int f, n;
        string s;
        if (!$value$plusargs("EXTROM=%s", fext)) begin $display("FAIL M6 SYSTEM: missing +EXTROM"); $finish; end
        void'($value$plusargs("FRAMES=%d", maxf));
        if ($value$plusargs("SHOT=%s", s)) begin
            int p; p = 0;
            while (p < s.len() && s[p] != ":") p++;
            shot_at = s.substr(0, p - 1).atoi();
            shot_file = s.substr(p + 1, s.len() - 1);
        end
        for (int i = 0; i < 32'h0A00000; i++) mem[i] = 8'h00;
        f = $fopen(fext, "rb"); n = $fread(mem, f, 0, 32'h400000); $fclose(f);
        repeat (10) @(posedge clk); init = 0;
        repeat (5) @(posedge clk); reset = 0;
        dl <= 1;
        for (int k = 0; k < 'h8000; k += 2) begin
            @(posedge clk iff !iowait);
            wr <= 1; ioa <= k; iod <= {mem[k + 1], mem[k]};
            @(posedge clk); wr <= 0;
        end
        @(posedge clk iff !iowait); repeat (3) @(posedge clk); dl <= 0;
        @(posedge clk iff rom_ready);
        while (rtframes < maxf) begin
            @(posedge clk);
            if (shot_at >= 0 && rtframes == shot_at && dut.frame_start) begin
                // dump the displayed buffer (front) through the display port
                int fd;
                fd = $fopen(shot_file, "wb");
                for (int i = 0; i < 76800; i++) begin
                    logic [10:0] v;
                    v = dut.front ? dut.fb.fb1[i] : dut.fb.fb0[i];
                    $fwrite(fd, "%c%c", v[7:0], {5'd0, v[10:8]});
                end
                $fclose(fd);
                $display("M6: shot of displayed frame after rt frame %0d -> %s", rtframes, shot_file);
                shot_at = -1;
            end
        end
        if (nmis > 0 && drops == 0)
            $display("PASS M6 SYSTEM: %0d real-time frames after EI, irqs=%0d nmis=%0d drops=%0d", rtframes, irqs, nmis, drops);
        else
            $display("FAIL M6 SYSTEM: irqs=%0d nmis=%0d drops=%0d", irqs, nmis, drops);
        $finish;
    end
endmodule
