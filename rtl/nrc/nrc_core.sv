// Neratte Chu (Seta ST-0016) MiSTer core -- system integration below the MiSTer wrapper.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// clocks + raster + ROM loader + SDRAM arbiter + ST-0016 (CPU side) + renderer + framebuffers +
// display pipeline. The SDRAM PHY (rtl/vendor/sdram.sv) is outside, so benches can substitute a
// behavioural memory. See docs/ARCHITECTURE.md.
//
// SDRAM clients (priority order): 0 loader, 1 CPU, 2 DMA, 3 sound, 4 renderer.
// Frame flow: at vblank_start (irq_event) the IRQ is raised, a completed render (if any) becomes the
// displayed buffer, the palette is copied into the new back buffer's slot and the sprite-RAM
// snapshot starts the next render into the back buffer.
module nrc_core #(
    parameter logic [24:0] EXTROM_END = 25'h0400000,
    parameter logic [24:0] CHA_BASE   = 25'h0800000,
    parameter logic [24:0] CHA_END    = 25'h0A00000,
    parameter int          CPU_NUM    = 176,     // CPU time base = CPU_NUM/CPU_DEN of clk_sys (8 MHz)
    parameter int          CPU_DEN    = 2205
) (
    input  logic        clk,
    input  logic        init,          // PLL not locked: memory system reset
    input  logic        reset,         // OSD / user / HPS reset
    input  logic        sim_turbo,     // simulation only: run the CPU time base flat out (tie 0)
    // HPS download
    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    output logic        ioctl_wait,
    // SDRAM channel (sdram.sv ch1)
    output logic [26:1] sd_addr,
    output logic [15:0] sd_din,
    output logic  [1:0] sd_be,
    output logic        sd_req,
    output logic        sd_rnw,
    input  logic [63:0] sd_dout,
    input  logic        sd_ready,
    // controls
    input  logic [31:0] joy0,
    input  logic [31:0] joy1,
    input  logic        dbg_overlay,
    // video
    output logic        ce_pix,
    output logic [23:0] rgb,
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,
    output logic        vsync,
    // audio
    output logic signed [15:0] snd_l,
    output logic signed [15:0] snd_r,
    // status
    output logic        rom_ready,
    output logic [15:0] dbg_pc,
    output logic [15:0] dbg_frames,
    output logic [15:0] dbg_render_ms100,   // last render time in units of 1024 clk_sys = 10.2 us
    output logic [15:0] dbg_snap_drops,
    output logic [15:0] dbg_irqs,
    output logic [15:0] dbg_nmis
);
    // ------------------------------------------------------------------ clocks / raster
    logic tick8, ce_snd, ce_cpu, cpu_stall;
    nrc_clocks #(.NUM(CPU_NUM), .DEN(CPU_DEN)) clocks (
        .clk(clk), .rst(reset), .rst_video(init), .cpu_stall(cpu_stall), .turbo(sim_turbo),
        .ce_pix(ce_pix), .tick8(tick8), .ce_snd(ce_snd), .ce_cpu(ce_cpu),
        .credits(), .lost_credits()
    );

    logic [8:0] hcnt, vcnt, vx;
    logic [7:0] vy;
    logic t_hb, t_vb, t_hs, t_vs, vblank_start, frame_start;
    // The raster free-runs through OSD resets and ROM downloads (only PLL loss resets it): a CRT keeps
    // sync, so the MiSTer OSD/loading screen stays visible on analog outputs.
    nrc_video_timing timing (
        .clk(clk), .rst(init), .ce_pix(ce_pix),
        .hcnt(hcnt), .vcnt(vcnt), .x(vx), .y(vy),
        .hblank(t_hb), .vblank(t_vb), .hsync(t_hs), .vsync(t_vs),
        .vblank_start(vblank_start), .frame_start(frame_start)
    );

    // ------------------------------------------------------------------ loader / DIPs
    logic        l_req, l_ack;
    logic [24:0] l_addr;
    logic [15:0] l_wdata;
    logic        from_we;
    logic [13:0] from_addr;
    logic [15:0] from_data;
    logic        l_wait;
    nrc_loader #(.EXTROM_END(EXTROM_END), .CHA_BASE(CHA_BASE), .CHA_END(CHA_END)) loader (
        .clk(clk), .init(init),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(l_wait),
        .m_req(l_req), .m_addr(l_addr), .m_wdata(l_wdata), .m_ack(l_ack),
        .from_we(from_we), .from_addr(from_addr), .from_data(from_data),
        .rom_ready(rom_ready), .loading(), .stream_bytes()
    );
    assign ioctl_wait = l_wait;

    // DIP switches: MRA <switches>, ioctl index 254, byte 0 = DSW1, byte 1 = DSW2 (MAME values)
    logic [7:0] dsw1 = 8'hFF, dsw2 = 8'hDF;
    always_ff @(posedge clk) begin
        if (ioctl_download && ioctl_wr && ioctl_index == 16'd254 && ioctl_addr[26:1] == 0) begin
            dsw1 <= ioctl_dout[7:0];
            dsw2 <= ioctl_dout[15:8];
        end
    end

    wire sys_reset = reset || !rom_ready;

    // ------------------------------------------------------------------ SDRAM arbiter
    localparam int NC = 5;
    logic [NC-1:0]       a_req, a_we, a_ack;
    logic [NC-1:0][24:0] a_addr;
    logic [NC-1:0][15:0] a_wdata;
    logic [NC-1:0][1:0]  a_be;
    logic [63:0]         a_rdata;

    logic        cm_req, cm_we, dm_req, dm_we, sm_req, rm_req;
    logic [24:0] cm_addr, dm_addr, sm_addr, rm_addr;
    logic [15:0] cm_wdata, dm_wdata;
    logic  [1:0] cm_be, dm_be;

    assign a_req   = {rm_req, sm_req, dm_req, cm_req, l_req};
    assign a_we    = {1'b0, 1'b0, dm_we, cm_we, 1'b1};
    assign a_addr  = {rm_addr, sm_addr, dm_addr, cm_addr, l_addr};
    assign a_wdata = {16'h0, 16'h0, dm_wdata, cm_wdata, l_wdata};
    assign a_be    = {2'b11, 2'b11, dm_be, cm_be, 2'b11};
    assign l_ack   = a_ack[0];

    nrc_sdram_arb #(.N(NC)) arb (
        .clk(clk), .rst(init), .req(a_req), .we(a_we), .addr(a_addr), .wdata(a_wdata), .be(a_be),
        .ack(a_ack), .rdata(a_rdata), .owner(), .busy(),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready)
    );

    // ------------------------------------------------------------------ framebuffer control
    logic front = 1'b0, frame_ready = 1'b0, have_frame = 1'b0;
    logic render_busy, render_go, render_done;
    // Buffer the palette snapshot / next render go to: the back buffer after this event's swap.
    wire  new_front = frame_ready ? !front : front;
    wire  snap_ok   = vblank_start && !render_busy;
    always_ff @(posedge clk) begin
        if (sys_reset) begin
            front <= 1'b0; frame_ready <= 1'b0; have_frame <= 1'b0; dbg_frames <= '0;
        end else begin
            if (vblank_start && frame_ready) begin
                front <= !front; frame_ready <= 1'b0; have_frame <= 1'b1;
                dbg_frames <= dbg_frames + 16'd1;
            end
            if (render_done) frame_ready <= 1'b1;
        end
    end

    // ------------------------------------------------------------------ ST-0016 CPU side
    logic [12:0] spr_raddr;
    logic [63:0] spr_rdata;
    logic  [7:0] scroll_snap [32];
    logic  [7:0] tm_base_snap [8];
    logic  [7:0] tm_prio_snap, tm_merge_snap;
    logic [16:0] d_addr;
    logic [10:0] d_pen;
    logic [23:0] d_rgb;

    nrc_st0016 #(.CHA_BASE(CHA_BASE)) st0016 (
        .clk(clk), .reset(sys_reset), .ce_cpu(ce_cpu), .ce_pix(ce_pix), .ce_snd(ce_snd),
        .cpu_stall(cpu_stall),
        .from_we(from_we), .from_addr(from_addr), .from_data(from_data),
        .cm_req(cm_req), .cm_we(cm_we), .cm_addr(cm_addr), .cm_wdata(cm_wdata), .cm_be(cm_be), .cm_ack(a_ack[1]),
        .dm_req(dm_req), .dm_we(dm_we), .dm_addr(dm_addr), .dm_wdata(dm_wdata), .dm_be(dm_be), .dm_ack(a_ack[2]),
        .sm_req(sm_req), .sm_addr(sm_addr), .sm_ack(a_ack[3]),
        .m_rdata(a_rdata),
        .irq_event(vblank_start), .pal_snap(snap_ok), .render_go(render_go), .render_done(render_done),
        .spr_raddr(spr_raddr), .spr_rdata(spr_rdata), .scroll_snap(scroll_snap),
        .tm_base_snap(tm_base_snap), .tm_prio_snap(tm_prio_snap), .tm_merge_snap(tm_merge_snap),
        .pal_snap_buf(!new_front), .disp_buf(front), .disp_pen(d_pen), .disp_rgb(d_rgb),
        .joy0(joy0), .joy1(joy1), .dsw1(dsw1), .dsw2(dsw2),
        .snd_l(snd_l), .snd_r(snd_r),
        .dbg_pc(dbg_pc), .dbg_irqs(dbg_irqs), .dbg_nmis(dbg_nmis),
        .dbg_snap_drops(dbg_snap_drops), .dbg_dma_count()
    );

    // ------------------------------------------------------------------ renderer + framebuffers
    logic [16:0] fb_raddr, fb_waddr;
    logic [10:0] fb_rdata, fb_wdata;
    logic        fb_we;
    logic [23:0] r_cycles;
    nrc_render #(.CHA_BASE(CHA_BASE)) render (
        .clk(clk), .reset(sys_reset), .go(render_go), .done(render_done), .busy(render_busy),
        .scroll(scroll_snap),
        .tm_base(tm_base_snap), .tm_prio(tm_prio_snap), .tm_merge(tm_merge_snap), .spr_addr(spr_raddr), .spr_data(spr_rdata),
        .m_req(rm_req), .m_addr(rm_addr), .m_ack(a_ack[4]), .m_rdata(a_rdata),
        .fb_raddr(fb_raddr), .fb_rdata(fb_rdata), .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata),
        .st_tiles(), .st_fetched(), .st_cycles(r_cycles)
    );
    assign dbg_render_ms100 = {6'd0, r_cycles[19:10]};   // units of 1024 clk = 10.2 us (no divider)

    nrc_framebuffer fb (
        .clk(clk), .r_buf(!front), .r_addr(fb_raddr), .r_rdata(fb_rdata),
        .r_we(fb_we), .r_waddr(fb_waddr), .r_wdata(fb_wdata),
        .d_addr(d_addr), .d_data(d_pen)
    );

    // ------------------------------------------------------------------ display pipeline
    // x/y change on ce_pix; the pen address is ready 2 cycles later, framebuffer + palette deliver
    // RGB 4 cycles after that, well inside the 14-cycle dot. The output stage registers RGB and
    // the timing signals of the same dot together at the next ce_pix (one dot of delay for all).
    logic [23:0] ov_rgb;
    nrc_overlay overlay (
        .clk(clk), .ce_pix(ce_pix), .enable(dbg_overlay), .frame_start(frame_start),
        .x(vx), .y(vy), .rgb_in(have_frame ? d_rgb : 24'h000000), .rgb_out(ov_rgb),
        .rom_ready(rom_ready), .pc(dbg_pc), .frames(dbg_frames), .irqs(dbg_irqs), .nmis(dbg_nmis),
        .render_t(dbg_render_ms100), .drops(dbg_snap_drops)
    );

    logic [16:0] row_base;
    always_ff @(posedge clk) begin
        row_base <= 17'(vy) * 17'd320;          // two register stages: 14 clk per dot
        d_addr   <= row_base + 17'(vx);
        if (ce_pix) begin
            hblank <= t_hb;
            vblank <= t_vb;
            hsync  <= t_hs;
            vsync  <= t_vs;
            rgb    <= (t_hb || t_vb) ? 24'h000000 : ov_rgb;
        end
    end
endmodule
