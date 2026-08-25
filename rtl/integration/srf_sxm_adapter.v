`timescale 1ns/1ps

// Stateless SRF/SXM interface conversion. This module performs only packed
// bus indexing, lane/segment conversion, and static slot mapping. It contains
// no register, queue, arbitration, retry, or cycle state.
module srf_sxm_adapter #(
    parameter integer P_HEMISPHERES        = 2,
    parameter integer P_DIRECTIONS         = 2,
    parameter integer P_COLUMNS            = 16,
    parameter integer P_SUPERLANES         = 4,
    parameter integer P_STREAMS            = 32,
    parameter integer P_LANES              = 8,
    parameter integer P_DATA_BITS          = 8,
    parameter integer P_LOCAL_CONSUMERS    = 2,
    parameter integer P_LOCAL_PRODUCERS    = 2,
    parameter integer P_SXM_ACTIVE_STREAMS = 16,
    parameter integer P_SELECTOR_BITS      = 6,
    parameter integer P_SXM_INPUT_COL_EAST = 14,
    parameter integer P_SXM_INPUT_COL_WEST = 15,
    parameter integer P_SXM_OUTPUT_COL_EAST = 15,
    parameter integer P_SXM_OUTPUT_COL_WEST = 14,
    parameter integer P_SXM_CONSUMER_SLOT  = 1,
    parameter integer P_SXM_PRODUCER_SLOT  = 1
) (
    input wire [P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
                P_STREAMS*P_LANES*P_DATA_BITS-1:0] srf_state_data_i,
    input wire [P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
                P_STREAMS*P_LANES-1:0] srf_state_valid_i,

    input wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS*
                P_SELECTOR_BITS-1:0] sxm_sr_read_req_i,
    output reg [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS-1:0]
                sxm_sr_read_valid_o,
    output reg [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS*
                P_LANES*P_DATA_BITS-1:0] sxm_sr_read_data_o,
    input wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS-1:0]
                sxm_sr_consume_i,

    input wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS-1:0]
                sxm_sr_write_valid_i,
    input wire [P_HEMISPHERES*P_SXM_ACTIVE_STREAMS*P_SELECTOR_BITS-1:0]
                sxm_sr_write_sel_i,
    input wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS*
                P_LANES*P_DATA_BITS-1:0] sxm_sr_write_data_i,

    output reg [P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
                P_LOCAL_CONSUMERS*P_STREAMS*P_LANES-1:0] srf_consume_o,
    output reg [P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
                P_LOCAL_PRODUCERS*P_STREAMS*P_LANES-1:0] srf_inject_valid_o,
    output reg [P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
                P_LOCAL_PRODUCERS*P_STREAMS*P_LANES*P_DATA_BITS-1:0]
                srf_inject_data_o
);

    localparam integer P_SXM_SEGMENT_BITS = P_LANES * P_DATA_BITS;
    localparam integer P_SRF_STATE_CELLS =
        P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*P_STREAMS*P_LANES;
    localparam integer P_SRF_CONSUME_BITS =
        P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
        P_LOCAL_CONSUMERS*P_STREAMS*P_LANES;
    localparam integer P_SRF_INJECT_BITS =
        P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
        P_LOCAL_PRODUCERS*P_STREAMS*P_LANES;
    localparam integer P_SXM_SEGMENTS =
        P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS;

    function integer state_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            state_lane_index =
                (((((hemisphere*P_DIRECTIONS + direction)*P_COLUMNS + column)*
                    P_SUPERLANES + superlane)*P_STREAMS + stream)*P_LANES + lane);
        end
    endfunction

    function integer consume_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer consumer;
        input integer stream;
        input integer lane;
        begin
            consume_lane_index =
                ((((((hemisphere*P_DIRECTIONS + direction)*P_COLUMNS + column)*
                     P_SUPERLANES + superlane)*P_LOCAL_CONSUMERS + consumer)*
                   P_STREAMS + stream)*P_LANES + lane);
        end
    endfunction

    function integer inject_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream;
        input integer lane;
        begin
            inject_lane_index =
                ((((((hemisphere*P_DIRECTIONS + direction)*P_COLUMNS + column)*
                     P_SUPERLANES + superlane)*P_LOCAL_PRODUCERS + producer)*
                   P_STREAMS + stream)*P_LANES + lane);
        end
    endfunction

    integer h;
    integer t;
    integer j;
    integer lane;
    integer segment_index;
    integer selector_index;
    integer direction_value;
    integer stream_value;
    integer column_value;
    integer state_index;
    integer control_index;
    reg [P_SELECTOR_BITS-1:0] selector_value;

    always @* begin
        sxm_sr_read_valid_o = {P_SXM_SEGMENTS{1'b0}};
        sxm_sr_read_data_o = {P_SXM_SEGMENTS*P_SXM_SEGMENT_BITS{1'b0}};
        srf_consume_o = {P_SRF_CONSUME_BITS{1'b0}};
        srf_inject_valid_o = {P_SRF_INJECT_BITS{1'b0}};
        srf_inject_data_o = {P_SRF_INJECT_BITS*P_DATA_BITS{1'b0}};

        // Current SR state -> SXM segment input. East reads column 14; West
        // reads column 15. A segment is valid only when all eight lanes are
        // valid in the same current-state observation.
        for (h = 0; h < P_HEMISPHERES; h = h + 1) begin
            for (t = 0; t < P_SUPERLANES; t = t + 1) begin
                for (j = 0; j < P_SXM_ACTIVE_STREAMS; j = j + 1) begin
                    segment_index = (h*P_SUPERLANES + t)*
                                    P_SXM_ACTIVE_STREAMS + j;
                    selector_index = segment_index*P_SELECTOR_BITS;
                    selector_value = sxm_sr_read_req_i[
                        selector_index +: P_SELECTOR_BITS];
                    direction_value = selector_value[P_SELECTOR_BITS-1];
                    stream_value = selector_value[P_SELECTOR_BITS-2:0];
                    column_value = direction_value ?
                        P_SXM_INPUT_COL_WEST : P_SXM_INPUT_COL_EAST;
                    sxm_sr_read_valid_o[segment_index] = 1'b1;
                    for (lane = 0; lane < P_LANES; lane = lane + 1) begin
                        state_index = state_lane_index(
                            h, direction_value, column_value, t,
                            stream_value, lane);
                        sxm_sr_read_data_o[
                            segment_index*P_SXM_SEGMENT_BITS +
                            lane*P_DATA_BITS +: P_DATA_BITS] =
                            srf_state_data_i[
                                state_index*P_DATA_BITS +: P_DATA_BITS];
                        sxm_sr_read_valid_o[segment_index] =
                            sxm_sr_read_valid_o[segment_index] &
                            srf_state_valid_i[state_index];
                    end

                    // Consume uses the same-cycle read selector. Slot 1 is
                    // statically owned by SXM and one segment expands to all
                    // eight SR lane consume bits.
                    if (sxm_sr_consume_i[segment_index]) begin
                        for (lane = 0; lane < P_LANES; lane = lane + 1) begin
                            control_index = consume_lane_index(
                                h, direction_value, column_value, t,
                                P_SXM_CONSUMER_SLOT, stream_value, lane);
                            srf_consume_o[control_index] = 1'b1;
                        end
                    end
                end
            end
        end

        // SXM producer candidates -> SR local producer slot 1. East writes
        // column 15; West writes column 14. Segment bytes retain lane order.
        for (h = 0; h < P_HEMISPHERES; h = h + 1) begin
            for (t = 0; t < P_SUPERLANES; t = t + 1) begin
                for (j = 0; j < P_SXM_ACTIVE_STREAMS; j = j + 1) begin
                    segment_index = (h*P_SUPERLANES + t)*
                                    P_SXM_ACTIVE_STREAMS + j;
                    selector_index = (h*P_SXM_ACTIVE_STREAMS + j)*
                                     P_SELECTOR_BITS;
                    selector_value = sxm_sr_write_sel_i[
                        selector_index +: P_SELECTOR_BITS];
                    direction_value = selector_value[P_SELECTOR_BITS-1];
                    stream_value = selector_value[P_SELECTOR_BITS-2:0];
                    column_value = direction_value ?
                        P_SXM_OUTPUT_COL_WEST : P_SXM_OUTPUT_COL_EAST;
                    if (sxm_sr_write_valid_i[segment_index]) begin
                        for (lane = 0; lane < P_LANES; lane = lane + 1) begin
                            control_index = inject_lane_index(
                                h, direction_value, column_value, t,
                                P_SXM_PRODUCER_SLOT, stream_value, lane);
                            srf_inject_valid_o[control_index] = 1'b1;
                            srf_inject_data_o[
                                control_index*P_DATA_BITS +: P_DATA_BITS] =
                                sxm_sr_write_data_i[
                                    segment_index*P_SXM_SEGMENT_BITS +
                                    lane*P_DATA_BITS +: P_DATA_BITS];
                        end
                    end
                end
            end
        end
    end

endmodule
