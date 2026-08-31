`timescale 1ns/1ps

// Independent SRF + SXM integration baseline. MEM is intentionally absent.
// Static local slot ownership is producer/consumer slot 1 for SXM; slot 0 is
// tied off in this baseline.
module srf_sxm_integration_top #(
    parameter integer P_HEMISPHERES     = 2,
    parameter integer P_COLUMNS         = 16,
    parameter integer P_SUPERLANES      = 4,
    parameter integer P_STREAMS         = 32,
    parameter integer P_LANES           = 8,
    parameter integer P_DATA_BITS       = 8,
    parameter integer P_LOCAL_PRODUCERS = 2,
    parameter integer P_LOCAL_CONSUMERS = 2,
    parameter integer P_SXM_CONSUMER_SLOT = 1,
    parameter integer P_SXM_PRODUCER_SLOT = 1
) (
    input wire clk_i,
    input wire rst_ni,

    input wire [P_HEMISPHERES*2*P_SUPERLANES*P_STREAMS*P_LANES*
                P_DATA_BITS-1:0] srf_boundary_input_data_i,
    input wire [P_HEMISPHERES*2*P_SUPERLANES*P_STREAMS*P_LANES-1:0]
                srf_boundary_input_valid_i,
    output wire [P_HEMISPHERES*2*P_SUPERLANES*P_STREAMS*P_LANES*
                 P_DATA_BITS-1:0] srf_boundary_output_data_o,
    output wire [P_HEMISPHERES*2*P_SUPERLANES*P_STREAMS*P_LANES-1:0]
                 srf_boundary_output_valid_o,

    input wire [P_HEMISPHERES-1:0] transpose_cmd_valid_i,
    input wire [P_HEMISPHERES*96-1:0] transpose_cmd_i,
    input wire [P_HEMISPHERES-1:0] permute_cmd_valid_i,
    input wire [P_HEMISPHERES*96-1:0] permute_cmd_i,

    output wire [P_HEMISPHERES*2*P_COLUMNS*P_SUPERLANES*P_STREAMS*
                 P_LANES*P_DATA_BITS-1:0] srf_state_data_o,
    output wire [P_HEMISPHERES*2*P_COLUMNS*P_SUPERLANES*P_STREAMS*
                 P_LANES-1:0] srf_state_valid_o,
    output wire [P_HEMISPHERES*2*P_COLUMNS*P_SUPERLANES-1:0]
                 srf_collision_o,
    output wire [P_HEMISPHERES*2*P_COLUMNS*P_SUPERLANES-1:0]
                 srf_invalid_consume_o,
    output wire srf_fabric_collision_o,
    output wire srf_fabric_invalid_consume_o,

    output wire [P_HEMISPHERES-1:0] sxm_fault_valid_o,
    output wire [P_HEMISPHERES*P_SUPERLANES-1:0]
                 sxm_transpose_input_invalid_o,
    output wire [P_HEMISPHERES*P_SUPERLANES-1:0]
                 sxm_transpose_buffer_full_o,
    output wire [P_HEMISPHERES-1:0] sxm_permute_phase_fault_o,
    output wire [P_HEMISPHERES-1:0] sxm_permute_selector_fault_o,
    output wire [P_HEMISPHERES-1:0] sxm_permute_buffer_not_ready_o,
    output wire [P_HEMISPHERES-1:0] sxm_busy_o
);

    localparam integer P_DIRECTIONS = 2;
    localparam integer P_SXM_ACTIVE_STREAMS = 16;
    localparam integer P_SELECTOR_BITS = 6;
    localparam integer P_SRF_CONSUME_BITS =
        P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
        P_LOCAL_CONSUMERS*P_STREAMS*P_LANES;
    localparam integer P_SRF_INJECT_BITS =
        P_HEMISPHERES*P_DIRECTIONS*P_COLUMNS*P_SUPERLANES*
        P_LOCAL_PRODUCERS*P_STREAMS*P_LANES;

    wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS*
          P_SELECTOR_BITS-1:0] sxm_sr_read_req;
    wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS-1:0]
          sxm_sr_read_valid;
    wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS*
          P_LANES*P_DATA_BITS-1:0] sxm_sr_read_data;
    wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS-1:0]
          sxm_sr_consume;
    wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS-1:0]
          sxm_sr_write_valid;
    wire [P_HEMISPHERES*P_SXM_ACTIVE_STREAMS*P_SELECTOR_BITS-1:0]
          sxm_sr_write_sel;
    wire [P_HEMISPHERES*P_SUPERLANES*P_SXM_ACTIVE_STREAMS*
          P_LANES*P_DATA_BITS-1:0] sxm_sr_write_data;
    wire [P_SRF_CONSUME_BITS-1:0] srf_consume;
    wire [P_SRF_INJECT_BITS-1:0] srf_inject_valid;
    wire [P_SRF_INJECT_BITS*P_DATA_BITS-1:0] srf_inject_data;

    stream_sr_fabric #(
        .P_HEMISPHERES(P_HEMISPHERES),
        .SR_COLUMNS_PER_HEMI(P_COLUMNS),
        .P_SUPERLANES_PER_COLUMN(P_SUPERLANES),
        .P_STREAMS_PER_DIR(P_STREAMS),
        .P_LANES_PER_SUPERLANE(P_LANES),
        .P_SR_DATA_BITS(P_DATA_BITS),
        .P_LOCAL_PRODUCERS(P_LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS(P_LOCAL_CONSUMERS)
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

    sxm_full u_sxm (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .transpose_cmd_valid_i(transpose_cmd_valid_i),
        .transpose_cmd_i(transpose_cmd_i),
        .permute_cmd_valid_i(permute_cmd_valid_i),
        .permute_cmd_i(permute_cmd_i),
        .sr_read_req_o(sxm_sr_read_req),
        .sr_read_valid_i(sxm_sr_read_valid),
        .sr_read_data_i(sxm_sr_read_data),
        .sr_consume_o(sxm_sr_consume),
        .sr_write_valid_o(sxm_sr_write_valid),
        .sr_write_sel_o(sxm_sr_write_sel),
        .sr_write_data_o(sxm_sr_write_data),
        .fault_valid_o(sxm_fault_valid_o),
        .transpose_input_invalid_o(sxm_transpose_input_invalid_o),
        .transpose_buffer_full_o(sxm_transpose_buffer_full_o),
        .permute_phase_fault_o(sxm_permute_phase_fault_o),
        .permute_selector_fault_o(sxm_permute_selector_fault_o),
        .permute_buffer_not_ready_o(sxm_permute_buffer_not_ready_o),
        .busy_o(sxm_busy_o)
    );

    srf_sxm_adapter #(
        .P_HEMISPHERES(P_HEMISPHERES),
        .P_DIRECTIONS(P_DIRECTIONS),
        .P_COLUMNS(P_COLUMNS),
        .P_SUPERLANES(P_SUPERLANES),
        .P_STREAMS(P_STREAMS),
        .P_LANES(P_LANES),
        .P_DATA_BITS(P_DATA_BITS),
        .P_LOCAL_CONSUMERS(P_LOCAL_CONSUMERS),
        .P_LOCAL_PRODUCERS(P_LOCAL_PRODUCERS),
        .P_SXM_ACTIVE_STREAMS(P_SXM_ACTIVE_STREAMS),
        .P_SELECTOR_BITS(P_SELECTOR_BITS),
        .P_SXM_CONSUMER_SLOT(P_SXM_CONSUMER_SLOT),
        .P_SXM_PRODUCER_SLOT(P_SXM_PRODUCER_SLOT)
    ) u_adapter (
        .srf_state_data_i(srf_state_data_o),
        .srf_state_valid_i(srf_state_valid_o),
        .sxm_sr_read_req_i(sxm_sr_read_req),
        .sxm_sr_read_valid_o(sxm_sr_read_valid),
        .sxm_sr_read_data_o(sxm_sr_read_data),
        .sxm_sr_consume_i(sxm_sr_consume),
        .sxm_sr_write_valid_i(sxm_sr_write_valid),
        .sxm_sr_write_sel_i(sxm_sr_write_sel),
        .sxm_sr_write_data_i(sxm_sr_write_data),
        .srf_consume_o(srf_consume),
        .srf_inject_valid_o(srf_inject_valid),
        .srf_inject_data_o(srf_inject_data)
    );

endmodule
