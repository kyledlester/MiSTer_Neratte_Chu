//============================================================================
//
//  Neratte Chu (Seta ST-0016) MiSTer core -- top level (emu).
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation, either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  Structure follows MiSTer-devel/Template_MiSTer (GPL-2.0+).
//
//============================================================================
//
// M0: PLL (clk_sys 100.227 MHz), clock enables, raster 455x262 (320x240 active).
// M2-M13: nrc_core = ROM loader + SDRAM arbiter + ST-0016 (T80, bus, sprite RAM, palette, IRQ/NMI,
// DMA) + sprite frame renderer + double framebuffer. See docs/ARCHITECTURE.md, docs/MILESTONES.md.

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = status[10:9];

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS   = 0;

// 320x240 on a 4:3 display.
wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"NeratteChu;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[12:11],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"O[10:9],Stereo mix,None,25%,50%,100%;",
	"-;",
	"DIP;",
	"-;",
	"P1,CRT Adjust;",
	"P1O[96],CRT Adjust,Off,On;",
	"H1P1O[116:112],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[104:101],CRT H-Position,0,+6,+12,+18,+24,+30,+36,+42,-48,-42,-36,-30,-24,-18,-12,-6;",
	"H1P1O[108:105],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P2,Pause options;",
	"P2O[13],Pause when OSD is open,Off,On;",
	"P2O[14],Dim video after 10s,On,Off;",
	"-;",
	"O[2],Debug overlay,Off,On;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,Button 1,Button 2,Button 3,Start,Coin,Service,Pause;",
	"jn,A,B,X,Start,Select,R,L;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire  [21:0] gamma_bus;
wire   [1:0] buttons;
wire [127:0] status;
wire  [31:0] joystick_0, joystick_1;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wait;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask({14'd0, ~status[96], 1'b0}),   // H1 = CRT Adjust amounts, hidden while Off
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);

///////////////////////   CLOCKS / RESET   ///////////////////////

wire clk_sys;
wire pll_locked;

nrc_pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.clk_sys(clk_sys),
	.locked(pll_locked)
);

// Memory system (SDRAM controller, loader, arbiter) resets only on PLL loss of lock; the game
// hardware is also held during downloads and by OSD/user resets.
reg [2:0] init_sync = 3'b111;
always @(posedge clk_sys) init_sync <= {init_sync[1:0], ~pll_locked};
wire init = init_sync[2];

reg [2:0] rst_sync = 3'b111;
always @(posedge clk_sys) rst_sync <= {rst_sync[1:0], RESET | status[0] | buttons[1] | ioctl_download | ~pll_locked};
wire reset = rst_sync[2];

///////////////////////   CORE   /////////////////////////////////

wire [26:1] sd_addr;
wire [15:0] sd_din;
wire  [1:0] sd_be;
wire        sd_req, sd_rnw, sd_ready;
wire [63:0] sd_dout;

wire        ce_pix;
wire [23:0] rgb;
wire        hblank, vblank, hsync, vsync, vb_next;
wire signed [15:0] snd_l, snd_r;
wire        rom_ready;

nrc_core core
(
	.clk(clk_sys),
	.init(init),
	.reset(reset),
	.sim_turbo(1'b0),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.sd_addr(sd_addr),
	.sd_din(sd_din),
	.sd_be(sd_be),
	.sd_req(sd_req),
	.sd_rnw(sd_rnw),
	.sd_dout(sd_dout),
	.sd_ready(sd_ready),
	.joy0(joystick_0),
	.joy1(joystick_1),
	.dbg_overlay(status[2]),
	.pause(pause_cpu),
	.ce_pix(ce_pix),
	.rgb(rgb),
	.hblank(hblank),
	.vblank(vblank),
	.hsync(hsync),
	.vsync(vsync),
	.vb_next(vb_next),
	.snd_l(snd_l),
	.snd_r(snd_r),
	.rom_ready(rom_ready),
	.dbg_pc(),
	.dbg_frames(),
	.dbg_render_ms100(),
	.dbg_snap_drops(),
	.dbg_irqs(),
	.dbg_nmis()
);

assign AUDIO_L = snd_l;
assign AUDIO_R = snd_r;

sdram #(.CYCLES_PER_REFRESH(14'd780)) sdram
(
	.init(init),
	.clk(clk_sys),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_CLK(SDRAM_CLK),
	.ch1_addr(sd_addr),
	.ch1_dout(sd_dout),
	.ch1_din(sd_din),
	.ch1_be(sd_be),
	.ch1_req(sd_req),
	.ch1_rnw(sd_rnw),
	.ch1_ready(sd_ready),
	.ch2_addr(26'd0),
	.ch2_dout(),
	.ch2_din(32'd0),
	.ch2_req(1'b0),
	.ch2_rnw(1'b1),
	.ch2_ready(),
	.ch3_addr(24'd0),
	.ch3_dout(),
	.ch3_din(16'd0),
	.ch3_req(1'b0),
	.ch3_rnw(1'b1),
	.ch3_ready()
);

///////////////////////   PAUSE   ////////////////////////////////
// JimmyStones' generic MiSTer pause (rtl/vendor/pause.v, GPL-3.0+): Pause button (either player,
// joystick bit 10) toggles, optionally the open OSD pauses; the RGB is halved after 10 s of pause
// (burn-in protection, OSD option). nrc_core freezes the CPU time base, interrupts, renders and sound.
wire        pause_cpu;
wire [23:0] rgb_p;
pause #(.RW(8), .GW(8), .BW(8), .CLKSPD(100)) pause
(
	.clk_sys(clk_sys),
	.reset(reset),
	.user_button(joystick_0[10] | joystick_1[10]),
	.pause_request(1'b0),
	.options({~status[14], status[13]}),
	.OSD_STATUS(OSD_STATUS),
	.r(rgb[23:16]),
	.g(rgb[15:8]),
	.b(rgb[7:0]),
	.pause_cpu(pause_cpu),
	.rgb_out(rgb_p)
);

///////////////////////   VIDEO   ////////////////////////////////

// CRT Adjust (analog geometry, OSD submenu; rtl/nrc/nrc_crt_adjust.sv): a port of the owner's
// NA-1/NA-2 integration around the unmodified upstream crt_adjust.sv. Off = true bypass.
reg  vsync_d = 1'b0;
always @(posedge clk_sys) vsync_d <= vsync;
wire frame_event = vsync && !vsync_d;          // once per frame, inside vertical blanking
wire        av_ce, av_hb, av_vb, av_hs, av_vs;
wire [23:0] av_rgb;
nrc_crt_adjust crt_adjust
(
	.clk_sys(clk_sys),
	.ce_pix(ce_pix),
	.frame_event(frame_event),
	.osd_on(status[96]),
	.osd_hsize(status[116:112]),
	.osd_hpos(status[104:101]),
	.osd_vshift(status[108:105]),
	.sd_off((status[12:11] == 2'd0) && !forced_scandoubler),
	.rgb_in(rgb_p),
	.hblank_in(hblank),
	.vblank_in(vblank),
	.hsync_in(hsync),
	.vsync_in(vsync),
	.vb_next_in(vb_next),
	.ce_out(av_ce),
	.rgb_out(av_rgb),
	.hblank_out(av_hb),
	.vblank_out(av_vb),
	.hsync_out(av_hs),
	.vsync_out(av_vs),
	.active()
);

arcade_video #(.WIDTH(320), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(av_ce),
	.RGB_in(av_rgb),
	.HBlank(av_hb),
	.VBlank(av_vb),
	.HSync(av_hs),
	.VSync(av_vs),
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),
	.fx({1'b0, status[12:11]}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

endmodule
