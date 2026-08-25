`timescale 1ns/1ps

// SRF-MEM Integration Wrapper .
//
// Fixed coordinate contract:
//   MEM hemisphere = SRF hemisphere
//   MEM boundary   = SRF column (boundaries/columns 0..13 only)
//   MEM direction  = SRF direction (0 East, 1 West)
//   MEM tile       = SRF superlane
//   MEM segment    = all eight lanes of one SRF superlane
//   MEM producer   = SRF local producer 0
//
// This wrapper owns no state and adds no pipeline stage. Collision routing,
// fault aggregation, ICU, SXM, and MXM integration are outside .
module srf_mem_integration_top #(
    parameter P_MEM_BANK_DEPTH_ROWS = 32768
) (
    input  wire clk_i,
    input  wire rst_ni,

    // Existing full-chip SRF external boundary paths are passed through.
    input  wire [32767:0] srf_boundary_input_data_i,
    input  wire [4095:0]  srf_boundary_input_valid_i,
    output wire [32767:0] srf_boundary_output_data_o,
    output wire [4095:0]  srf_boundary_output_valid_o,

    // Existing MEM command issue paths are passed through unchanged.
    input  wire [103:0]  west_bank_issue_valid_i,
    input  wire [3327:0] west_bank_issue_i,
    input  wire [103:0]  east_bank_issue_valid_i,
    input  wire [3327:0] east_bank_issue_i,

    // Raw observation ports. No  status signal changes data movement.
    output wire [524287:0] srf_state_data_o,
    output wire [65535:0]  srf_state_valid_o,
    output wire [255:0]    srf_collision_o,
    output wire [255:0]    srf_invalid_consume_o,
    output wire            srf_fabric_collision_o,
    output wire            srf_fabric_invalid_consume_o,
    output wire [207:0]    mem_bank_fault_valid_o,
    output wire [623:0]    mem_bank_fault_code_o,
    output wire [25:0]     mem_group_fault_valid_o,
    output wire [1:0]      mem_hemisphere_fault_valid_o,
    output wire [25:0]     mem_group_busy_o,
    output wire [1:0]      mem_hemisphere_busy_o,

    // Reserved until the integration fault policy is frozen.
    output wire            system_fault_reserved_o
);

    localparam P_HEMISPHERES         = 2;
    localparam P_DIRECTIONS          = 2;
    localparam P_SR_COLUMNS          = 16;
    localparam P_MEM_BOUNDARIES      = 14;
    localparam P_SUPERLANES          = 4;
    localparam P_STREAMS             = 32;
    localparam P_LANES               = 8;
    localparam P_DATA_BITS           = 8;
    localparam P_LOCAL_PRODUCERS     = 2;
    localparam P_LOCAL_CONSUMERS     = 2;
    localparam P_MEM_PRODUCERS       = 416;
    localparam P_MEM_BOUNDARY_CELLS  = 256;

    localparam P_SRF_INJECT_BITS =
        P_HEMISPHERES * P_DIRECTIONS * P_SR_COLUMNS * P_SUPERLANES *
        P_LOCAL_PRODUCERS * P_STREAMS * P_LANES;
    localparam P_SRF_CONSUME_BITS =
        P_HEMISPHERES * P_DIRECTIONS * P_SR_COLUMNS * P_SUPERLANES *
        P_LOCAL_CONSUMERS * P_STREAMS * P_LANES;

    wire [P_SRF_INJECT_BITS-1:0]             srf_inject_valid;
    wire [P_SRF_INJECT_BITS*P_DATA_BITS-1:0] srf_inject_data;
    wire [P_SRF_CONSUME_BITS-1:0]            srf_consume;

    wire [P_HEMISPHERES*P_MEM_BOUNDARIES*P_MEM_BOUNDARY_CELLS-1:0]
        mem_boundary_state_valid;
    wire [P_HEMISPHERES*P_MEM_BOUNDARIES*P_MEM_BOUNDARY_CELLS*64-1:0]
        mem_boundary_state_data;
    wire [P_HEMISPHERES*P_MEM_BOUNDARIES*P_MEM_BOUNDARY_CELLS-1:0]
        mem_boundary_consume;

    wire [P_HEMISPHERES*P_MEM_PRODUCERS-1:0] mem_producer_valid;
    wire [P_HEMISPHERES*P_MEM_PRODUCERS*64-1:0] mem_producer_data;
    wire [P_HEMISPHERES*P_MEM_PRODUCERS-1:0] mem_producer_stream_dir;
    wire [P_HEMISPHERES*P_MEM_PRODUCERS*5-1:0]
        mem_producer_stream_idx;
    wire [P_HEMISPHERES*P_MEM_PRODUCERS*4-1:0]
        mem_producer_boundary;
    wire [P_HEMISPHERES*P_MEM_PRODUCERS-1:0]
        mem_internal_collision;

    wire [207:0] mem_bank_fault_tile_valid_unused;
    wire [415:0] mem_bank_fault_tile_id_unused;
    wire [3119:0] mem_bank_fault_row_unused;

    // SRF raw state -> MEM segment state. One MEM segment is the complete set
    // of eight lanes in a superlane.  treats a segment as valid only when
    // all eight SRF lane-valid bits are set.
    genvar map_hemi;
    genvar map_boundary;
    genvar map_direction;
    genvar map_stream;
    genvar map_tile;
    generate
        for (map_hemi = 0; map_hemi < P_HEMISPHERES;
             map_hemi = map_hemi + 1) begin : g_state_hemi
            for (map_boundary = 0; map_boundary < P_MEM_BOUNDARIES;
                 map_boundary = map_boundary + 1) begin : g_state_boundary
                for (map_direction = 0; map_direction < P_DIRECTIONS;
                     map_direction = map_direction + 1) begin : g_state_dir
                    for (map_stream = 0; map_stream < P_STREAMS;
                         map_stream = map_stream + 1) begin : g_state_stream
                        for (map_tile = 0; map_tile < P_SUPERLANES;
                             map_tile = map_tile + 1) begin : g_state_tile
                            localparam MEM_CELL =
                                map_hemi*P_MEM_BOUNDARIES*P_MEM_BOUNDARY_CELLS +
                                map_boundary*P_MEM_BOUNDARY_CELLS +
                                map_direction*128 + map_stream*P_SUPERLANES +
                                map_tile;
                            localparam SR_LANE_BASE =
                                (((map_hemi*P_DIRECTIONS + map_direction)*
                                  P_SR_COLUMNS + map_boundary)*P_SUPERLANES +
                                  map_tile)*P_STREAMS*P_LANES +
                                map_stream*P_LANES;

                            assign mem_boundary_state_valid[MEM_CELL] =
                                &srf_state_valid_o[SR_LANE_BASE +: P_LANES];
                            assign mem_boundary_state_data[MEM_CELL*64 +: 64] =
                                srf_state_data_o[SR_LANE_BASE*P_DATA_BITS +: 64];
                        end
                    end
                end
            end
        end
    endgenerate

    // MEM segment consume -> SRF consumer 0. Consumer 1 and columns 14..15
    // remain zero. A segment consume is replicated to all eight lanes.
    reg [P_SRF_CONSUME_BITS-1:0] srf_consume_comb;
    integer consume_hemi;
    integer consume_boundary;
    integer consume_direction;
    integer consume_stream;
    integer consume_tile;
    integer consume_lane;
    integer consume_mem_cell;
    integer consume_srf_bit;
    always @* begin
        srf_consume_comb = {P_SRF_CONSUME_BITS{1'b0}};
        for (consume_hemi = 0; consume_hemi < P_HEMISPHERES;
             consume_hemi = consume_hemi + 1) begin
            for (consume_boundary = 0;
                 consume_boundary < P_MEM_BOUNDARIES;
                 consume_boundary = consume_boundary + 1) begin
                for (consume_direction = 0;
                     consume_direction < P_DIRECTIONS;
                     consume_direction = consume_direction + 1) begin
                    for (consume_stream = 0;
                         consume_stream < P_STREAMS;
                         consume_stream = consume_stream + 1) begin
                        for (consume_tile = 0;
                             consume_tile < P_SUPERLANES;
                             consume_tile = consume_tile + 1) begin
                            consume_mem_cell =
                                consume_hemi*P_MEM_BOUNDARIES*
                                    P_MEM_BOUNDARY_CELLS +
                                consume_boundary*P_MEM_BOUNDARY_CELLS +
                                consume_direction*128 +
                                consume_stream*P_SUPERLANES + consume_tile;
                            for (consume_lane = 0; consume_lane < P_LANES;
                                 consume_lane = consume_lane + 1) begin
                                consume_srf_bit =
                                    (((((consume_hemi*P_DIRECTIONS +
                                         consume_direction)*P_SR_COLUMNS +
                                        consume_boundary)*P_SUPERLANES +
                                       consume_tile)*P_LOCAL_CONSUMERS)*
                                      P_STREAMS + consume_stream)*P_LANES +
                                    consume_lane;
                                srf_consume_comb[consume_srf_bit] =
                                    mem_boundary_consume[consume_mem_cell];
                            end
                        end
                    end
                end
            end
        end
    end
    assign srf_consume = srf_consume_comb;

    // MEM Read producer candidates -> SRF producer 0. The 64-bit segment is
    // split into eight lane bytes and valid is replicated to all lanes. 
    // assumes collision-free scheduling. Overlapping candidates are outside
    // the  contract; procedural assignment order is not an architectural
    // winner policy and must not be relied upon.
    reg [P_SRF_INJECT_BITS-1:0]             srf_inject_valid_comb;
    reg [P_SRF_INJECT_BITS*P_DATA_BITS-1:0] srf_inject_data_comb;
    integer producer_hemi;
    integer producer_id;
    integer producer_global;
    integer producer_tile;
    integer producer_target_boundary;
    integer producer_target_direction;
    integer producer_target_stream;
    integer producer_lane;
    integer producer_srf_bit;
    always @* begin
        srf_inject_valid_comb = {P_SRF_INJECT_BITS{1'b0}};
        srf_inject_data_comb = {P_SRF_INJECT_BITS*P_DATA_BITS{1'b0}};
        for (producer_hemi = 0; producer_hemi < P_HEMISPHERES;
             producer_hemi = producer_hemi + 1) begin
            for (producer_id = 0; producer_id < P_MEM_PRODUCERS;
                 producer_id = producer_id + 1) begin
                producer_global = producer_hemi*P_MEM_PRODUCERS + producer_id;
                producer_tile = producer_id % P_SUPERLANES;
                producer_target_boundary =
                    mem_producer_boundary[producer_global*4 +: 4];
                producer_target_direction =
                    mem_producer_stream_dir[producer_global];
                producer_target_stream =
                    mem_producer_stream_idx[producer_global*5 +: 5];
                if (mem_producer_valid[producer_global] &&
                    producer_target_boundary < P_MEM_BOUNDARIES) begin
                    for (producer_lane = 0; producer_lane < P_LANES;
                         producer_lane = producer_lane + 1) begin
                        producer_srf_bit =
                            (((((producer_hemi*P_DIRECTIONS +
                                 producer_target_direction)*P_SR_COLUMNS +
                                producer_target_boundary)*P_SUPERLANES +
                               producer_tile)*P_LOCAL_PRODUCERS)*P_STREAMS +
                              producer_target_stream)*P_LANES + producer_lane;
                        srf_inject_valid_comb[producer_srf_bit] = 1'b1;
                        srf_inject_data_comb[
                            producer_srf_bit*P_DATA_BITS +: P_DATA_BITS] =
                            mem_producer_data[
                                producer_global*64 + producer_lane*8 +: 8];
                    end
                end
            end
        end
    end
    assign srf_inject_valid = srf_inject_valid_comb;
    assign srf_inject_data = srf_inject_data_comb;

    ftlpu_sr_fabric #(
        .P_HEMISPHERES(2),
        .SR_COLUMNS_PER_HEMI(16),
        .P_SUPERLANES_PER_COLUMN(4),
        .P_STREAMS_PER_DIR(32),
        .P_LANES_PER_SUPERLANE(8),
        .P_SR_DATA_BITS(8),
        .P_SR_HOP_CYCLES(1),
        .P_LOCAL_PRODUCERS(2),
        .P_LOCAL_CONSUMERS(2)
    ) u_srf (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .boundary_input_data(srf_boundary_input_data_i),
        .boundary_input_valid(srf_boundary_input_valid_i),
        .boundary_output_data(srf_boundary_output_data_o),
        .boundary_output_valid(srf_boundary_output_valid_o),
        .inject_valid_i(srf_inject_valid),
        .inject_data_i(srf_inject_data),
        .consume_i(srf_consume),
        .collision_o(srf_collision_o),
        .invalid_consume_o(srf_invalid_consume_o),
        .state_data_out(srf_state_data_o),
        .state_valid_out(srf_state_valid_o),
        .fabric_collision(srf_fabric_collision_o),
        .fabric_invalid_consume(srf_fabric_invalid_consume_o)
    );

    mem_full #(
        .P_MEM_SLICES_PER_HEMI(52),
        .P_MEM_SLICES_PER_GROUP(4),
        .P_MEM_BANK_DEPTH_ROWS(P_MEM_BANK_DEPTH_ROWS),
        .P_SLICE_FAULT_CODE_BITS(3)
    ) u_mem (
        .clk_i(clk_i),
        .west_rst_ni(rst_ni),
        .east_rst_ni(rst_ni),
        .west_bank_issue_valid_i(west_bank_issue_valid_i),
        .west_bank_issue_i(west_bank_issue_i),
        .west_mem_boundary_state_valid_i(
            mem_boundary_state_valid[0 +: 3584]),
        .west_mem_boundary_state_data_i(
            mem_boundary_state_data[0 +: 229376]),
        .west_external_producer_collision_i(5824'b0),
        .west_mem_boundary_consume_o(mem_boundary_consume[0 +: 3584]),
        .west_producer_valid_o(mem_producer_valid[0 +: 416]),
        .west_producer_data_o(mem_producer_data[0 +: 26624]),
        .west_producer_stream_dir_o(
            mem_producer_stream_dir[0 +: 416]),
        .west_producer_stream_idx_o(
            mem_producer_stream_idx[0 +: 2080]),
        .west_producer_boundary_o(mem_producer_boundary[0 +: 1664]),
        .west_internal_mem_collision_o(
            mem_internal_collision[0 +: 416]),
        .west_bank_fault_valid_o(mem_bank_fault_valid_o[0 +: 104]),
        .west_bank_fault_code_o(mem_bank_fault_code_o[0 +: 312]),
        .west_bank_fault_tile_valid_o(
            mem_bank_fault_tile_valid_unused[0 +: 104]),
        .west_bank_fault_tile_id_o(
            mem_bank_fault_tile_id_unused[0 +: 208]),
        .west_bank_fault_row_o(mem_bank_fault_row_unused[0 +: 1560]),
        .west_group_fault_valid_o(mem_group_fault_valid_o[0 +: 13]),
        .west_hemisphere_fault_valid_o(
            mem_hemisphere_fault_valid_o[0]),
        .west_group_busy_o(mem_group_busy_o[0 +: 13]),
        .west_hemisphere_busy_o(mem_hemisphere_busy_o[0]),
        .east_bank_issue_valid_i(east_bank_issue_valid_i),
        .east_bank_issue_i(east_bank_issue_i),
        .east_mem_boundary_state_valid_i(
            mem_boundary_state_valid[3584 +: 3584]),
        .east_mem_boundary_state_data_i(
            mem_boundary_state_data[229376 +: 229376]),
        .east_external_producer_collision_i(5824'b0),
        .east_mem_boundary_consume_o(mem_boundary_consume[3584 +: 3584]),
        .east_producer_valid_o(mem_producer_valid[416 +: 416]),
        .east_producer_data_o(mem_producer_data[26624 +: 26624]),
        .east_producer_stream_dir_o(
            mem_producer_stream_dir[416 +: 416]),
        .east_producer_stream_idx_o(
            mem_producer_stream_idx[2080 +: 2080]),
        .east_producer_boundary_o(mem_producer_boundary[1664 +: 1664]),
        .east_internal_mem_collision_o(
            mem_internal_collision[416 +: 416]),
        .east_bank_fault_valid_o(mem_bank_fault_valid_o[104 +: 104]),
        .east_bank_fault_code_o(mem_bank_fault_code_o[312 +: 312]),
        .east_bank_fault_tile_valid_o(
            mem_bank_fault_tile_valid_unused[104 +: 104]),
        .east_bank_fault_tile_id_o(
            mem_bank_fault_tile_id_unused[208 +: 208]),
        .east_bank_fault_row_o(mem_bank_fault_row_unused[1560 +: 1560]),
        .east_group_fault_valid_o(mem_group_fault_valid_o[13 +: 13]),
        .east_hemisphere_fault_valid_o(
            mem_hemisphere_fault_valid_o[1]),
        .east_group_busy_o(mem_group_busy_o[13 +: 13]),
        .east_hemisphere_busy_o(mem_hemisphere_busy_o[1])
    );

    // Reserved  integration outputs intentionally have no behavior.
    assign system_fault_reserved_o = 1'b0;

endmodule
