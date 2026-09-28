// Neratte Chu (Seta ST-0016) MiSTer core -- interrupt scheduler.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// MAME simple_st0016.cpp st0016_state::interrupt (384-line fictitious screen, 60 Hz):
//   line 240           : IRQ0, HOLD_LINE (asserted until the CPU acknowledges it)
//   lines 0,64,..,320  : NMI pulse, but only if IFF1 = 1 at that moment ("dirty hack" in MAME; the
//                        real NMI source is unknown - the game's NMI handler is the sound sequencer tick)
//
// FPGA mapping [APPROXIMATION, MAME-compatible, all constants here]:
//   IRQ at `irq_event` = start of vblank (line 256 of the 262-line raster) - the frame render instant.
//   NMI k (k = 0..5) at IRQ + (16 + 64k) / 384 of a frame, i.e. MAME lines 256, 320, 0, 64, 128, 192
//   keep their phase relative to the IRQ. Offsets are in dot clocks of the 455 x 262 raster.
//   NMI gating samples the T80's IFF1 at the event. nmi_n is held low for NMI_HOLD CPU clocks so the
//   T80 samples the falling edge.
module nrc_irq #(
    parameter int FRAME_DOTS = 455 * 262,
    parameter int NMI_HOLD   = 4
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       ce_pix,
    input  logic       ce_cpu,
    input  logic       irq_event,     // vblank start pulse
    input  logic       int_ack,       // CPU interrupt acknowledge cycle (level; edge-detected here)
    input  logic       iff1,
    output logic       int_n,
    output logic       nmi_n,
    output logic [15:0] irq_count,
    output logic [15:0] nmi_count,
    output logic [15:0] nmi_skipped
);
    function automatic int nmi_off(int k);
        return ((16 + 64 * k) * FRAME_DOTS) / 384;
    endfunction
    localparam int OFF0 = nmi_off(0), OFF1 = nmi_off(1), OFF2 = nmi_off(2);
    localparam int OFF3 = nmi_off(3), OFF4 = nmi_off(4), OFF5 = nmi_off(5);

    logic [16:0] dots;
    logic        running;
    logic        ack_q;
    logic [3:0]  hold;

    always_ff @(posedge clk) begin
        if (reset) begin
            int_n <= 1'b1; nmi_n <= 1'b1; dots <= '0; running <= 1'b0; ack_q <= 1'b0; hold <= '0;
            irq_count <= '0; nmi_count <= '0; nmi_skipped <= '0;
        end else begin
            ack_q <= int_ack;
            if (int_ack && !ack_q) int_n <= 1'b1;
            if (irq_event) begin
                int_n <= 1'b0;
                irq_count <= irq_count + 16'd1;
                dots <= '0;
                running <= 1'b1;
            end else if (ce_pix && running) begin
                dots <= dots + 17'd1;
                if (dots == OFF0 || dots == OFF1 || dots == OFF2 ||
                    dots == OFF3 || dots == OFF4 || dots == OFF5) begin
                    if (iff1) begin
                        nmi_n <= 1'b0;
                        hold  <= 4'(NMI_HOLD);
                        nmi_count <= nmi_count + 16'd1;
                    end else begin
                        nmi_skipped <= nmi_skipped + 16'd1;
                    end
                end
            end
            if (!nmi_n && ce_cpu) begin
                if (hold <= 4'd1) nmi_n <= 1'b1;
                else hold <= hold - 4'd1;
            end
        end
    end
endmodule
