// Neratte Chu (Seta ST-0016) MiSTer core -- Z80 core wrapper.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Instantiates the T80 kernel (rtl/vendor/t80, Daniel Wallner / MikeJ / Sorgelig, v351) directly
// and regenerates the bus strobes exactly as T80s.vhd does (Mode 0, T2Write = 1, IOWait = 1), so the
// external behaviour is that of T80s. The wrapper exists to expose IntE (IFF1, needed for MAME's
// IFF1-gated NMI) and the register file (PC/SP for diagnostics), which T80s does not export.
//
// Bus contract for the ST-0016 glue (nrc_st0016):
//   - every signal changes only on a cen edge;
//   - rd_n / wr_n are low for (at least) one cen period per memory or I/O access; mreq_n / iorq_n
//     tell which space; m1_n marks opcode fetches; interrupt acknowledge = !m1_n && !iorq_n;
//   - di is sampled on the cen edge that ends T2 (and DInst for opcode fetches in T3) - the glue
//     stalls cen until di is valid, so di only has to be valid while no cen is issued.
module nrc_cpu (
    input  logic        clk,
    input  logic        reset,       // synchronous to clk, active high
    input  logic        cen,
    input  logic        int_n,
    input  logic        nmi_n,
    input  logic  [7:0] di,
    output logic  [7:0] dout,
    output logic [15:0] a,
    output logic        m1_n,
    output logic        mreq_n,
    output logic        iorq_n,
    output logic        rd_n,
    output logic        wr_n,
    output logic        rfsh_n,
    output logic        halt_n,
    output logic        iff1,
    output logic [15:0] pc,
    output logic [15:0] sp
);
    logic        noread, write, iorq, intcycle_n, inte;
    logic  [2:0] mcycle, tstate;
    logic  [7:0] di_reg;
    logic [211:0] regs;
    wire  [211:0] dir_zero = '0;

    T80 #(
        .Mode(0),
        .IOWait(1)
    ) u0 (
        .RESET_n   (!reset),
        .CLK_n     (clk),
        .CEN       (cen),
        .WAIT_n    (1'b1),
        .INT_n     (int_n),
        .NMI_n     (nmi_n),
        .BUSRQ_n   (1'b1),
        .M1_n      (m1_n),
        .IORQ      (iorq),
        .NoRead    (noread),
        .Write     (write),
        .RFSH_n    (rfsh_n),
        .HALT_n    (halt_n),
        .BUSAK_n   (),
        .A         (a),
        .DInst     (di),
        .DI        (di_reg),
        .DO        (dout),
        .MC        (mcycle),
        .TS        (tstate),
        .IntCycle_n(intcycle_n),
        .IntE      (inte),
        .Stop      (),
        .R800_mode (1'b0),
        .out0      (1'b0),
        .REG       (regs),
        .DIRSet    (1'b0),
        .DIR       (dir_zero)
    );

    assign iff1 = inte;
    assign pc   = regs[79:64];
    assign sp   = regs[63:48];

    // T80s.vhd strobe process, Mode 0, T2Write /= 0, WAIT_n = 1.
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rd_n <= 1'b1; wr_n <= 1'b1; iorq_n <= 1'b1; mreq_n <= 1'b1;
            di_reg <= 8'h00;
        end else if (cen) begin
            rd_n <= 1'b1; wr_n <= 1'b1; iorq_n <= 1'b1; mreq_n <= 1'b1;
            if (mcycle == 3'd1) begin
                if (tstate == 3'd1) begin
                    rd_n   <= !intcycle_n;
                    mreq_n <= !intcycle_n;
                    iorq_n <= intcycle_n;
                end
                if (tstate == 3'd3) mreq_n <= 1'b0;
            end else begin
                if (tstate == 3'd1 && !noread && !write) begin
                    rd_n   <= 1'b0;
                    iorq_n <= !iorq;
                    mreq_n <= iorq;
                end
                if (tstate == 3'd1 && write) begin
                    wr_n   <= 1'b0;
                    iorq_n <= !iorq;
                    mreq_n <= iorq;
                end
            end
            if (tstate == 3'd2) di_reg <= di;
        end
    end
endmodule
