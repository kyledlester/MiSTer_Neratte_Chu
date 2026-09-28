// Neratte Chu (Seta ST-0016) MiSTer core -- player inputs and DIP multiplexer.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// MAME simple_st0016.cpp, INPUT_PORTS_START(st0016) + (nratechu). All inputs active low.
//   P1 / P2 (ports C0 / C1, C3): b0 up, b1 down, b2 left, b3 right, b4 B1, b5 B2, b6 B3, b7 START
//   SYSTEM: b0 COIN1, b1 COIN2, b2 SERVICE1, b3 unused (nratechu)
//   port C2 (mux_r): SYSTEM[3:0] | 4 DIP bits selected by the last C0 write, bits 5-4.
// MiSTer joystick bit order (CONF_STR "J1"): 0 right, 1 left, 2 down, 3 up, 4 B1, 5 B2, 6 B3,
// 7 Start, 8 Coin, 9 Service.
module nrc_inputs (
    input  logic [31:0] joy0,
    input  logic [31:0] joy1,
    input  logic  [7:0] dsw1,      // active-low DIP bytes as MAME defines them
    input  logic  [7:0] dsw2,
    input  logic  [7:0] mux,       // last value written to port C0
    output logic  [7:0] p1,
    output logic  [7:0] p2,
    output logic  [7:0] mux_out
);
    function automatic logic [7:0] player(input logic [31:0] j);
        return ~{j[7], j[6], j[5], j[4], j[0], j[1], j[2], j[3]};
    endfunction
    assign p1 = player(joy0);
    assign p2 = player(joy1);

    wire [3:0] system = ~{1'b0, joy0[9] | joy1[9], joy1[8], joy0[8]};

    always_comb begin
        logic [3:0] d;
        case (mux[5:4])
            2'd0: d = {dsw2[4], dsw2[0], dsw1[4], dsw1[0]};
            2'd1: d = {dsw2[5], dsw2[1], dsw1[5], dsw1[1]};
            2'd2: d = {dsw2[6], dsw2[2], dsw1[6], dsw1[2]};
            default: d = {dsw2[7], dsw2[3], dsw1[7], dsw1[3]};
        endcase
        mux_out = {d, system};
    end
endmodule
