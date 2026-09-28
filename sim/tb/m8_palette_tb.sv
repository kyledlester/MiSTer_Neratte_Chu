// M8 bench: palette RAM (CPU byte port, 4 x 512-byte banks = 1024 colours), snapshot into a
// per-buffer slot (CPU writes stalled during the copy), display pen -> RGB888 = MAME pal5bit,
// UNUSED_PEN (1024) -> colour 0.
`timescale 1ns/1ps
module m8_palette_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1;
    logic [10:0] a = 0; logic we = 0; logic [7:0] wd = 0, rd; logic stall;
    logic snap = 0, sbuf = 0, copying;
    logic dbuf = 0; logic [10:0] pen = 0; logic [23:0] rgb;
    nrc_palette dut (.clk(clk), .reset(reset), .cpu_addr(a), .cpu_we(we), .cpu_wdata(wd), .cpu_rdata(rd),
        .cpu_stall(stall), .snap(snap), .snap_buf(sbuf), .copying(copying),
        .disp_buf(dbuf), .disp_pen(pen), .disp_rgb(rgb));

    logic [15:0] ref0 [1024], ref1 [1024];
    int errors = 0, checks = 0;
    task automatic check(bit c, string m);
        checks++; if (!c) begin errors++; if (errors < 10) $display("FAIL: %s", m); end
    endtask
    function automatic logic [7:0] p5(logic [4:0] v); return {v, v[4:2]}; endfunction

    task automatic cpu_wr(input int addr, input logic [7:0] d);
        @(posedge clk); a <= addr; wd <= d; we <= 1;
        @(posedge clk iff !stall); we <= 0;
    endtask
    task automatic check_disp(input logic b, input logic [15:0] r[1024]);
        for (int c = 0; c <= 1024; c++) begin
            logic [15:0] v;
            v = (c == 1024) ? r[0] : r[c];
            @(posedge clk); dbuf <= b; pen <= c;
            repeat (3) @(posedge clk); #1;
            check(rgb == {p5(v[4:0]), p5(v[9:5]), p5(v[14:10])}, $sformatf("buf %0d pen %0d rgb %06h", b, c, rgb));
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); reset = 0;
        // fill all 4 banks, check CPU readback
        for (int i = 0; i < 2048; i++) begin
            logic [7:0] d; d = 8'(i * 7 + (i >> 5));
            cpu_wr(i, d);
            if (i & 1) ref0[i >> 1][15:8] = d; else ref0[i >> 1][7:0] = d;
        end
        for (int i = 0; i < 2048; i++) begin
            @(posedge clk); a <= i; @(posedge clk); @(posedge clk); #1;
            check(rd == (i[0] ? ref0[i >> 1][15:8] : ref0[i >> 1][7:0]), $sformatf("readback %0h", i));
        end
        // snapshot into buffer 0 while the CPU keeps writing: writes during the copy are stalled
        @(posedge clk); snap <= 1; sbuf <= 0; @(posedge clk); snap <= 0;
        fork
            for (int i = 0; i < 64; i++) begin
                cpu_wr(2 * i, 8'hEE);        // must wait for the copy; must not appear in buffer 0
                ref1[i] = {ref0[i][15:8], 8'hEE};
            end
        join
        check(!copying, "copy finished");
        for (int i = 64; i < 1024; i++) ref1[i] = ref0[i];
        check_disp(0, ref0);
        // second snapshot into buffer 1 sees the new values; buffer 0 unchanged
        @(posedge clk); snap <= 1; sbuf <= 1; @(posedge clk); snap <= 0;
        @(posedge clk iff !copying);
        check_disp(1, ref1);
        check_disp(0, ref0);
        if (errors == 0) $display("PASS M8 PALETTE: %0d checks", checks);
        else $display("FAIL M8 PALETTE: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
