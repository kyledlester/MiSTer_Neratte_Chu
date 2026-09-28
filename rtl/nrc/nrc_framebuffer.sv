// Neratte Chu (Seta ST-0016) MiSTer core -- double framebuffer.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Two 320 x 240 x 11-bit buffers (pen 0..1023, bit 10 = MAME UNUSED_PEN). Address = y*320 + x
// (ST-0016 bitmap x - 8, y). The renderer owns buffer r_buf (write port + read port), the display
// reads the other one. Because a buffer is never renderer-owned and displayed at the same time,
// each buffer needs only one write port and one read port whose address is muxed between the
// renderer and the display: a simple dual-port M10K array (no RAM duplication).
// Requires d_buf == !r_buf (nrc_core guarantees it).
module nrc_framebuffer (
    input  logic        clk,
    // renderer port (buffer r_buf): read data valid the cycle after r_addr
    input  logic        r_buf,
    input  logic [16:0] r_addr,
    output logic [10:0] r_rdata,
    input  logic        r_we,
    input  logic [16:0] r_waddr,
    input  logic [10:0] r_wdata,
    // display port (buffer !r_buf): data valid the cycle after d_addr
    input  logic [16:0] d_addr,
    output logic [10:0] d_data
);
    logic [10:0] fb0 [76800];
    logic [10:0] fb1 [76800];
    logic [10:0] q0, q1;
    logic        sel;

    wire [16:0] a0 = r_buf ? d_addr : r_addr;   // buffer 0 read address
    wire [16:0] a1 = r_buf ? r_addr : d_addr;   // buffer 1 read address

    always_ff @(posedge clk) begin
        if (r_we && !r_buf) fb0[r_waddr] <= r_wdata;
        q0 <= fb0[a0];
    end
    always_ff @(posedge clk) begin
        if (r_we && r_buf) fb1[r_waddr] <= r_wdata;
        q1 <= fb1[a1];
    end
    always_ff @(posedge clk) sel <= r_buf;

    assign r_rdata = sel ? q1 : q0;
    assign d_data  = sel ? q0 : q1;
endmodule
