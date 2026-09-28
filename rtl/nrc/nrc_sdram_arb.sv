// Neratte Chu (Seta ST-0016) MiSTer core -- SDRAM client arbiter.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Front end of rtl/vendor/sdram.sv channel 1 (burst 4 x 16 bit reads, single 16-bit writes with
// byte enables). N clients, fixed priority (index 0 highest), one transaction in flight.
//
// Client contract (per client i):
//   req[i]    level; hold it (with addr/we/wdata/be stable) until ack[i].
//   addr[i]   byte address (25 bit). Reads: the aligned 8-byte group addr & ~7 is returned in
//             rdata (byte k of the group at rdata[8k+7:8k], little-endian). Writes: the 16-bit word
//             addr & ~1 with byte enables be ([0] = even byte = wdata[7:0], [1] = odd = wdata[15:8]).
//   ack[i]    one-cycle pulse; rdata valid in the same cycle (and held until the next read completes).
//             A client is never granted in its own ack cycle, so it may drop req one cycle later.
// sdram.sv raises ch1_ready one cycle before the last burst word lands in ch1_dout, so the arbiter
// captures ch1_dout one cycle after ch1_ready.
// Memory image byte order: SDRAM word at byte address 2k holds {byte 2k+1, byte 2k}.
module nrc_sdram_arb #(
    parameter int N = 5
) (
    input  logic              clk,
    input  logic              rst,
    input  logic [N-1:0]      req,
    input  logic [N-1:0]      we,
    input  logic [N-1:0][24:0] addr,
    input  logic [N-1:0][15:0] wdata,
    input  logic [N-1:0][1:0] be,
    output logic [N-1:0]      ack,
    output logic [63:0]       rdata,
    output logic [$clog2(N > 1 ? N : 2)-1:0] owner,   // client of the current / last transaction
    output logic              busy,
    // sdram.sv channel 1
    output logic [26:1]       sd_addr,
    output logic [15:0]       sd_din,
    output logic [1:0]        sd_be,
    output logic              sd_req,
    output logic              sd_rnw,
    input  logic [63:0]       sd_dout,
    input  logic              sd_ready
);
    logic done;
    always_ff @(posedge clk) begin
        ack    <= '0;
        sd_req <= 1'b0;
        done   <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
            owner <= '0;
        end else if (done) begin
            busy <= 1'b0;
            ack[owner] <= 1'b1;
            rdata <= sd_dout;
        end else if (!busy) begin
            for (int i = N - 1; i >= 0; i--) begin
                if (req[i] && !ack[i]) begin
                    owner   <= i[$bits(owner)-1:0];
                    busy    <= 1'b1;
                    sd_req  <= 1'b1;
                    sd_rnw  <= !we[i];
                    sd_addr <= we[i] ? {1'b0, addr[i][24:1]} : {1'b0, addr[i][24:3], 2'b00};
                    sd_din  <= wdata[i];
                    sd_be   <= be[i];
                end
            end
        end else if (sd_ready) begin
            done <= 1'b1;
        end
    end
endmodule
