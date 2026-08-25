`timescale 1ns/1ps

// Stateless decoder for the ready/valid 64-bit SRF command interface.
module sr_controller #(
    parameter COLUMN_ADDR_WIDTH     = 4,
    parameter SUPERLANE_ADDR_WIDTH  = 2,
    parameter STREAM_ADDR_WIDTH     = 5,
    parameter LANE_ADDR_WIDTH       = 3
) (
    input  wire                                cmd_valid,
    output wire                                cmd_ready,
    input  wire [63:0]                         cmd_data,
    output reg                                 write_en,
    output reg  [COLUMN_ADDR_WIDTH-1:0]        write_column,
    output reg  [SUPERLANE_ADDR_WIDTH-1:0]     write_superlane,
    output reg  [STREAM_ADDR_WIDTH-1:0]        write_stream,
    output reg  [LANE_ADDR_WIDTH-1:0]          write_lane,
    output reg  [7:0]                          write_data,
    output reg                                 read_en,
    output reg  [COLUMN_ADDR_WIDTH-1:0]        read_column,
    output reg  [SUPERLANE_ADDR_WIDTH-1:0]     read_superlane,
    output reg  [STREAM_ADDR_WIDTH-1:0]        read_stream,
    output reg  [LANE_ADDR_WIDTH-1:0]          read_lane
);

    localparam [7:0] OPCODE_WRITE = 8'h01;
    localparam [7:0] OPCODE_READ  = 8'h02;

    //  controller has no internal stall condition.
    assign cmd_ready = 1'b1;

    // Pure combinational decode: unsupported opcodes produce no access.
    always @(*) begin
        write_en        = 1'b0;
        write_column    = {COLUMN_ADDR_WIDTH{1'b0}};
        write_superlane = {SUPERLANE_ADDR_WIDTH{1'b0}};
        write_stream    = {STREAM_ADDR_WIDTH{1'b0}};
        write_lane      = {LANE_ADDR_WIDTH{1'b0}};
        write_data      = 8'h00;
        read_en         = 1'b0;
        read_column     = {COLUMN_ADDR_WIDTH{1'b0}};
        read_superlane  = {SUPERLANE_ADDR_WIDTH{1'b0}};
        read_stream     = {STREAM_ADDR_WIDTH{1'b0}};
        read_lane       = {LANE_ADDR_WIDTH{1'b0}};

        if (cmd_valid) begin
            case (cmd_data[63:56])
                OPCODE_WRITE: begin
                    write_en        = 1'b1;
                    write_column    = cmd_data[48 +: COLUMN_ADDR_WIDTH];
                    write_superlane = cmd_data[40 +: SUPERLANE_ADDR_WIDTH];
                    write_stream    = cmd_data[32 +: STREAM_ADDR_WIDTH];
                    write_lane      = cmd_data[24 +: LANE_ADDR_WIDTH];
                    write_data      = cmd_data[23:16];
                end

                OPCODE_READ: begin
                    read_en         = 1'b1;
                    read_column     = cmd_data[48 +: COLUMN_ADDR_WIDTH];
                    read_superlane  = cmd_data[40 +: SUPERLANE_ADDR_WIDTH];
                    read_stream     = cmd_data[32 +: STREAM_ADDR_WIDTH];
                    read_lane       = cmd_data[24 +: LANE_ADDR_WIDTH];
                end

                default: begin
                    write_en = 1'b0;
                    read_en  = 1'b0;
                end
            endcase
        end
    end

endmodule
