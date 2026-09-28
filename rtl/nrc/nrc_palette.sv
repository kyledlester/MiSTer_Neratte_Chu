// Neratte Chu (Seta ST-0016) MiSTer core -- palette RAM + per-frame snapshots.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Live palette: 2 KiB = 1024 colours x 16 bit little-endian (MAME m_paletteram), CPU window EA00-EBFF
// through the E5 bank register (512 bytes per bank).
// MAME converts pens to colours at the moment it renders the frame (vblank IRQ). To keep pens and
// colours consistent the renderer's snapshot instant also copies the live palette into the
// snapshot slot that travels with the framebuffer being drawn (snap_buf). The copy takes 1024 clocks;
// CPU palette writes during the copy are stalled (cpu_stall) so the copy is exact.
// Display reads (buffer, pen) -> RGB888 with MAME pal5bit expansion; pen 1024 (UNUSED_PEN) shows colour 0.
module nrc_palette (
    input  logic        clk,
    input  logic        reset,
    // CPU port: byte address 0..0x7FF (bank*0x200 + offset); read data valid the next cycle
    input  logic [10:0] cpu_addr,
    input  logic        cpu_we,
    input  logic  [7:0] cpu_wdata,
    output logic  [7:0] cpu_rdata,
    output logic        cpu_stall,
    // snapshot
    input  logic        snap,
    input  logic        snap_buf,
    output logic        copying,
    // display
    input  logic        disp_buf,
    input  logic [10:0] disp_pen,
    output logic [23:0] disp_rgb      // 2 cycles after disp_pen
);
    logic [7:0] lo [1024];
    logic [7:0] hi [1024];
    logic [14:0] snapram [2048];

    logic [9:0] cidx;
    logic       cbuf;
    logic       c_wr;
    logic [9:0] c_widx;
    logic [14:0] c_data;

    assign cpu_stall = cpu_we && copying;

    // live RAM: port A = CPU, port B = copy engine
    logic [7:0] lo_b, hi_b;
    always_ff @(posedge clk) begin
        if (cpu_we && !copying) begin
            if (cpu_addr[0]) hi[cpu_addr[10:1]] <= cpu_wdata;
            else             lo[cpu_addr[10:1]] <= cpu_wdata;
        end
        cpu_rdata <= cpu_addr[0] ? hi[cpu_addr[10:1]] : lo[cpu_addr[10:1]];
    end
    always_ff @(posedge clk) begin
        lo_b <= lo[cidx];
        hi_b <= hi[cidx];
    end

    // copy engine: read index i, write snapram one cycle later
    always_ff @(posedge clk) begin
        c_wr <= 1'b0;
        if (reset) begin
            copying <= 1'b0; cidx <= '0;
        end else if (snap && !copying) begin
            copying <= 1'b1; cidx <= '0; cbuf <= snap_buf;
        end else if (copying) begin
            c_wr   <= 1'b1;
            c_widx <= cidx;
            cidx   <= cidx + 10'd1;
            if (cidx == 10'd1023) copying <= 1'b0;
        end
    end
    // c_wr/c_widx arrive in the cycle after cidx was presented, together with lo_b/hi_b
    always_ff @(posedge clk) begin
        if (c_wr) snapram[{cbuf, c_widx}] <= {hi_b[6:0], lo_b};
    end

    // display port
    logic [14:0] d_q;
    always_ff @(posedge clk) begin
        d_q <= snapram[{disp_buf, disp_pen[10] ? 10'd0 : disp_pen[9:0]}];
        disp_rgb <= {d_q[4:0], d_q[4:2], d_q[9:5], d_q[9:7], d_q[14:10], d_q[14:12]};
    end
endmodule
