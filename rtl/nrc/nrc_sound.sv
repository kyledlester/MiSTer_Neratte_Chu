// Neratte Chu (Seta ST-0016) MiSTer core -- ST-0016 PCM sound (8 voices).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Behavioural reference: MAME master src/devices/sound/st0016.cpp (commit dcca0e9b), which adds
// PCB-fitted non-linear decoding, linear interpolation and an exponential volume law to MAME 0.289.
// Golden model: scripts/research/st0016_snd_ref.py. Details: docs/ST0016_AUDIO.md.
//
// One output sample per ce_snd (62.5 kHz = 8 MHz / 128). For each of the 8 voices whose flags have
// bit 1 or 2 set: fetch the sample bytes at pos and next_pos(pos) from character RAM (SDRAM; one
// cached 8-byte group per voice), decode (linear or non-linear, voice 7 reg $1F bit 1), interpolate
// with frac, advance pos/frac, handle loop/end, and add (out * gain) >> 8 to L and R.
// Deviation (documented): MAME's s32 product (b - a) * frac can overflow (C++ UB, wraps in practice)
// for steps > 32767; the RTL computes it exactly. The 8-voice sum saturates to 16 bits.
module nrc_sound #(
    parameter logic [24:0] CHA_BASE = 25'h0800000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce_snd,
    input  logic  [7:0] cpu_addr,
    input  logic        cpu_we,
    input  logic  [7:0] cpu_wdata,
    output logic  [7:0] cpu_rdata,
    // SDRAM client (character RAM sample reads)
    output logic        m_req,
    output logic [24:0] m_addr,
    input  logic        m_ack,
    input  logic [63:0] m_rdata,
    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r
);
    // ------------------------------------------------------------ register file (readback)
    logic [7:0] regs [256];
    always_ff @(posedge clk) begin
        if (cpu_we) regs[cpu_addr] <= cpu_wdata;
        cpu_rdata <= regs[cpu_addr];
    end

    // ------------------------------------------------------------ tables
    // volume byte -> gain x256 (MAME master m_voltab; bit 7 ignored); regenerate with
    // scripts/gen_sound_tables.py
    function automatic logic [8:0] voltab(input logic [7:0] d);
        logic [8:0] g;
        g = 9'd0;
        case (d[6:0])
            // VOLTAB BEGIN
            7'd63: g = 9'd1;
            7'd64: g = 9'd1;
            7'd65: g = 9'd1;
            7'd66: g = 9'd1;
            7'd67: g = 9'd1;
            7'd68: g = 9'd1;
            7'd69: g = 9'd1;
            7'd70: g = 9'd1;
            7'd71: g = 9'd2;
            7'd72: g = 9'd2;
            7'd73: g = 9'd2;
            7'd74: g = 9'd2;
            7'd75: g = 9'd2;
            7'd76: g = 9'd3;
            7'd77: g = 9'd3;
            7'd78: g = 9'd3;
            7'd79: g = 9'd4;
            7'd80: g = 9'd4;
            7'd81: g = 9'd4;
            7'd82: g = 9'd5;
            7'd83: g = 9'd5;
            7'd84: g = 9'd6;
            7'd85: g = 9'd6;
            7'd86: g = 9'd7;
            7'd87: g = 9'd8;
            7'd88: g = 9'd8;
            7'd89: g = 9'd9;
            7'd90: g = 9'd10;
            7'd91: g = 9'd11;
            7'd92: g = 9'd12;
            7'd93: g = 9'd13;
            7'd94: g = 9'd14;
            7'd95: g = 9'd16;
            7'd96: g = 9'd17;
            7'd97: g = 9'd19;
            7'd98: g = 9'd21;
            7'd99: g = 9'd23;
            7'd100: g = 9'd25;
            7'd101: g = 9'd27;
            7'd102: g = 9'd29;
            7'd103: g = 9'd32;
            7'd104: g = 9'd34;
            7'd105: g = 9'd38;
            7'd106: g = 9'd42;
            7'd107: g = 9'd46;
            7'd108: g = 9'd51;
            7'd109: g = 9'd55;
            7'd110: g = 9'd59;
            7'd111: g = 9'd64;
            7'd112: g = 9'd68;
            7'd113: g = 9'd76;
            7'd114: g = 9'd85;
            7'd115: g = 9'd93;
            7'd116: g = 9'd102;
            7'd117: g = 9'd110;
            7'd118: g = 9'd119;
            7'd119: g = 9'd128;
            7'd120: g = 9'd136;
            7'd121: g = 9'd153;
            7'd122: g = 9'd170;
            7'd123: g = 9'd187;
            7'd124: g = 9'd204;
            7'd125: g = 9'd221;
            7'd126: g = 9'd238;
            7'd127: g = 9'd256;
            // VOLTAB END
            default: g = 9'd0;
        endcase
        return g;
    endfunction

    // sample byte -> s16 (MAME master m_linear / m_nonlinear)
    function automatic logic signed [15:0] decode(input logic [7:0] c, input logic nonlin);
        logic [6:0]  mag;
        logic [2:0]  e;
        logic [3:0]  m;
        logic [11:0] v;
        logic [15:0] u;
        if (!nonlin) return {c, 8'h00};
        mag = c[7] ? ((c == 8'h80) ? 7'd127 : 7'(8'd0 - c)) : c[6:0];
        e = mag[6:4];
        m = mag[3:0];
        v = (e == 3'd0) ? {7'd0, m, 1'b0} : (12'({1'b1, m}) << e);
        u = {1'b0, v, 3'b000};
        return c[7] ? -$signed(u) : $signed(u);
    endfunction

    // MAME master voice_t::next_pos
    function automatic logic [24:0] next_pos(input logic [24:0] p, input logic lponce,
            input logic [23:0] lpend, input logic [23:0] lpstart, input logic [23:0] vend,
            input logic loop);
        logic [24:0] n;
        n = p + 25'd1;
        if (lponce) return (n >= {1'b0, lpend}) ? {1'b0, lpstart} : n;
        if (n >= {1'b0, vend}) return loop ? {1'b0, lpstart} : p;
        return n;
    endfunction

    // ------------------------------------------------------------ voice state
    logic [23:0] v_start [8], v_lpstart [8], v_lpend [8], v_end [8];
    logic [15:0] v_freq [8];
    logic  [8:0] v_voll [8], v_volr [8];
    logic  [7:0] v_flags [8];
    logic [24:0] v_pos [8];
    logic [15:0] v_frac [8];
    logic        v_lponce [8];
    logic        nonlinear;
    // per-voice sample cache: one 8-byte group of character RAM
    logic        c_valid [8];
    logic [17:0] c_tag [8];
    logic [63:0] c_data [8];

    // ------------------------------------------------------------ engine
    // The per-voice work is split into short pipeline states (timing at 100 MHz); a sample has
    // ~1600 clk_sys of budget and 8 voices need < 200 even with cache misses.
    typedef enum logic [3:0] {E_IDLE, E_LOAD, E_NP, E_FETCH_A, E_FETCH_B, E_DEC, E_MUL, E_CALC,
                              E_WB, E_VOL, E_ACC, E_OUT} est_t;
    est_t es;
    logic  [2:0] v;
    // local copy of the voice being processed
    logic        l_act, l_loop, l_lponce;
    logic [23:0] l_lpstart, l_lpend, l_end;
    logic [15:0] l_freq;
    logic  [8:0] l_voll, l_volr;
    logic [24:0] pos, np, p2;
    logic [15:0] frac, f2;
    logic  [7:0] ba, bb;
    logic signed [15:0] sa, sb;
    logic signed [16:0] diff;
    logic signed [33:0] prod;
    logic signed [25:0] ml, mr;
    logic        hit_lpend, hit_end;
    logic        touched;          // CPU wrote reg $16 of voice v while it was being processed
    logic signed [19:0] acc_l, acc_r;
    logic signed [15:0] outv;

    wire [20:0] a_ofs = pos[20:0];
    wire [20:0] b_ofs = np[20:0];
    wire a_hit = c_valid[v] && c_tag[v] == a_ofs[20:3];
    wire b_hit = c_valid[v] && c_tag[v] == b_ofs[20:3];

    // CPU register writes; key-on per MAME voice_t::reg_w (compare with the live flags)
    wire [2:0] wv = cpu_addr[7:5];
    wire [4:0] wr = cpu_addr[4:0];
    wire kon = cpu_we && wr == 5'h16 && cpu_wdata != v_flags[wv] && cpu_wdata != 8'h00;
    wire flags_wr_v = cpu_we && wr == 5'h16 && wv == v;

    always_ff @(posedge clk) begin
        if (reset) begin
            es <= E_IDLE; m_req <= 1'b0; nonlinear <= 1'b0;
            out_l <= '0; out_r <= '0;
            for (int i = 0; i < 8; i++) begin
                v_start[i] <= '0; v_lpstart[i] <= '0; v_lpend[i] <= '0; v_end[i] <= '0;
                v_freq[i] <= '0; v_voll[i] <= '0; v_volr[i] <= '0; v_flags[i] <= '0;
                v_pos[i] <= '0; v_frac[i] <= '0; v_lponce[i] <= 1'b0; c_valid[i] <= 1'b0;
            end
        end else begin
            if (flags_wr_v) touched <= 1'b1;
            // ---------------- engine
            case (es)
                E_IDLE: if (ce_snd) begin
                    v <= 3'd0; acc_l <= '0; acc_r <= '0; es <= E_LOAD;
                end
                E_LOAD: begin
                    l_act     <= v_flags[v][2:1] != 2'b00;
                    l_loop    <= v_flags[v][0];
                    l_lponce  <= v_lponce[v];
                    l_lpstart <= v_lpstart[v];
                    l_lpend   <= v_lpend[v];
                    l_end     <= v_end[v];
                    l_freq    <= v_freq[v];
                    l_voll    <= v_voll[v];
                    l_volr    <= v_volr[v];
                    pos       <= v_pos[v];
                    frac      <= v_frac[v];
                    touched   <= flags_wr_v;
                    es        <= E_NP;
                end
                E_NP: begin
                    if (l_act) begin
                        np <= next_pos(pos, l_lponce, l_lpend, l_lpstart, l_end, l_loop);
                        es <= E_FETCH_A;
                    end else if (v == 3'd7) es <= E_OUT;
                    else begin v <= v + 3'd1; es <= E_LOAD; end
                end
                E_FETCH_A: begin
                    if (a_hit) begin
                        ba <= c_data[v][8*a_ofs[2:0] +: 8];
                        es <= E_FETCH_B;
                    end else if (!m_req) begin
                        m_req <= 1'b1; m_addr <= CHA_BASE + {4'd0, a_ofs[20:3], 3'd0};
                    end else if (m_ack) begin
                        m_req <= 1'b0;
                        c_valid[v] <= 1'b1; c_tag[v] <= a_ofs[20:3]; c_data[v] <= m_rdata;
                    end
                end
                E_FETCH_B: begin
                    if (b_hit) begin
                        bb <= c_data[v][8*b_ofs[2:0] +: 8];
                        es <= E_DEC;
                    end else if (!m_req) begin
                        m_req <= 1'b1; m_addr <= CHA_BASE + {4'd0, b_ofs[20:3], 3'd0};
                    end else if (m_ack) begin
                        m_req <= 1'b0;
                        c_valid[v] <= 1'b1; c_tag[v] <= b_ofs[20:3]; c_data[v] <= m_rdata;
                    end
                end
                E_DEC: begin
                    logic signed [15:0] da, db;
                    da = decode(ba, nonlinear);
                    db = decode(bb, nonlinear);
                    sa   <= da;
                    diff <= 17'(db) - 17'(da);
                    {f2[15:0]} <= frac + l_freq;                          // low 16 bits
                    p2   <= pos + 25'((17'(frac) + 17'(l_freq)) >> 16);   // carry into pos
                    es   <= E_MUL;
                end
                E_MUL: begin
                    prod      <= diff * $signed({1'b0, frac});
                    hit_lpend <= (p2 >= {1'b0, l_lpend});
                    hit_end   <= (p2 >= {1'b0, l_end});
                    es        <= E_CALC;
                end
                E_CALC: begin
                    outv <= 16'(sa + 16'(prod >>> 16));
                    es   <= E_WB;
                end
                E_WB: begin
                    // write back unless the CPU wrote this voice's flags while it was processed
                    // (MAME: a register write follows the stream update, so the write wins)
                    if (!touched && !flags_wr_v) begin
                        v_frac[v] <= f2;
                        if (l_lponce) begin
                            v_pos[v] <= hit_lpend ? {1'b0, l_lpstart} : p2;
                        end else if (hit_end) begin
                            if (l_loop) begin
                                v_pos[v] <= {1'b0, l_lpstart};
                                v_lponce[v] <= 1'b1;
                            end else begin
                                v_flags[v] <= 8'h00; v_pos[v] <= '0; v_frac[v] <= '0;
                            end
                        end else begin
                            v_pos[v] <= p2;
                        end
                    end
                    es <= E_VOL;
                end
                E_VOL: begin
                    ml <= outv * $signed({1'b0, l_voll});
                    mr <= outv * $signed({1'b0, l_volr});
                    es <= E_ACC;
                end
                E_ACC: begin
                    acc_l <= acc_l + 20'(ml >>> 8);
                    acc_r <= acc_r + 20'(mr >>> 8);
                    if (v == 3'd7) es <= E_OUT;
                    else begin v <= v + 3'd1; es <= E_LOAD; end
                end
                E_OUT: begin
                    out_l <= (acc_l > 20'sd32767) ? 16'sd32767 : (acc_l < -20'sd32768) ? -16'sd32768 : 16'(acc_l);
                    out_r <= (acc_r > 20'sd32767) ? 16'sd32767 : (acc_r < -20'sd32768) ? -16'sd32768 : 16'(acc_r);
                    es <= E_IDLE;
                end
                default: es <= E_IDLE;
            endcase

            // ---------------- CPU register writes (after the engine: they win on conflicts)
            if (cpu_we) begin
                case (wr)
                    5'h00: v_start[wv][7:0]     <= cpu_wdata;
                    5'h01: v_start[wv][15:8]    <= cpu_wdata;
                    5'h02: v_start[wv][23:16]   <= cpu_wdata;
                    5'h04: v_lpstart[wv][7:0]   <= cpu_wdata;
                    5'h05: v_lpstart[wv][15:8]  <= cpu_wdata;
                    5'h06: v_lpstart[wv][23:16] <= cpu_wdata;
                    5'h08: v_lpend[wv][7:0]     <= cpu_wdata;
                    5'h09: v_lpend[wv][15:8]    <= cpu_wdata;
                    5'h0A: v_lpend[wv][23:16]   <= cpu_wdata;
                    5'h0C: v_end[wv][7:0]       <= cpu_wdata;
                    5'h0D: v_end[wv][15:8]      <= cpu_wdata;
                    5'h0E: v_end[wv][23:16]     <= cpu_wdata;
                    5'h10: v_freq[wv][7:0]      <= cpu_wdata;
                    5'h11: v_freq[wv][15:8]     <= cpu_wdata;
                    5'h14: v_voll[wv]           <= voltab(cpu_wdata);
                    5'h15: v_volr[wv]           <= voltab(cpu_wdata);
                    5'h16: begin
                        if (kon) begin
                            v_pos[wv]    <= {1'b0, v_start[wv]};
                            v_frac[wv]   <= '0;
                            v_lponce[wv] <= 1'b0;
                        end
                        v_flags[wv] <= cpu_wdata;
                    end
                    5'h1F: if (wv == 3'd7) nonlinear <= cpu_wdata[1];
                    default: ;
                endcase
            end
        end
    end
endmodule
