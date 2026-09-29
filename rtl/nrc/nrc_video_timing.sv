// Neratte Chu (Seta ST-0016) MiSTer core -- raster timing.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// 455 dots x 262 lines at ce_pix = clk_sys/14 = 7.159091 MHz: 15.734 kHz / 60.05 Hz.
// Totals are the game's own programming of the ST-0016 CRT registers ($66/$67 = $1C6 -> H
// total 455, $6E/$6F = $105 -> V total 262; ROM table at $8020) [GAME-PROGRAMMED].
// Vertical: active lines 16..255 ($6A = $10 visible start, $6C = $100 visible end),
// vsync from line 1 ($68 = 1) [GAME-PROGRAMMED; register meanings from MAME comments].
// Horizontal: 320 active dots (MAME visible width for nratechu); the placement of sync
// inside the 135-dot blank is [MISTER-COMPATIBLE], centred like a standard NTSC active
// window (see docs/ST0016_VIDEO.md "Timing"). The H register semantics are not proven.
//
// Coordinates: x = 0..319, y = 0..239 inside the active window. ST-0016 bitmap x = x + 8
// (MAME nratechu visible area 8..327), bitmap y = y.
module nrc_video_timing #(
    parameter int H_TOTAL   = 455,
    parameter int H_ACTIVE  = 320,
    parameter int HS_START  = 369,   // front porch 49 dots: CRT Adjust H-Position -48 keeps HSync in the blank
    parameter int HS_END    = 403,
    parameter int V_TOTAL   = 262,
    parameter int V_ACT0    = 16,
    parameter int V_ACT1    = 256,   // first line after the active window (vblank start)
    parameter int VS_START  = 1,
    parameter int VS_END    = 4
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        ce_pix,
    output logic  [8:0] hcnt,        // 0..454
    output logic  [8:0] vcnt,        // 0..261
    output logic  [8:0] x,           // active x (valid when !hblank)
    output logic  [7:0] y,           // active y (valid when !vblank)
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,
    output logic        vsync,
    output logic        vblank_start,   // one clk_sys pulse when line V_ACT1 begins (at its HSync)
    output logic        frame_start     // one clk_sys pulse when line 0 begins (at its HSync)
);
    // The line number (vcnt) advances at the HSync leading edge (hcnt = HS_START), not at the start of
    // the active area: vblank / vsync change on the HSync edge (the conventional CRT arrangement) and
    // every HSync-to-HSync window holds exactly one line's active dots, which is what line-buffered
    // presentation stages (CRT Adjust, sim/tb/m17_crt_tb.sv) require. Totals and widths unchanged.
    always_ff @(posedge clk) begin
        vblank_start <= 1'b0;
        frame_start  <= 1'b0;
        if (rst) begin
            hcnt <= '0; vcnt <= '0;
            hblank <= 1'b1; vblank <= 1'b1; hsync <= 1'b0; vsync <= 1'b0;
            x <= '0; y <= '0;
        end else if (ce_pix) begin
            logic [8:0] h_n, v_n;
            h_n = (hcnt == H_TOTAL - 1) ? 9'd0 : hcnt + 9'd1;
            v_n = vcnt;
            if (h_n == HS_START) v_n = (vcnt == V_TOTAL - 1) ? 9'd0 : vcnt + 9'd1;
            hcnt   <= h_n;
            vcnt   <= v_n;
            hblank <= (h_n >= H_ACTIVE);
            vblank <= (v_n < V_ACT0) || (v_n >= V_ACT1);
            hsync  <= (h_n >= HS_START) && (h_n < HS_END);
            if (h_n == HS_START) vsync <= (v_n >= VS_START) && (v_n < VS_END);
            x      <= h_n;
            y      <= 8'(v_n - V_ACT0);
            if (h_n == HS_START && v_n == V_ACT1) vblank_start <= 1'b1;
            if (h_n == HS_START && v_n == 0)      frame_start  <= 1'b1;
        end
    end
endmodule
