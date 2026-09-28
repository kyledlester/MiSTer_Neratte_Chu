// Neratte Chu (Seta ST-0016) MiSTer core -- sprite renderer (frame renderer into a framebuffer).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Hardware port of MAME 0.289 st0016_cpu_device::draw_sprites() for game_flag 1 (nratechu):
// spr_dx = 0, spr_dy = 8, clip x 8..327 / y 0..239, bitmap pre-filled with UNUSED_PEN (1024).
// Golden model: scripts/research/st0016_ref.py (pixel-identical to MAME snapshots).
// Tilemaps are not drawn (Neratte Chu never enables one; docs/KNOWN_ISSUES.md U-4).
//
// Sequence per frame (started by `go`, from the sprite-RAM snapshot):
//   1. clear the target buffer to UNUSED_PEN (76,800 writes);
//   2. walk the main list (8-byte entries from 0, stop at byte3 bit7) and each sublist;
//   3. per 8x8 tile: compute which of its 8 destination columns / rows fall inside the clip
//      (exactly MAME's u16 arithmetic, x wrap "-512 if > 327"); a tile with no visible pixel is
//      skipped without fetching; otherwise fetch its 32 bytes (4 x 8-byte SDRAM reads) and draw the
//      64 pixels with a pipelined read-modify-write of the framebuffer (1 pixel / clock).
// Pixel rules: normal  : if (pen || dest == UNUSED) dest = colour*16 + pen
//              merge   : dest = (dest | pen << 4) & 0x3FF         (sub byte 5 bit 6)
// Painter's order (list, sublist, tile, pixel) is preserved; pixels inside one tile are distinct.
module nrc_render #(
    parameter logic [24:0] CHA_BASE = 25'h0800000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        go,
    output logic        done,          // one-cycle pulse when the frame is complete
    output logic        busy,
    input  logic  [7:0] scroll [32],   // vregs 40-5F snapshot
    // sprite RAM render copy
    output logic [12:0] spr_addr,
    input  logic [63:0] spr_data,      // valid the cycle after spr_addr
    // character RAM (SDRAM client)
    output logic        m_req,
    output logic [24:0] m_addr,
    input  logic        m_ack,
    input  logic [63:0] m_rdata,
    // framebuffer (target buffer selected outside)
    output logic [16:0] fb_raddr,
    input  logic [10:0] fb_rdata,      // valid the cycle after fb_raddr
    output logic        fb_we,
    output logic [16:0] fb_waddr,
    output logic [10:0] fb_wdata,
    // statistics (last frame)
    output logic [15:0] st_tiles,
    output logic [15:0] st_fetched,
    output logic [23:0] st_cycles
);
    localparam logic [10:0] UNUSED = 11'h400;
    localparam int SPR_DX = 0, SPR_DY = 8;
    localparam int CLIP_MINX = 8, CLIP_MAXX = 327, CLIP_MAXY = 239;

    typedef enum logic [4:0] {
        S_IDLE, S_CLEAR, S_MAIN_RD, S_MAIN_WAIT, S_MAIN_PARSE, S_SUB_RD, S_SUB_WAIT, S_SUB_PARSE,
        S_TILE, S_TILE_CHK, S_FETCH, S_DRAW, S_DRAIN, S_NEXT, S_DONE
    } st_t;
    st_t st;

    // main entry state
    logic [12:0] mi;                 // main entry index
    logic [15:0] ex, ey;             // entry x/y incl. scroll (16-bit two's complement)
    logic        use_sizes;
    logic  [1:0] gw, gh;
    logic  [9:0] sub_left;           // remaining sublist entries
    logic [12:0] si;                 // sublist entry index
    // sub entry state
    logic [15:0] code;
    logic  [5:0] color;
    logic        flipx, flipy, merge;
    logic  [1:0] lw, lh;             // log2 size
    logic [15:0] sx, sy;             // sub position incl. entry position
    logic  [2:0] col, row;           // tile counters in loop order
    logic [15:0] tileno;
    // tile state
    logic [15:0] xpos, ypos;
    logic  [7:0] xvis, yvis;         // visible destination columns / rows (index = offset 0..7)
    logic [16:0] xfb [8];            // framebuffer column for destination offset (x - 8)
    logic [16:0] yfb [8];            // framebuffer row base (y * 320)
    logic [63:0] tdata [4];          // 32 bytes of the tile
    logic  [1:0] fg;                 // fetch group
    logic  [5:0] pix;                // pixel counter (source row*8 + col)
    logic [16:0] clr;
    logic [23:0] cyc;

    // 10-bit signed -> 16-bit
    function automatic logic [15:0] sx10(input logic [9:0] v);
        return {{6{v[9]}}, v};
    endfunction

    // source pixel -> destination offsets and pen
    wire [2:0] s_col = pix[2:0];
    wire [2:0] s_row = pix[5:3];
    wire [2:0] d_col = flipx ? 3'd7 - s_col : s_col;
    wire [2:0] d_row = flipy ? 3'd7 - s_row : s_row;
    wire [63:0] rowgrp = tdata[s_row[2:1]];
    wire [31:0] rowbytes = s_row[0] ? rowgrp[63:32] : rowgrp[31:0];
    wire [7:0]  pbyte = rowbytes[8*s_col[2:1] +: 8];
    wire [3:0]  pen = s_col[0] ? pbyte[7:4] : pbyte[3:0];
    wire        pvis = xvis[d_col] && yvis[d_row];

    // draw pipeline: stage 1 issues the framebuffer read (fb_raddr registered), the RAM returns the
    // data two cycles later, stage 3 computes and writes.
    logic        p2_valid, p3_valid;
    logic [16:0] p2_addr, p3_addr;
    logic  [3:0] p2_pen, p3_pen;
    logic        in_sub;   // a sub entry is active (S_NEXT: continue its tiles / the sublist)

    // S_NEXT helper: true while another tile of the current sub entry follows
    function automatic logic st_is_tile_loop(input logic [2:0] c, input logic [2:0] r,
                                             input logic [1:0] w, input logic [1:0] h);
        return in_sub && !((c == 3'((4'd1 << w) - 4'd1)) && (r == 3'((4'd1 << h) - 4'd1)));
    endfunction

    // tile visibility (combinational from xpos/ypos)
    logic  [7:0] xvis_c, yvis_c;
    logic [16:0] xfb_c [8];
    logic [16:0] yfb_c [8];
    always_comb begin
        for (int k = 0; k < 8; k++) begin
            logic [15:0] dx, dy;
            dx = xpos + 16'(k);
            if (dx > 16'(CLIP_MAXX)) dx = dx - 16'd512;
            xvis_c[k] = (dx >= 16'(CLIP_MINX)) && (dx <= 16'(CLIP_MAXX));
            xfb_c[k]  = 17'(dx[8:0] - 9'(CLIP_MINX));
            dy = ypos + 16'(k);
            yvis_c[k] = (dy <= 16'(CLIP_MAXY));
            yfb_c[k]  = 17'(dy[7:0]) * 17'd320;
        end
    end

    assign busy = (st != S_IDLE);

    always_ff @(posedge clk) begin
        done  <= 1'b0;
        fb_we <= 1'b0;
        if (reset) begin
            st <= S_IDLE; m_req <= 1'b0; p2_valid <= 1'b0; p3_valid <= 1'b0; in_sub <= 1'b0;
            st_tiles <= '0; st_fetched <= '0; st_cycles <= '0;
        end else begin
            if (st != S_IDLE) cyc <= cyc + 24'd1;

            // draw pipeline stage 3: framebuffer read data for p3_addr is valid now
            if (p3_valid) begin
                fb_waddr <= p3_addr;
                if (merge) begin
                    fb_we    <= 1'b1;
                    fb_wdata <= {1'b0, (fb_rdata[9:0] | {2'b00, p3_pen, 4'b0000})};
                end else if (p3_pen != 4'd0 || fb_rdata == UNUSED) begin
                    fb_we    <= 1'b1;
                    fb_wdata <= {1'b0, color, p3_pen};
                end
            end
            p3_valid <= p2_valid; p3_addr <= p2_addr; p3_pen <= p2_pen;
            p2_valid <= 1'b0;
            if (st == S_SUB_PARSE) in_sub <= 1'b1;
            else if (st == S_MAIN_PARSE) in_sub <= 1'b0;

            case (st)
                S_IDLE: if (go) begin
                    st <= S_CLEAR; clr <= '0; cyc <= '0;
                    st_tiles <= '0; st_fetched <= '0;
                end

                S_CLEAR: begin
                    fb_we <= 1'b1; fb_waddr <= clr; fb_wdata <= UNUSED;
                    clr <= clr + 17'd1;
                    if (clr == 17'd76799) begin st <= S_MAIN_RD; mi <= '0; end
                end

                // spr_addr is registered here and in nrc_spriteram: data is valid two states later
                S_MAIN_RD:   begin spr_addr <= mi; st <= S_MAIN_WAIT; end
                S_MAIN_WAIT: st <= S_MAIN_PARSE;

                S_MAIN_PARSE: begin
                    logic [7:0] b [8];
                    logic [2:0] slot;
                    logic [15:0] scx, scy, x, y;
                    for (int k = 0; k < 8; k++) b[k] = spr_data[8*k +: 8];
                    if (b[3][7]) begin
                        st <= S_DONE;
                    end else begin
                        slot = b[1][3:1];
                        scx = sx10({scroll[{slot, 2'd1}][1:0], scroll[{slot, 2'd0}]});
                        scy = sx10({scroll[{slot, 2'd3}][1:0], scroll[{slot, 2'd2}]});
                        x = sx10({b[5][1:0], b[4]});
                        y = sx10({b[7][1:0], b[6]});
                        ex <= x + scx;
                        ey <= y + scy;
                        use_sizes <= b[1][4];
                        gw <= b[5][3:2];
                        gh <= b[7][3:2];
                        sub_left <= {1'b0, b[1][0], b[0]} + 10'd1;
                        si <= {b[3][4:0], b[2]};
                        if ({b[3][6:0], b[2]} >= 15'h2000) st <= S_NEXT;   // offset >= 64 KiB: skip
                        else st <= S_SUB_RD;
                    end
                end

                S_SUB_RD:   begin spr_addr <= si; st <= S_SUB_WAIT; end
                S_SUB_WAIT: st <= S_SUB_PARSE;

                S_SUB_PARSE: begin
                    logic [7:0] b [8];
                    for (int k = 0; k < 8; k++) b[k] = spr_data[8*k +: 8];
                    code  <= {b[1], b[0]};
                    color <= b[2][5:0];
                    flipx <= b[3][7];
                    flipy <= b[3][6];
                    merge <= b[5][6];
                    lw    <= use_sizes ? b[5][3:2] : gw;
                    lh    <= use_sizes ? b[7][3:2] : gh;
                    sx    <= {7'd0, b[5][0], b[4]} + ex;
                    sy    <= {7'd0, b[7][0], b[6]} + ey;
                    col <= '0; row <= '0;
                    st <= S_TILE;
                end

                S_TILE: begin
                    // loop-order counters -> drawn tile position and number
                    logic [2:0] x0, y0, wm, hm;
                    wm = 3'((4'd1 << lw) - 4'd1);
                    hm = 3'((4'd1 << lh) - 4'd1);
                    x0 = flipx ? wm - col : col;
                    y0 = flipy ? hm - row : row;
                    xpos   <= sx + {10'd0, x0, 3'd0} + 16'(SPR_DX);
                    ypos   <= sy + {10'd0, y0, 3'd0} + 16'(SPR_DY);
                    tileno <= code + (16'(col) << lh) + 16'(row);
                    st <= S_TILE_CHK;
                end

                S_TILE_CHK: begin
                    st_tiles <= st_tiles + 16'd1;
                    xvis <= xvis_c; yvis <= yvis_c;
                    for (int k = 0; k < 8; k++) begin xfb[k] <= xfb_c[k]; yfb[k] <= yfb_c[k]; end
                    if (xvis_c == 8'd0 || yvis_c == 8'd0) begin
                        st <= S_NEXT;          // nothing of this tile is inside the clip
                    end else begin
                        st <= S_FETCH; fg <= '0;
                        m_req <= 1'b1;
                        m_addr <= CHA_BASE + {4'd0, tileno, 5'd0};
                        st_fetched <= st_fetched + 16'd1;
                    end
                end

                S_FETCH: if (m_ack) begin
                    tdata[fg] <= m_rdata;
                    fg <= fg + 2'd1;
                    if (fg == 2'd3) begin
                        m_req <= 1'b0;
                        st <= S_DRAW; pix <= '0;
                    end else begin
                        m_addr <= m_addr + 25'd8;
                    end
                end

                S_DRAW: begin
                    // stage 1: issue the framebuffer read of this source pixel's destination
                    if (pvis) begin
                        fb_raddr <= yfb[d_row] + xfb[d_col];
                        p2_valid <= 1'b1;
                        p2_addr  <= yfb[d_row] + xfb[d_col];
                        p2_pen   <= pen;
                    end
                    pix <= pix + 6'd1;
                    if (pix == 6'd63) st <= S_DRAIN;
                end

                S_DRAIN: if (!p2_valid && !p3_valid) st <= S_NEXT;   // last pixel written

                S_NEXT: begin
                    // next tile / next sub entry / next main entry
                    if (st_is_tile_loop(col, row, lw, lh)) begin
                        if (row == 3'((4'd1 << lh) - 4'd1)) begin row <= '0; col <= col + 3'd1; end
                        else row <= row + 3'd1;
                        st <= S_TILE;
                    end else if (in_sub && sub_left > 10'd1 && si != 13'h1FFF) begin
                        sub_left <= sub_left - 10'd1;
                        si <= si + 13'd1;
                        st <= S_SUB_RD;
                    end else if (mi != 13'h1FFF) begin
                        mi <= mi + 13'd1;
                        st <= S_MAIN_RD;
                    end else begin
                        st <= S_DONE;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    st_cycles <= cyc;
                    st <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
