// M15 bench: ST-0016 sound engine vs scripts/research/st0016_snd_ref.py (MAME master port).
//   +CHA=<charram.bin> +STIM=<stim> +N=<samples> +OUT=<out.txt>
// Stimulus lines "<sample> <reg hex> <data hex>" are applied (one register write per clock) before
// the sample's ce_snd; each sample's L/R is logged after the engine returns to idle. Character RAM
// is a behavioural SDRAM client with random latency.
`timescale 1ns/1ps
module m15_sound_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1, ce_snd = 0;
    logic [7:0] a = 0, wd = 0; logic we = 0;
    logic m_req, m_ack = 0; logic [24:0] m_addr; logic [63:0] m_rdata;
    logic signed [15:0] ol, orr;
    nrc_sound #(.CHA_BASE(25'h0800000)) dut (.clk(clk), .reset(reset), .ce_snd(ce_snd),
        .cpu_addr(a), .cpu_we(we), .cpu_wdata(wd), .cpu_rdata(),
        .m_req(m_req), .m_addr(m_addr), .m_ack(m_ack), .m_rdata(m_rdata), .out_l(ol), .out_r(orr));

    logic [7:0] cha [0:2097151];
    int seed = 5;
    always @(posedge clk) begin
        m_ack <= 0;
        if (m_req && !m_ack) begin
            repeat (6 + $urandom(seed) % 10) @(posedge clk);
            for (int k = 0; k < 8; k++) m_rdata[8*k +: 8] <= cha[(m_addr - 25'h0800000) + k];
            m_ack <= 1;
        end
    end

    initial begin
        string fcha, fstim, fout;
        int fd, fs, fo, n, nsamp, ss, sr, sd, have;
        if (!$value$plusargs("CHA=%s", fcha) || !$value$plusargs("STIM=%s", fstim) ||
            !$value$plusargs("N=%d", nsamp) || !$value$plusargs("OUT=%s", fout)) begin
            $display("FAIL M15 SOUND: missing plusargs"); $finish;
        end
        fd = $fopen(fcha, "rb"); n = $fread(cha, fd); $fclose(fd);
        fs = $fopen(fstim, "r"); fo = $fopen(fout, "w");
        repeat (4) @(posedge clk); reset = 0;
        have = ($fscanf(fs, "%d %h %h", ss, sr, sd) == 3);
        for (int s = 0; s < nsamp; s++) begin
            while (have && ss <= s) begin
                @(posedge clk); a <= sr[7:0]; wd <= sd[7:0]; we <= 1;
                @(posedge clk); we <= 0;
                have = ($fscanf(fs, "%d %h %h", ss, sr, sd) == 3);
            end
            @(posedge clk); ce_snd <= 1; @(posedge clk); ce_snd <= 0;
            @(posedge clk iff dut.es == 0);
            @(posedge clk);
            $fwrite(fo, "%0d %0d\n", ol, orr);
        end
        $fclose(fo);
        $display("PASS M15 SOUND: %0d samples written to %s (verdict: st0016_snd_ref.py cmp)", nsamp, fout);
        $finish;
    end
endmodule
