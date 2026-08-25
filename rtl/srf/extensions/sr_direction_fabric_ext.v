`timescale 1ns/1ps

// NON-SPEC EXTENSION adapter. It preserves the development-time command and
// direct-access interface without adding ports or state to the SRF core.
// Writes become an extra local producer; reads select the core state outputs.
module sr_direction_fabric_ext #(
    parameter COLUMN_NUM            = 16,
    parameter SUPERLANE_NUM         = 4,
    parameter STREAM_NUM            = 32,
    parameter LANE_NUM              = 8,
    parameter DATA_BITS             = 8,
    parameter P_SR_HOP_CYCLES       = 1,
    parameter LOCAL_PRODUCERS       = 2,
    parameter LOCAL_CONSUMERS       = 2,
    parameter COLUMN_ADDR_WIDTH     = 4,
    parameter SUPERLANE_ADDR_WIDTH  = 2,
    parameter STREAM_ADDR_WIDTH     = 5,
    parameter LANE_ADDR_WIDTH       = 3
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire direction,
    input  wire cmd_valid,
    output wire cmd_ready,
    input  wire [63:0] cmd_data,
    input  wire [SUPERLANE_NUM*STREAM_NUM*LANE_NUM*DATA_BITS-1:0] stream_data_in,
    input  wire [SUPERLANE_NUM*STREAM_NUM*LANE_NUM-1:0]           stream_valid_in,
    output wire [SUPERLANE_NUM*STREAM_NUM*LANE_NUM*DATA_BITS-1:0] stream_data_out,
    output wire [SUPERLANE_NUM*STREAM_NUM*LANE_NUM-1:0]           stream_valid_out,
    input  wire [COLUMN_NUM*SUPERLANE_NUM*LOCAL_PRODUCERS*STREAM_NUM*LANE_NUM-1:0] inject_valid_i,
    input  wire [COLUMN_NUM*SUPERLANE_NUM*LOCAL_PRODUCERS*STREAM_NUM*LANE_NUM*DATA_BITS-1:0] inject_data_i,
    input  wire [COLUMN_NUM*SUPERLANE_NUM*LOCAL_CONSUMERS*STREAM_NUM*LANE_NUM-1:0] consume_i,
    output wire [COLUMN_NUM*SUPERLANE_NUM-1:0] collision_o,
    output wire [COLUMN_NUM*SUPERLANE_NUM-1:0] invalid_consume_o,
    output wire [COLUMN_NUM*SUPERLANE_NUM*STREAM_NUM*LANE_NUM*DATA_BITS-1:0] state_data_out,
    output wire [COLUMN_NUM*SUPERLANE_NUM*STREAM_NUM*LANE_NUM-1:0]           state_valid_out,

    input  wire                                      write_en,
    input  wire [COLUMN_ADDR_WIDTH-1:0]             write_column,
    input  wire [SUPERLANE_ADDR_WIDTH-1:0]          write_superlane,
    input  wire [STREAM_ADDR_WIDTH-1:0]             write_stream,
    input  wire [LANE_ADDR_WIDTH-1:0]               write_lane,
    input  wire [DATA_BITS-1:0]                     write_data,
    input  wire                                      read_en,
    input  wire [COLUMN_ADDR_WIDTH-1:0]             read_column,
    input  wire [SUPERLANE_ADDR_WIDTH-1:0]          read_superlane,
    input  wire [STREAM_ADDR_WIDTH-1:0]             read_stream,
    input  wire [LANE_ADDR_WIDTH-1:0]               read_lane,
    output wire [DATA_BITS-1:0]                     read_data,
    output wire                                      read_valid
);

    localparam LEAF_CELL_NUM = STREAM_NUM * LANE_NUM;
    localparam LEAF_NUM = COLUMN_NUM * SUPERLANE_NUM;
    localparam CORE_PRODUCERS = LOCAL_PRODUCERS + 1;
    localparam EXT_LEAF_INJECT_WIDTH = LOCAL_PRODUCERS * LEAF_CELL_NUM;
    localparam CORE_LEAF_INJECT_WIDTH = CORE_PRODUCERS * LEAF_CELL_NUM;
    localparam CORE_INJECT_WIDTH = LEAF_NUM * CORE_LEAF_INJECT_WIDTH;
    localparam CONSUME_WIDTH = COLUMN_NUM * SUPERLANE_NUM *
                               LOCAL_CONSUMERS * LEAF_CELL_NUM;
    localparam STATE_CELL_NUM = COLUMN_NUM * SUPERLANE_NUM * LEAF_CELL_NUM;
    localparam BOUNDARY_CELL_NUM = SUPERLANE_NUM * LEAF_CELL_NUM;

    wire controller_write_en;
    wire [COLUMN_ADDR_WIDTH-1:0] controller_write_column;
    wire [SUPERLANE_ADDR_WIDTH-1:0] controller_write_superlane;
    wire [STREAM_ADDR_WIDTH-1:0] controller_write_stream;
    wire [LANE_ADDR_WIDTH-1:0] controller_write_lane;
    wire [7:0] controller_write_data;
    wire controller_read_en;
    wire [COLUMN_ADDR_WIDTH-1:0] controller_read_column;
    wire [SUPERLANE_ADDR_WIDTH-1:0] controller_read_superlane;
    wire [STREAM_ADDR_WIDTH-1:0] controller_read_stream;
    wire [LANE_ADDR_WIDTH-1:0] controller_read_lane;

    wire effective_write_en;
    wire [COLUMN_ADDR_WIDTH-1:0] effective_write_column;
    wire [SUPERLANE_ADDR_WIDTH-1:0] effective_write_superlane;
    wire [STREAM_ADDR_WIDTH-1:0] effective_write_stream;
    wire [LANE_ADDR_WIDTH-1:0] effective_write_lane;
    wire [DATA_BITS-1:0] effective_write_data;
    wire effective_read_en;
    wire [COLUMN_ADDR_WIDTH-1:0] effective_read_column;
    wire [SUPERLANE_ADDR_WIDTH-1:0] effective_read_superlane;
    wire [STREAM_ADDR_WIDTH-1:0] effective_read_stream;
    wire [LANE_ADDR_WIDTH-1:0] effective_read_lane;

    wire [CORE_INJECT_WIDTH-1:0] east_core_inject_valid;
    wire [CORE_INJECT_WIDTH*DATA_BITS-1:0] east_core_inject_data;
    wire [CORE_INJECT_WIDTH-1:0] west_core_inject_valid;
    wire [CORE_INJECT_WIDTH*DATA_BITS-1:0] west_core_inject_data;
    wire [CONSUME_WIDTH-1:0] east_core_consume;
    wire [CONSUME_WIDTH-1:0] west_core_consume;

    wire [BOUNDARY_CELL_NUM*DATA_BITS-1:0] east_stream_data_out;
    wire [BOUNDARY_CELL_NUM-1:0] east_stream_valid_out;
    wire [BOUNDARY_CELL_NUM*DATA_BITS-1:0] west_stream_data_out;
    wire [BOUNDARY_CELL_NUM-1:0] west_stream_valid_out;
    wire [STATE_CELL_NUM*DATA_BITS-1:0] east_state_data;
    wire [STATE_CELL_NUM-1:0] east_state_valid;
    wire [STATE_CELL_NUM*DATA_BITS-1:0] west_state_data;
    wire [STATE_CELL_NUM-1:0] west_state_valid;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] east_collision;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] west_collision;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] east_invalid_consume;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] west_invalid_consume;

    sr_controller #(
        .COLUMN_ADDR_WIDTH(COLUMN_ADDR_WIDTH),
        .SUPERLANE_ADDR_WIDTH(SUPERLANE_ADDR_WIDTH),
        .STREAM_ADDR_WIDTH(STREAM_ADDR_WIDTH),
        .LANE_ADDR_WIDTH(LANE_ADDR_WIDTH)
    ) u_sr_controller (
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_data(cmd_data),
        .write_en(controller_write_en),
        .write_column(controller_write_column),
        .write_superlane(controller_write_superlane),
        .write_stream(controller_write_stream),
        .write_lane(controller_write_lane),
        .write_data(controller_write_data),
        .read_en(controller_read_en),
        .read_column(controller_read_column),
        .read_superlane(controller_read_superlane),
        .read_stream(controller_read_stream),
        .read_lane(controller_read_lane)
    );

    assign effective_write_en = controller_write_en | write_en;
    assign effective_write_column = controller_write_en ?
        controller_write_column : write_column;
    assign effective_write_superlane = controller_write_en ?
        controller_write_superlane : write_superlane;
    assign effective_write_stream = controller_write_en ?
        controller_write_stream : write_stream;
    assign effective_write_lane = controller_write_en ?
        controller_write_lane : write_lane;
    assign effective_write_data = controller_write_en ?
        controller_write_data : write_data;
    assign effective_read_en = controller_read_en | read_en;
    assign effective_read_column = controller_read_en ?
        controller_read_column : read_column;
    assign effective_read_superlane = controller_read_en ?
        controller_read_superlane : read_superlane;
    assign effective_read_stream = controller_read_en ?
        controller_read_stream : read_stream;
    assign effective_read_lane = controller_read_en ?
        controller_read_lane : read_lane;

    assign east_core_consume = direction ? {CONSUME_WIDTH{1'b0}} : consume_i;
    assign west_core_consume = direction ? consume_i : {CONSUME_WIDTH{1'b0}};

    genvar column;
    genvar superlane;
    genvar cell_index;
    generate
        for (column = 0; column < COLUMN_NUM; column = column + 1) begin : g_column
            for (superlane = 0; superlane < SUPERLANE_NUM;
                 superlane = superlane + 1) begin : g_superlane
                localparam LEAF_INDEX = column*SUPERLANE_NUM + superlane;
                localparam EXT_BASE = LEAF_INDEX*EXT_LEAF_INJECT_WIDTH;
                localparam CORE_BASE = LEAF_INDEX*CORE_LEAF_INJECT_WIDTH;

                assign east_core_inject_valid[CORE_BASE +: EXT_LEAF_INJECT_WIDTH] =
                    direction ? {EXT_LEAF_INJECT_WIDTH{1'b0}} :
                    inject_valid_i[EXT_BASE +: EXT_LEAF_INJECT_WIDTH];
                assign west_core_inject_valid[CORE_BASE +: EXT_LEAF_INJECT_WIDTH] =
                    direction ? inject_valid_i[EXT_BASE +: EXT_LEAF_INJECT_WIDTH] :
                    {EXT_LEAF_INJECT_WIDTH{1'b0}};
                assign east_core_inject_data[CORE_BASE*DATA_BITS +:
                                             EXT_LEAF_INJECT_WIDTH*DATA_BITS] =
                    inject_data_i[EXT_BASE*DATA_BITS +:
                                  EXT_LEAF_INJECT_WIDTH*DATA_BITS];
                assign west_core_inject_data[CORE_BASE*DATA_BITS +:
                                             EXT_LEAF_INJECT_WIDTH*DATA_BITS] =
                    inject_data_i[EXT_BASE*DATA_BITS +:
                                  EXT_LEAF_INJECT_WIDTH*DATA_BITS];

                for (cell_index = 0; cell_index < LEAF_CELL_NUM;
                     cell_index = cell_index + 1) begin : g_access_cell
                    localparam ACCESS_INDEX = CORE_BASE +
                        LOCAL_PRODUCERS*LEAF_CELL_NUM + cell_index;
                    wire access_target;
                    assign access_target = effective_write_en &&
                        (effective_write_column == column) &&
                        (effective_write_superlane == superlane) &&
                        (effective_write_stream == (cell_index / LANE_NUM)) &&
                        (effective_write_lane == (cell_index % LANE_NUM));
                    assign east_core_inject_valid[ACCESS_INDEX] =
                        !direction && access_target;
                    assign west_core_inject_valid[ACCESS_INDEX] =
                        direction && access_target;
                    assign east_core_inject_data[ACCESS_INDEX*DATA_BITS +: DATA_BITS] =
                        effective_write_data;
                    assign west_core_inject_data[ACCESS_INDEX*DATA_BITS +: DATA_BITS] =
                        effective_write_data;
                end
            end
        end
    endgenerate

    ftlpu_sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM), .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM), .P_LANES_PER_SUPERLANE(LANE_NUM), .P_SR_DATA_BITS(DATA_BITS),
        .P_SR_HOP_CYCLES(P_SR_HOP_CYCLES),
        .P_LOCAL_PRODUCERS(CORE_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS), .DIRECTION(0)
    ) u_east_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .stream_data_in(stream_data_in),
        .stream_valid_in(direction ? {BOUNDARY_CELL_NUM{1'b0}} : stream_valid_in),
        .stream_data_out(east_stream_data_out),
        .stream_valid_out(east_stream_valid_out),
        .inject_valid_i(east_core_inject_valid),
        .inject_data_i(east_core_inject_data), .consume_i(east_core_consume),
        .collision_o(east_collision),
        .invalid_consume_o(east_invalid_consume),
        .state_data_out(east_state_data), .state_valid_out(east_state_valid)
    );

    ftlpu_sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM), .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM), .P_LANES_PER_SUPERLANE(LANE_NUM), .P_SR_DATA_BITS(DATA_BITS),
        .P_SR_HOP_CYCLES(P_SR_HOP_CYCLES),
        .P_LOCAL_PRODUCERS(CORE_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS), .DIRECTION(1)
    ) u_west_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .stream_data_in(stream_data_in),
        .stream_valid_in(direction ? stream_valid_in : {BOUNDARY_CELL_NUM{1'b0}}),
        .stream_data_out(west_stream_data_out),
        .stream_valid_out(west_stream_valid_out),
        .inject_valid_i(west_core_inject_valid),
        .inject_data_i(west_core_inject_data), .consume_i(west_core_consume),
        .collision_o(west_collision),
        .invalid_consume_o(west_invalid_consume),
        .state_data_out(west_state_data), .state_valid_out(west_state_valid)
    );

    assign stream_data_out = direction ? west_stream_data_out : east_stream_data_out;
    assign stream_valid_out = direction ? west_stream_valid_out : east_stream_valid_out;
    assign state_data_out = direction ? west_state_data : east_state_data;
    assign state_valid_out = direction ? west_state_valid : east_state_valid;
    assign collision_o = direction ? west_collision : east_collision;
    assign invalid_consume_o = direction ? west_invalid_consume : east_invalid_consume;

    assign read_data = effective_read_en ?
        state_data_out[
            (((effective_read_column*SUPERLANE_NUM + effective_read_superlane)*
              STREAM_NUM + effective_read_stream)*LANE_NUM + effective_read_lane)*
            DATA_BITS +: DATA_BITS] : {DATA_BITS{1'b0}};
    assign read_valid = effective_read_en ?
        state_valid_out[
            ((effective_read_column*SUPERLANE_NUM + effective_read_superlane)*
             STREAM_NUM + effective_read_stream)*LANE_NUM + effective_read_lane] :
        1'b0;

endmodule
