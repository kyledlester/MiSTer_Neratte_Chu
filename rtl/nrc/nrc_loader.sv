// Neratte Chu (Seta ST-0016) MiSTer core -- ROM stream loader.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// ioctl index 0 (hps_io WIDE=1): the MRA delivers the ST-0016 external ROM image in MAME region
// order, stream offset == extrom byte address (MRA: sx012-01 @0, 512 KiB zero pad, sx012-02
// @100000). Bytes 2k / 2k+1 arrive as ioctl_dout[7:0] / [15:8] with ioctl_addr = 2k; they are
// stored unchanged (SDRAM word {byte 2k+1, byte 2k}, see nrc_sdram_arb).
//
// Stream bytes below 0x8000 are also written into the fixed-ROM BRAM (the CPU's 0000-7FFF window,
// fixedrom_offset = 0 for nratechu).
//
// After the download finishes the loader zero-fills
//   - extrom from the end of the stream up to 0x3FFFFF (MAME ROMREGION_ERASE00: U33/U34 unpopulated),
//   - character RAM (SDRAM 0x800000-0x9FFFFF; MAME starts it zeroed),
// then raises rom_ready. The system is held in reset while !rom_ready.
//
// Flow control: one word buffered, ioctl_wait high from ioctl_wr until the SDRAM write is acked.
module nrc_loader #(
    parameter logic [15:0] INDEX      = 16'd0,
    parameter logic [24:0] EXTROM_END = 25'h0400000,
    parameter logic [24:0] CHA_BASE   = 25'h0800000,
    parameter logic [24:0] CHA_END    = 25'h0A00000
) (
    input  logic        clk,
    input  logic        init,           // PLL loss of lock
    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    output logic        ioctl_wait,
    // SDRAM client (write only)
    output logic        m_req,
    output logic [24:0] m_addr,
    output logic [15:0] m_wdata,
    input  logic        m_ack,
    // fixed ROM BRAM write port (16-bit words, word address = byte address >> 1)
    output logic        from_we,
    output logic [13:0] from_addr,
    output logic [15:0] from_data,
    output logic        rom_ready,
    output logic        loading,
    output logic [24:0] stream_bytes
);
    typedef enum logic [1:0] {S_IDLE, S_LOAD, S_FILL_ROM, S_FILL_CHA} state_t;
    state_t st = S_IDLE;

    wire selected = ioctl_download && (ioctl_index == INDEX);
    wire wr_now   = selected && ioctl_wr;
    logic pending = 1'b0;
    logic [24:0] fill_addr;

    // A download that starts during the zero-fill waits until the fill's current write completes.
    wire fill_busy = (st == S_FILL_ROM) || (st == S_FILL_CHA);
    assign ioctl_wait = pending || wr_now || (selected && fill_busy);
    assign loading    = (st != S_IDLE);

    always_ff @(posedge clk) begin
        from_we <= 1'b0;
        if (init) begin
            st <= S_IDLE; pending <= 1'b0; m_req <= 1'b0;
            rom_ready <= 1'b0; stream_bytes <= '0;
        end else begin
            case (st)
                S_IDLE: if (selected) begin
                    st <= S_LOAD; rom_ready <= 1'b0; stream_bytes <= '0;
                end
                S_LOAD: begin
                    if (wr_now && !pending) begin
                        pending <= 1'b1;
                        m_req   <= 1'b1;
                        m_addr  <= ioctl_addr[24:0];
                        m_wdata <= ioctl_dout;
                        if (ioctl_addr[24:0] + 25'd2 > stream_bytes) stream_bytes <= ioctl_addr[24:0] + 25'd2;
                        if (ioctl_addr[26:15] == 0) begin
                            from_we   <= 1'b1;
                            from_addr <= ioctl_addr[14:1];
                            from_data <= ioctl_dout;
                        end
                    end
                    if (m_ack) begin m_req <= 1'b0; pending <= 1'b0; end
                    if (!selected && !pending && !m_req) begin
                        st <= S_FILL_ROM;
                        fill_addr <= {stream_bytes[24:1], 1'b0};
                    end
                end
                S_FILL_ROM, S_FILL_CHA: begin
                    if (selected && (!m_req || m_ack)) begin
                        m_req <= 1'b0;
                        st <= S_LOAD; rom_ready <= 1'b0; stream_bytes <= '0;
                    end else if (!m_req) begin
                        if (st == S_FILL_ROM && fill_addr >= EXTROM_END) begin
                            st <= S_FILL_CHA; fill_addr <= CHA_BASE;
                        end else if (st == S_FILL_CHA && fill_addr >= CHA_END) begin
                            st <= S_IDLE; rom_ready <= 1'b1;
                        end else begin
                            m_req <= 1'b1; m_addr <= fill_addr; m_wdata <= 16'h0000;
                        end
                    end else if (m_ack) begin
                        m_req <= 1'b0;
                        fill_addr <= fill_addr + 25'd2;
                    end
                end
            endcase
        end
    end
endmodule
