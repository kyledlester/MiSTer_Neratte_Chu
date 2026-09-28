// Neratte Chu (Seta ST-0016) MiSTer core -- sprite RAM with render snapshot.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// 64 KiB sprite RAM (PCB: 2 x 62256) held twice in BRAM:
//   live   : 64K x 8, the CPU's view (windows C000/D000 through the E2 bank register).
//   render : 8K x 64 (8 byte lanes), read by the renderer one 8-byte entry per clock.
// Every CPU write updates `live` at once and is queued in a FIFO; queued writes are applied to
// `render` (one per clock) only while no render is in progress.
//
// Snapshot protocol (docs/ARCHITECTURE.md "Video architecture"):
//   snap        pulse at the MAME render instant (vblank IRQ). The FIFO fill level is marked.
//   render_go   pulse once every write older than the mark has reached `render`. From then until
//               render_done, `render` is frozen: it equals `live` at the snap instant (MAME semantics).
//   render_done pulse from the renderer; queued (newer) writes then drain.
// A snap while a render is still active or pending is dropped and counted (snap_drops).
// If the FIFO is full the CPU is stalled (cpu_stall) until it drains - never a lost write.
module nrc_spriteram #(
    parameter int FIFO_LOG2 = 10
) (
    input  logic        clk,
    input  logic        reset,
    // CPU port (registered read, data valid the cycle after cpu_rd)
    input  logic [15:0] cpu_addr,
    input  logic        cpu_we,          // one-cycle write strobe
    input  logic  [7:0] cpu_wdata,
    output logic  [7:0] cpu_rdata,
    output logic        cpu_stall,       // FIFO full: hold the write
    // snapshot / renderer
    input  logic        snap,
    output logic        render_go,
    input  logic        render_done,
    output logic        render_active,
    input  logic [12:0] r_addr,
    output logic [63:0] r_data,
    output logic [15:0] snap_drops,
    output logic [FIFO_LOG2:0] fifo_max
);
    // ---- live copy ----
    logic [7:0] live [65536];
    always_ff @(posedge clk) begin
        if (cpu_we && !cpu_stall) live[cpu_addr] <= cpu_wdata;
        cpu_rdata <= live[cpu_addr];
    end

    // ---- write FIFO ----
    localparam int D = 1 << FIFO_LOG2;
    logic [23:0] fifo [D];
    logic [FIFO_LOG2:0] wp, rp, mark;
    wire  [FIFO_LOG2:0] level = wp - rp;
    assign cpu_stall = cpu_we && (level == D[FIFO_LOG2:0]);
    logic [23:0] fifo_q;
    logic        apply;

    // ---- render copy, 8 byte lanes ----
    logic [7:0] lane [8][8192];
    logic [15:0] ap;
    logic [7:0]  ad;
    always_ff @(posedge clk) begin
        for (int l = 0; l < 8; l++) begin
            if (apply && ap[2:0] == l[2:0]) lane[l][ap[15:3]] <= ad;
            r_data[8*l +: 8] <= lane[l][r_addr];
        end
    end

    logic snap_pending;
    logic issue, issue_q, issue_q_block;
    wire  may_drain = !render_active && !(snap_pending && rp == mark);
    // issue: advance the read pointer when there is something to drain; the entry read at rp is
    // registered into fifo_q on this edge and applied on the next (issue_q).
    assign issue = !reset && may_drain && (level != 0) && !issue_q_block;
    // fifo_q is loaded from fifo[rp] every cycle, so an issue must use the value registered
    // while rp still pointed at the entry: hold one bubble between issues.
    always_ff @(posedge clk) begin
        issue_q       <= issue;
        issue_q_block <= issue;
    end
    always_ff @(posedge clk) begin
        render_go <= 1'b0;
        apply     <= 1'b0;
        if (cpu_we && !cpu_stall) fifo[wp[FIFO_LOG2-1:0]] <= {cpu_addr, cpu_wdata};
        fifo_q <= fifo[rp[FIFO_LOG2-1:0]];
        if (reset) begin
            wp <= '0; rp <= '0; mark <= '0;
            snap_pending <= 1'b0; render_active <= 1'b0;
            snap_drops <= '0; fifo_max <= '0;
        end else begin
            if (cpu_we && !cpu_stall) wp <= wp + 1'd1;
            if (level > fifo_max) fifo_max <= level;
            // Drain: read fifo[rp] (registered), apply one cycle later.
            // A two-stage pipeline: stage 1 issues the read, stage 2 applies.
            if (issue_q) begin
                apply <= 1'b1;
                ap <= fifo_q[23:8];
                ad <= fifo_q[7:0];
            end
            if (snap) begin
                if (snap_pending || render_active) snap_drops <= snap_drops + 16'd1;
                else begin snap_pending <= 1'b1; mark <= wp; end
            end
            if (snap_pending && rp == mark && !issue_q && !render_active) begin
                snap_pending  <= 1'b0;
                render_active <= 1'b1;
                render_go     <= 1'b1;
            end
            if (render_done) render_active <= 1'b0;
            if (issue) rp <= rp + 1'd1;
        end
    end

endmodule
