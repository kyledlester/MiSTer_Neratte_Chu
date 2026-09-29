// M3/M4 system bench: nrc_core running the real Neratte Chu program.
//   +EXTROM=<4 MiB extrom image> +LOG=<write log> +MAXW=<n writes> [+FRAMES=<n>] [+TURBO]
// The SDRAM channel is a behavioural model (random 8..14-cycle latency) preloaded with the extrom
// image; the loader streams only 0000-7FFF (fixed-ROM BRAM mirror) through the real ioctl path
// (EXTROM_END = 0x8000 and an empty char-RAM fill in this bench; the full fill is covered by M2).
// Every CPU memory / I/O write is logged in program order as "M aaaa dd" / "O pp dd", and "F n" at
// each vblank IRQ, for scripts/research/cmp_writes.py against MAME (scripts/mame/nrc_writes.lua).
// +TURBO runs the CPU time base 3x faster (tick every ~4 clk) - only valid before interrupts matter.
`timescale 1ns/1ps
module m3_cpu_tb;
    logic clk = 0;
    always #4.989 clk = ~clk;
    logic init = 1, reset = 1;

    string fext, flog;
    int maxw = 100000, maxframes = 0;

    logic        dl = 0, wr = 0, iowait;
    logic [26:0] ioa = 0;
    logic [15:0] iod = 0;
    logic [26:1] sd_addr; logic [15:0] sd_din; logic [1:0] sd_be; logic sd_req, sd_rnw;
    logic [63:0] sd_dout; logic sd_ready = 0;
    logic ce_pix, hb, vb, hs, vs, rom_ready;
    logic [23:0] rgb;
    logic [15:0] pc, frames;
    logic [15:0] rt, drops, irqs, nmis;

`ifdef TURBO
    localparam int CN = 1, CD = 4;
`else
    localparam int CN = 176, CD = 2205;
`endif
    nrc_core #(.EXTROM_END(25'h0008000), .CHA_BASE(25'h0800000), .CHA_END(25'h0800000),
               .CPU_NUM(CN), .CPU_DEN(CD)) dut (
        .clk(clk), .init(init), .reset(reset), .sim_turbo(1'b0),
        .ioctl_download(dl), .ioctl_index(16'd0), .ioctl_wr(wr), .ioctl_addr(ioa), .ioctl_dout(iod),
        .ioctl_wait(iowait),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready),
        .joy0(32'd0), .joy1(32'd0), .dbg_overlay(1'b0), .pause(1'b0),
        .ce_pix(ce_pix), .rgb(rgb), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .vb_next(),
        .snd_l(), .snd_r(), .rom_ready(rom_ready),
        .dbg_pc(pc), .dbg_frames(frames), .dbg_render_ms100(rt), .dbg_snap_drops(drops), .dbg_irqs(irqs), .dbg_nmis(nmis));

    // behavioural SDRAM (16-bit words, little-endian byte pairs)
    logic [7:0] mem [0:32'h0A00000 - 1];
    int seed = 3;
    always @(posedge clk) begin
        if (sd_req) begin
            logic [26:1] a; logic rnw; logic [15:0] d; logic [1:0] be;
            a = sd_addr; rnw = sd_rnw; d = sd_din; be = sd_be;
            repeat (8 + $urandom(seed) % 7) @(posedge clk);
            if (rnw) begin
                for (int k = 0; k < 8; k++) sd_dout[8*k +: 8] <= mem[{a, 1'b0} + k];
            end else begin
                if (be[0]) mem[{a, 1'b0}]     = d[7:0];
                if (be[1]) mem[{a, 1'b0} + 1] = d[15:8];
            end
            sd_ready <= 1;
            @(posedge clk); sd_ready <= 0;
        end
    end

    // write logger
    int fd, nw = 0, nf = 0;
    wire [15:0] A = dut.st0016.a_cpu;
    always @(posedge clk) begin
        if (!reset && rom_ready && dut.st0016.bs == 0 && !dut.st0016.wr_n && nw < maxw) begin
            if (!dut.st0016.iorq_n) $fwrite(fd, "O %02x %02x\n", A[7:0], dut.st0016.dout_cpu);
            else                    $fwrite(fd, "M %04x %02x\n", A, dut.st0016.dout_cpu);
            nw++;
        end
        if (!reset && rom_ready && dut.vblank_start) begin
            nf++;
            $fwrite(fd, "F %0d\n", nf);
            $display("M3 FRAME %0d: writes=%0d irqs=%0d nmis=%0d pc=%04x shown=%0d render=%0d0us drops=%0d iff1=%0d",
                     nf, nw, irqs, nmis, pc, frames, rt, drops, dut.st0016.iff1);
        end
    end

    initial begin
        int f, n;
        if (!$value$plusargs("EXTROM=%s", fext) || !$value$plusargs("LOG=%s", flog)) begin
            $display("FAIL M3 CPU: missing plusargs"); $finish;
        end
        void'($value$plusargs("MAXW=%d", maxw));
        void'($value$plusargs("FRAMES=%d", maxframes));
        for (int i = 0; i < 32'h0A00000; i++) mem[i] = 8'h00;
        f = $fopen(fext, "rb"); n = $fread(mem, f, 0, 32'h400000); $fclose(f);
        if (n != 32'h400000) begin $display("FAIL M3 CPU: extrom read %0d bytes", n); $finish; end
        fd = $fopen(flog, "w");
        repeat (10) @(posedge clk); init = 0;
        repeat (5) @(posedge clk); reset = 0;
        // stream the fixed-ROM part through the loader (ioctl path)
        dl <= 1;
        for (int k = 0; k < 'h8000; k += 2) begin
            @(posedge clk iff !iowait);
            wr <= 1; ioa <= k; iod <= {mem[k + 1], mem[k]};
            @(posedge clk); wr <= 0;
        end
        @(posedge clk iff !iowait); repeat (3) @(posedge clk); dl <= 0;
        @(posedge clk iff rom_ready);
        $display("M3: rom_ready at %0t, CPU released", $time);
        while (nw < maxw && (maxframes == 0 || nf < maxframes)) begin
            repeat (100000) @(posedge clk);
        end
        $fclose(fd);
        $display("PASS M3 CPU: %0d writes, %0d frames logged to %s (verdict: cmp_writes.py)", nw, nf, flog);
        $finish;
    end
endmodule
