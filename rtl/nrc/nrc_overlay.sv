// Neratte Chu (Seta ST-0016) MiSTer core -- diagnostic overlay.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// OSD "Debug overlay: On" draws one line of 8x8 characters over the top of the picture:
//   R<rom> P<pc> F<frames> I<irqs> N<nmis> T<render time/10us> D<snapshot drops>
// (hex). Values are sampled once per frame. Purely diagnostic; no effect on emulation.
module nrc_overlay (
    input  logic        clk,
    input  logic        ce_pix,
    input  logic        enable,
    input  logic        frame_start,
    input  logic  [8:0] x,              // active x 0..319
    input  logic  [7:0] y,              // active y 0..239
    input  logic [23:0] rgb_in,
    output logic [23:0] rgb_out,
    input  logic        rom_ready,
    input  logic [15:0] pc,
    input  logic [15:0] frames,
    input  logic [15:0] irqs,
    input  logic [15:0] nmis,
    input  logic [15:0] render_t,
    input  logic [15:0] drops
);
    // 40 character cells; codes 0-15 hex digits, 16+ letters, 31 blank
    localparam int NCH = 40;
    logic [4:0] text [NCH];
    logic [15:0] s_pc, s_fr, s_ir, s_nm, s_rt, s_dr;
    logic        s_rom;
    always_ff @(posedge clk) if (frame_start) begin
        s_pc <= pc; s_fr <= frames; s_ir <= irqs; s_nm <= nmis; s_rt <= render_t; s_dr <= drops;
        s_rom <= rom_ready;
    end

    localparam logic [4:0] L_R = 5'd16, L_P = 5'd17, L_F = 5'd18, L_I = 5'd19, L_N = 5'd20,
                           L_T = 5'd21, L_D = 5'd22, BL = 5'd31;
    always_comb begin
        for (int i = 0; i < NCH; i++) text[i] = BL;
        text[0] = L_R; text[1] = s_rom ? 5'd1 : 5'd0;
        text[3] = L_P; for (int i = 0; i < 4; i++) text[4 + i] = {1'b0, s_pc[15 - 4*i -: 4]};
        text[9] = L_F; for (int i = 0; i < 4; i++) text[10 + i] = {1'b0, s_fr[15 - 4*i -: 4]};
        text[15] = L_I; for (int i = 0; i < 4; i++) text[16 + i] = {1'b0, s_ir[15 - 4*i -: 4]};
        text[21] = L_N; for (int i = 0; i < 4; i++) text[22 + i] = {1'b0, s_nm[15 - 4*i -: 4]};
        text[27] = L_T; for (int i = 0; i < 4; i++) text[28 + i] = {1'b0, s_rt[15 - 4*i -: 4]};
        text[33] = L_D; for (int i = 0; i < 4; i++) text[34 + i] = {1'b0, s_dr[15 - 4*i -: 4]};
    end

    // 5x7 font in an 8x8 cix (bit 4 = leftmost column)
    function automatic logic [4:0] glyph(input logic [4:0] c, input logic [2:0] r);
        logic [34:0] g;
        case (c)
            5'd0:  g = 35'b01110_10001_10011_10101_11001_10001_01110;
            5'd1:  g = 35'b00100_01100_00100_00100_00100_00100_01110;
            5'd2:  g = 35'b01110_10001_00001_00010_00100_01000_11111;
            5'd3:  g = 35'b11110_00001_00001_01110_00001_00001_11110;
            5'd4:  g = 35'b00010_00110_01010_10010_11111_00010_00010;
            5'd5:  g = 35'b11111_10000_11110_00001_00001_10001_01110;
            5'd6:  g = 35'b00110_01000_10000_11110_10001_10001_01110;
            5'd7:  g = 35'b11111_00001_00010_00100_01000_01000_01000;
            5'd8:  g = 35'b01110_10001_10001_01110_10001_10001_01110;
            5'd9:  g = 35'b01110_10001_10001_01111_00001_00010_01100;
            5'd10: g = 35'b01110_10001_10001_11111_10001_10001_10001;
            5'd11: g = 35'b11110_10001_10001_11110_10001_10001_11110;
            5'd12: g = 35'b01110_10001_10000_10000_10000_10001_01110;
            5'd13: g = 35'b11110_10001_10001_10001_10001_10001_11110;
            5'd14: g = 35'b11111_10000_10000_11110_10000_10000_11111;
            5'd15: g = 35'b11111_10000_10000_11110_10000_10000_10000;
            5'd16: g = 35'b11110_10001_10001_11110_10100_10010_10001; // R
            5'd17: g = 35'b11110_10001_10001_11110_10000_10000_10000; // P
            5'd18: g = 35'b11111_10000_10000_11110_10000_10000_10000; // F
            5'd19: g = 35'b01110_00100_00100_00100_00100_00100_01110; // I
            5'd20: g = 35'b10001_11001_10101_10011_10001_10001_10001; // N
            5'd21: g = 35'b11111_00100_00100_00100_00100_00100_00100; // T
            5'd22: g = 35'b11110_10001_10001_10001_10001_10001_11110; // D
            default: g = '0;
        endcase
        return (r == 3'd7) ? 5'd0 : g[34 - 5*r -: 5];
    endfunction

    // Pipelined (x/y are stable for 14 clk_sys per dot; rgb_out is sampled at the next ce_pix):
    // stage 1 cell/row indices, stage 2 character code, stage 3 glyph row, stage 4 pixel.
    logic        in_band1, xin1, in_band2, xin2, in_band3, xin3, in_band4, on4;
    logic  [5:0] cix1;
    logic  [2:0] cx1, cy1, cx2, cy2, cx3;
    logic  [4:0] ch2, row3;
    always_ff @(posedge clk) begin
        in_band1 <= (y >= 8'd2) && (y < 8'd10);
        xin1     <= (x >= 9'd4) && (x < 9'd4 + 9'(8 * NCH));
        cix1     <= 6'((x - 9'd4) >> 3);
        cx1      <= 3'(x - 9'd4);
        cy1      <= 3'(y - 8'd2);
        in_band2 <= in_band1; xin2 <= xin1; cx2 <= cx1; cy2 <= cy1;
        ch2      <= xin1 ? text[cix1] : BL;
        in_band3 <= in_band2; xin3 <= xin2; cx3 <= cx2;
        row3     <= glyph(ch2, cy2);
        in_band4 <= in_band3;
        on4      <= in_band3 && xin3 && cx3 < 3'd5 && row3[3'd4 - cx3];
    end
    always_comb rgb_out = !enable ? rgb_in : on4 ? 24'hFFFF40 :
                          in_band4 ? {1'b0, rgb_in[23:17], 1'b0, rgb_in[15:9], 1'b0, rgb_in[7:1]} : rgb_in;
endmodule
