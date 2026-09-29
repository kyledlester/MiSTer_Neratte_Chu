// Neratte Chu (Seta ST-0016) MiSTer core -- ST-0016 CPU side: Z80, bus, registers, RAMs, DMA.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Behavioural contract: MAME 0.289 st0016_cpu_device (cpu_internal_map / cpu_internal_io_map,
// vregs_r/w, bank handlers) plus the board glue of simple_st0016.cpp (st0016_mem, st0016_io, mux).
// Address map and register list: docs/MEMORY_MAP.md.
//
// Bus timing: nrc_cpu raises rd_n/wr_n low right after a cen edge. This module detects the start
// of each access, stalls the CPU clock enable (cpu_stall) until the access has completed, and
// presents read data in `din`, which stays valid until the next access. Internal (BRAM/register)
// accesses complete two cycles after the start (the T80 address/data are registered once first,
// so no RAM port is driven straight from the T80); SDRAM accesses when the arbiter acknowledges.
// The credit scheduler (nrc_clocks) repays the stall cycles, so CPU time stays exactly 8 MHz.
module nrc_st0016 #(
    parameter logic [24:0] CHA_BASE = 25'h0800000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce_cpu,
    input  logic        ce_pix,
    input  logic        ce_snd,
    output logic        cpu_stall,
    // fixed ROM BRAM load port (from nrc_loader)
    input  logic        from_we,
    input  logic [13:0] from_addr,
    input  logic [15:0] from_data,
    // SDRAM clients: CPU (extrom bank window, charram window) and DMA
    output logic        cm_req,
    output logic        cm_we,
    output logic [24:0] cm_addr,
    output logic [15:0] cm_wdata,
    output logic  [1:0] cm_be,
    input  logic        cm_ack,
    output logic        dm_req,
    output logic        dm_we,
    output logic [24:0] dm_addr,
    output logic [15:0] dm_wdata,
    output logic  [1:0] dm_be,
    input  logic        dm_ack,
    output logic        sm_req,
    output logic [24:0] sm_addr,
    input  logic        sm_ack,
    input  logic [63:0] m_rdata,
    // video
    input  logic        irq_event,        // vblank start: IRQ + render snapshot instant
    input  logic        pal_snap,         // palette snapshot (irq_event while the renderer is idle)
    output logic        render_go,
    input  logic        render_done,
    input  logic [12:0] spr_raddr,
    output logic [63:0] spr_rdata,
    output logic [7:0]  scroll_snap [32], // vregs 40-5F at the snapshot
    output logic [7:0]  tm_base_snap [8], // per tilemap slot at the snapshot: reg1 (0 = off)
    output logic [7:0]  tm_prio_snap,     //   reg3 == $FF (drawn over the sprites)
    output logic [7:0]  tm_merge_snap,    //   reg7 == $12 (merge mode)
    output logic        flip_screen,      // CRT register $74 bits 7-5 != 0 (the game's hardware flip)
    input  logic        pal_snap_buf,
    input  logic        disp_buf,
    input  logic [10:0] disp_pen,
    output logic [23:0] disp_rgb,
    // inputs
    input  logic [31:0] joy0,
    input  logic [31:0] joy1,
    input  logic  [7:0] dsw1,
    input  logic  [7:0] dsw2,
    // audio
    output logic signed [15:0] snd_l,
    output logic signed [15:0] snd_r,
    // diagnostics
    output logic [15:0] dbg_pc,
    output logic [15:0] dbg_irqs,
    output logic [15:0] dbg_nmis,
    output logic [15:0] dbg_snap_drops,
    output logic [15:0] dbg_dma_count
);
    // ------------------------------------------------------------------ CPU
    logic [15:0] a_cpu, a;       // a / dout: registered copies of the T80 bus (timing: every
    logic  [7:0] dout_cpu, dout, din;   // consumer below starts from a flop, see B_WAIT)
    logic m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, iff1;
    logic int_n, nmi_n;

    nrc_cpu cpu (
        .clk(clk), .reset(reset), .cen(ce_cpu),
        .int_n(int_n), .nmi_n(nmi_n),
        .di(din), .dout(dout_cpu), .a(a_cpu),
        .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n),
        .rfsh_n(rfsh_n), .halt_n(halt_n), .iff1(iff1), .pc(dbg_pc), .sp()
    );

    wire int_ack = !m1_n && !iorq_n;

    always_ff @(posedge clk) begin
        a    <= a_cpu;
        dout <= dout_cpu;
    end

    nrc_irq irq (
        .clk(clk), .reset(reset), .ce_pix(ce_pix), .ce_cpu(ce_cpu),
        .irq_event(irq_event), .int_ack(int_ack), .iff1(iff1),
        .int_n(int_n), .nmi_n(nmi_n),
        .irq_count(dbg_irqs), .nmi_count(dbg_nmis), .nmi_skipped()
    );

    // ------------------------------------------------------------------ registers
    logic  [7:0] rom_bank;
    logic  [3:0] spr_bank0, spr_bank1;
    logic [15:0] char_bank;
    logic  [1:0] pal_bank;
    logic  [7:0] mux_sel;
    logic  [7:0] scroll [32];
    logic  [7:0] tm_base [8];
    logic  [7:0] tm_prio, tm_merge;
    logic  [7:0] dmareg [9];           // A0..A8
    logic [15:0] lfsr;

    // ------------------------------------------------------------------ memories
    // fixed ROM window 0000-7FFF (16K x 16, loaded by nrc_loader)
    logic [15:0] from_mem [16384];
    logic [15:0] from_q;
    always_ff @(posedge clk) begin
        if (from_we) from_mem[from_addr] <= from_data;
        from_q <= from_mem[a[14:1]];
    end

    // board RAM: E000-E87F and F000-FFFF (8 KiB array indexed by A12..A0)
    wire wram_hit = (a[15:12] == 4'hF) || (a[15:11] == 5'b11100) || (a[15:7] == 9'b1110_1000_0);
    logic [7:0] wram [8192];
    logic [7:0] wram_q;
    logic       wram_we;
    always_ff @(posedge clk) begin
        if (wram_we) wram[a[12:0]] <= dout;
        wram_q <= wram[a[12:0]];
    end

    // vregs 00-BF readback store
    logic [7:0] vregs [256];
    logic [7:0] vregs_q;
    logic       vregs_we;
    always_ff @(posedge clk) begin
        if (vregs_we) vregs[a[7:0]] <= dout;
        vregs_q <= vregs[a[7:0]];
    end

    // sprite RAM
    wire  [15:0] spr_cpu_addr = {a[12] ? spr_bank1 : spr_bank0, a[11:0]};
    logic        spr_we, spr_busy;
    logic  [7:0] spr_q;
    nrc_spriteram spram (
        .clk(clk), .reset(reset),
        .cpu_addr(spr_cpu_addr), .cpu_we(spr_we), .cpu_wdata(dout), .cpu_rdata(spr_q),
        .cpu_busy(spr_busy),
        .snap(irq_event), .render_go(render_go), .render_done(render_done), .render_active(),
        .r_addr(spr_raddr), .r_data(spr_rdata), .snap_drops(dbg_snap_drops), .fifo_max()
    );

    // palette
    logic       pal_we, pal_busy;
    logic [7:0] pal_q;
    nrc_palette palette (
        .clk(clk), .reset(reset),
        .cpu_addr({pal_bank, a[8:0]}), .cpu_we(pal_we), .cpu_wdata(dout), .cpu_rdata(pal_q),
        .cpu_busy(pal_busy),
        .snap(pal_snap), .snap_buf(pal_snap_buf), .copying(),
        .disp_buf(disp_buf), .disp_pen(disp_pen), .disp_rgb(disp_rgb)
    );

    // sound
    logic       snd_we;
    logic [7:0] snd_q;
    nrc_sound #(.CHA_BASE(CHA_BASE)) sound (
        .clk(clk), .reset(reset), .ce_snd(ce_snd),
        .cpu_addr(a[7:0]), .cpu_we(snd_we), .cpu_wdata(dout), .cpu_rdata(snd_q),
        .m_req(sm_req), .m_addr(sm_addr), .m_ack(sm_ack), .m_rdata(m_rdata),
        .out_l(snd_l), .out_r(snd_r)
    );

    // inputs
    logic [7:0] p1, p2, mux_q;
    nrc_inputs inputs (
        .joy0(joy0), .joy1(joy1), .dsw1(dsw1), .dsw2(dsw2), .mux(mux_sel),
        .p1(p1), .p2(p2), .mux_out(mux_q)
    );

    // ------------------------------------------------------------------ bus
    typedef enum logic [2:0] {B_IDLE, B_WAIT, B_DECODE, B_SDRAM, B_DONE, B_DMA} bstate_t;
    bstate_t bs;

    wire acc_req   = !rd_n || !wr_n;
    wire acc_start = acc_req && (bs == B_IDLE);
    wire is_io     = !iorq_n;
    wire is_rd     = !rd_n;

    // extrom single-line read cache (8 bytes): ROM is read-only after loading
    logic        rc_valid;
    logic [18:0] rc_tag;
    logic [63:0] rc_data;
    wire  [21:0] ext_addr = {rom_bank, a[13:0]};

    // stall: from the start cycle until the access is done (DONE state clears it)
    assign cpu_stall = acc_start || (bs == B_WAIT) || (bs == B_DECODE) || (bs == B_SDRAM) || (bs == B_DMA);

    logic        sd_is_rom;
    logic  [2:0] sd_byte;

    // DMA
    logic [23:0] dma_src, dma_dst;
    logic [21:0] dma_len;
    logic        dma_phase;      // 0 = read source, 1 = write destination
    logic  [7:0] dma_byte;

    always_ff @(posedge clk) begin
        wram_we  <= 1'b0;
        vregs_we <= 1'b0;
        spr_we   <= 1'b0;
        pal_we   <= 1'b0;
        snd_we   <= 1'b0;
        if (reset) begin
            bs <= B_IDLE;
            cm_req <= 1'b0; dm_req <= 1'b0;
            rom_bank <= 8'd0; spr_bank0 <= 4'd0; spr_bank1 <= 4'd0; char_bank <= 16'd0;
            pal_bank <= 2'd0; mux_sel <= 8'd0;
            rc_valid <= 1'b0;
            lfsr <= 16'hACE1;
            dbg_dma_count <= '0;
            for (int i = 0; i < 32; i++) scroll[i] <= 8'd0;
            for (int i = 0; i < 8; i++) tm_base[i] <= 8'd0;
            tm_prio <= 8'd0; tm_merge <= 8'd0;
            flip_screen <= 1'b0;
            for (int i = 0; i < 9; i++) dmareg[i] <= 8'd0;
        end else begin
            case (bs)
                // B_WAIT: a/dout (registered) and the RAM read ports addressed from them settle
                B_IDLE: if (acc_req) bs <= B_WAIT;
                B_WAIT: bs <= B_DECODE;

                B_DECODE: begin
                    bs <= B_DONE;
                    if (is_io) begin
                        if (is_rd) begin
                            if (a[7:0] <= 8'h01) begin
                                din  <= a[0] ? lfsr[15:8] : lfsr[7:0];
                                lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                            end
                            else if (a[7:0] < 8'hC0) din <= vregs_q;
                            else if (a[7:0] == 8'hC0) din <= p1;
                            else if (a[7:0] == 8'hC1 || a[7:0] == 8'hC3) din <= p2;
                            else if (a[7:0] == 8'hC2) din <= mux_q;
                            else din <= 8'h00;
                        end else begin
                            if (a[7:0] < 8'hC0) begin
                                vregs_we <= 1'b1;
                                if (a[7:5] == 3'b010) scroll[a[4:0]] <= dout;
                                if (a[7:0] == 8'h74) flip_screen <= (dout[7:5] != 3'b000);
                                if (a[7:6] == 2'b00) begin
                                    if (a[2:0] == 3'd1) tm_base[a[5:3]] <= dout;
                                    if (a[2:0] == 3'd3) tm_prio[a[5:3]] <= (dout == 8'hFF);
                                    if (a[2:0] == 3'd7) tm_merge[a[5:3]] <= (dout == 8'h12);
                                end
                                if (a[7:0] >= 8'hA0 && a[7:0] <= 8'hA8) dmareg[a[3:0]] <= dout;
                                if (a[7:0] == 8'hA8 && dout[5]) begin
                                    dma_src   <= {dmareg[2], dmareg[1], dmareg[0]} << 1;
                                    dma_dst   <= {dmareg[5], dmareg[4], dmareg[3]} << 1;
                                    dma_len   <= ({dout[4:0], dmareg[7], dmareg[6]} + 22'd1) << 1;
                                    dma_phase <= 1'b0;
                                    dbg_dma_count <= dbg_dma_count + 16'd1;
                                    bs <= B_DMA;
                                end
                            end
                            case (a[7:0])
                                8'hC0: mux_sel <= dout;
                                8'hE1: rom_bank <= dout;
                                8'hE2: begin spr_bank0 <= dout[3:0]; spr_bank1 <= dout[7:4]; end
                                8'hE3: char_bank[7:0]  <= dout;
                                8'hE4: char_bank[15:8] <= dout;
                                8'hE5: pal_bank <= dout[1:0];
                                default: ;
                            endcase
                        end
                    end else begin
                        // memory
                        if (a[15] == 1'b0) begin
                            if (is_rd) din <= a[0] ? from_q[15:8] : from_q[7:0];
                        end else if (a[15:14] == 2'b10) begin
                            if (is_rd) begin
                                if (rc_valid && rc_tag == ext_addr[21:3]) begin
                                    din <= rc_data[8*ext_addr[2:0] +: 8];
                                end else begin
                                    cm_req <= 1'b1; cm_we <= 1'b0;
                                    cm_addr <= {3'b000, ext_addr};
                                    sd_is_rom <= 1'b1; sd_byte <= ext_addr[2:0];
                                    bs <= B_SDRAM;
                                end
                            end
                        end else if (a[15:13] == 3'b110) begin
                            if (is_rd) din <= spr_q;
                            else if (spr_busy) bs <= B_DECODE;  // FIFO nearly full: wait
                            else spr_we <= 1'b1;
                        end else if (a[15:8] == 8'hE9) begin
                            if (is_rd) din <= snd_q; else snd_we <= 1'b1;
                        end else if (a[15:9] == 7'b1110_101) begin
                            if (is_rd) din <= pal_q;
                            else if (pal_busy) bs <= B_DECODE;  // snapshot copy running: wait
                            else pal_we <= 1'b1;
                        end else if (a[15:5] == 11'b1110_1100_000) begin
                            cm_req  <= 1'b1;
                            cm_we   <= !is_rd;
                            cm_addr <= CHA_BASE + {4'd0, char_bank, a[4:0]};
                            cm_wdata <= {dout, dout};
                            cm_be   <= a[0] ? 2'b10 : 2'b01;
                            sd_is_rom <= 1'b0; sd_byte <= a[2:0];
                            bs <= B_SDRAM;
                        end else if (wram_hit) begin
                            if (is_rd) din <= wram_q; else wram_we <= 1'b1;
                        end else begin
                            if (is_rd) din <= 8'h00;
                        end
                    end
                end

                B_SDRAM: if (cm_ack) begin
                    cm_req <= 1'b0;
                    bs <= B_DONE;
                    if (is_rd) begin
                        din <= m_rdata[8*sd_byte +: 8];
                        if (sd_is_rom) begin
                            rc_valid <= 1'b1; rc_tag <= ext_addr[21:3]; rc_data <= m_rdata;
                        end
                    end
                end

                B_DMA: begin
                    // MAME vregs_w: byte copy extrom -> charram while src < 4 MiB and dst < 2 MiB
                    if (!dm_req) begin
                        if (dma_len == 0 || dma_src >= 24'h400000 || dma_dst >= 24'h200000) begin
                            bs <= B_DONE;
                        end else begin
                            dm_req <= 1'b1;
                            if (!dma_phase) begin
                                dm_we <= 1'b0; dm_addr <= {1'b0, dma_src};
                            end else begin
                                dm_we <= 1'b1; dm_addr <= CHA_BASE + {1'b0, dma_dst};
                                dm_wdata <= {dma_byte, dma_byte};
                                dm_be <= dma_dst[0] ? 2'b10 : 2'b01;
                            end
                        end
                    end else if (dm_ack) begin
                        dm_req <= 1'b0;
                        if (!dma_phase) begin
                            dma_byte <= m_rdata[8*dma_src[2:0] +: 8];
                            dma_phase <= 1'b1;
                        end else begin
                            dma_phase <= 1'b0;
                            dma_src <= dma_src + 24'd1;
                            dma_dst <= dma_dst + 24'd1;
                            dma_len <= dma_len - 22'd1;
                        end
                    end
                end

                B_DONE: if (!acc_req) bs <= B_IDLE;

                default: bs <= B_IDLE;
            endcase
        end
    end

    // scroll snapshot at the render instant (the IRQ / vblank event)
    always_ff @(posedge clk) begin
        if (irq_event) begin
            for (int i = 0; i < 32; i++) scroll_snap[i] <= scroll[i];
            for (int i = 0; i < 8; i++) tm_base_snap[i] <= tm_base[i];
            tm_prio_snap <= tm_prio; tm_merge_snap <= tm_merge;
        end
    end
endmodule
