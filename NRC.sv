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
// M0: PLL (clk_sys 100.227 MHz), clock enables, raster 455x262 (320x240 active),
// test pattern through arcade_video. See docs/MILESTONES.md.

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;
assign AUDIO_L   = 16'd0;
assign AUDIO_R   = 16'd0;
assign AUDIO_MIX = 2'd0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = 0;
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
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire  [21:0] gamma_bus;
wire   [1:0] buttons;
wire [127:0] status;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0)
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

reg [2:0] rst_sync = 3'b111;
always @(posedge clk_sys) rst_sync <= {rst_sync[1:0], RESET | status[0] | buttons[1] | ~pll_locked};
wire reset = rst_sync[2];

wire ce_pix, tick8, ce_snd, ce_cpu;
nrc_clocks clocks
(
	.clk(clk_sys),
	.rst(reset),
	.cpu_stall(1'b0),
	.ce_pix(ce_pix),
	.tick8(tick8),
	.ce_snd(ce_snd),
	.ce_cpu(ce_cpu),
	.credits(),
	.lost_credits()
);

///////////////////////   VIDEO   ////////////////////////////////

wire [8:0] hcnt, vcnt, vx;
wire [7:0] vy;
wire hblank, vblank, hsync, vsync, vblank_start, frame_start;

nrc_video_timing timing
(
	.clk(clk_sys),
	.rst(reset),
	.ce_pix(ce_pix),
	.hcnt(hcnt),
	.vcnt(vcnt),
	.x(vx),
	.y(vy),
	.hblank(hblank),
	.vblank(vblank),
	.hsync(hsync),
	.vsync(vsync),
	.vblank_start(vblank_start),
	.frame_start(frame_start)
);

// M0 test pattern: 8 colour bars, a 1-pixel white border and a moving bar.
reg [7:0] frame_cnt;
always @(posedge clk_sys) if (frame_start) frame_cnt <= frame_cnt + 8'd1;

wire border = (vx == 0) || (vx == 319) || (vy == 0) || (vy == 239);
wire [2:0] bar = vx[8:6] + (vx >= 9'd320 ? 3'd0 : 3'd0);
wire movebar = (vy[7:3] == frame_cnt[7:3]);
wire [23:0] rgb = border ? 24'hFFFFFF :
                  movebar ? 24'h808080 :
                  {{8{bar[2]}}, {8{bar[1]}}, {8{bar[0]}}};

arcade_video #(.WIDTH(320), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(ce_pix),
	.RGB_in(rgb),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hsync),
	.VSync(vsync),
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
