`timescale 1ns/1ps

module tb_srf_sxm_integration;

    localparam integer HEMISPHERES = 2;
    localparam integer DIRECTIONS = 2;
    localparam integer COLUMNS = 16;
    localparam integer SUPERLANES = 4;
    localparam integer STREAMS = 32;
    localparam integer LANES = 8;
    localparam integer DATA_BITS = 8;
    localparam integer CONSUMERS = 2;
    localparam integer PRODUCERS = 2;

    reg clk_i;
    reg rst_ni;
    reg [32767:0] srf_boundary_input_data_i;
    reg [4095:0] srf_boundary_input_valid_i;
    reg [1:0] transpose_cmd_valid_i;
    reg [191:0] transpose_cmd_i;
    reg [1:0] permute_cmd_valid_i;
    reg [191:0] permute_cmd_i;

    wire [32767:0] srf_boundary_output_data_o;
    wire [4095:0] srf_boundary_output_valid_o;
    wire [524287:0] srf_state_data_o;
    wire [65535:0] srf_state_valid_o;
    wire [255:0] srf_collision_o;
    wire [255:0] srf_invalid_consume_o;
    wire srf_fabric_collision_o;
    wire srf_fabric_invalid_consume_o;
    wire [1:0] sxm_fault_valid_o;
    wire [7:0] sxm_transpose_input_invalid_o;
    wire [7:0] sxm_transpose_buffer_full_o;
    wire [1:0] sxm_permute_phase_fault_o;
    wire [1:0] sxm_permute_selector_fault_o;
    wire [1:0] sxm_permute_buffer_not_ready_o;
    wire [1:0] sxm_busy_o;

    integer errors;
    integer lane;
    integer stream;
    integer tile;
    integer index_value;
    integer before_errors;
    reg [63:0] expected_segment;

    srf_sxm_integration_top dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .srf_boundary_input_data_i(srf_boundary_input_data_i),
        .srf_boundary_input_valid_i(srf_boundary_input_valid_i),
        .srf_boundary_output_data_o(srf_boundary_output_data_o),
        .srf_boundary_output_valid_o(srf_boundary_output_valid_o),
        .transpose_cmd_valid_i(transpose_cmd_valid_i),
        .transpose_cmd_i(transpose_cmd_i),
        .permute_cmd_valid_i(permute_cmd_valid_i),
        .permute_cmd_i(permute_cmd_i),
        .srf_state_data_o(srf_state_data_o),
        .srf_state_valid_o(srf_state_valid_o),
        .srf_collision_o(srf_collision_o),
        .srf_invalid_consume_o(srf_invalid_consume_o),
        .srf_fabric_collision_o(srf_fabric_collision_o),
        .srf_fabric_invalid_consume_o(srf_fabric_invalid_consume_o),
        .sxm_fault_valid_o(sxm_fault_valid_o),
        .sxm_transpose_input_invalid_o(sxm_transpose_input_invalid_o),
        .sxm_transpose_buffer_full_o(sxm_transpose_buffer_full_o),
        .sxm_permute_phase_fault_o(sxm_permute_phase_fault_o),
        .sxm_permute_selector_fault_o(sxm_permute_selector_fault_o),
        .sxm_permute_buffer_not_ready_o(sxm_permute_buffer_not_ready_o),
        .sxm_busy_o(sxm_busy_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function integer boundary_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            boundary_lane_index =
                ((((hemisphere*DIRECTIONS + direction)*SUPERLANES +
                   superlane)*STREAMS + stream_id)*LANES + lane_id);
        end
    endfunction

    function integer state_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            state_lane_index =
                (((((hemisphere*DIRECTIONS + direction)*COLUMNS + column)*
                    SUPERLANES + superlane)*STREAMS + stream_id)*LANES +
                  lane_id);
        end
    endfunction

    function integer consume_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer consumer;
        input integer stream_id;
        input integer lane_id;
        begin
            consume_lane_index =
                ((((((hemisphere*DIRECTIONS + direction)*COLUMNS + column)*
                     SUPERLANES + superlane)*CONSUMERS + consumer)*STREAMS +
                   stream_id)*LANES + lane_id);
        end
    endfunction

    function integer inject_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream_id;
        input integer lane_id;
        begin
            inject_lane_index =
                ((((((hemisphere*DIRECTIONS + direction)*COLUMNS + column)*
                     SUPERLANES + superlane)*PRODUCERS + producer)*STREAMS +
                   stream_id)*LANES + lane_id);
        end
    endfunction

    function integer sxm_segment_index;
        input integer hemisphere;
        input integer superlane;
        input integer active_stream;
        begin
            sxm_segment_index =
                (hemisphere*SUPERLANES + superlane)*16 + active_stream;
        end
    endfunction

    function [95:0] make_command;
        input [1:0] opcode;
        input src_direction;
        input [4:0] src_base;
        input dst_direction;
        input [4:0] dst_base;
        input [3:0] input_row;
        input [3:0] output_row;
        input [2:0] output_tile;
        input [7:0] phase_id;
        reg [95:0] command_value;
        begin
            command_value = 96'b0;
            command_value[1:0] = opcode;
            command_value[2] = src_direction;
            command_value[7:3] = src_base;
            command_value[8] = dst_direction;
            command_value[13:9] = dst_base;
            command_value[17:14] = input_row;
            command_value[21:18] = output_row;
            command_value[24:22] = output_tile;
            command_value[32:25] = phase_id;
            make_command = command_value;
        end
    endfunction

    function [7:0] source_byte;
        input [7:0] seed;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            source_byte = seed + superlane*8'h40 +
                          stream_id*8 + lane_id;
        end
    endfunction

    function [63:0] source_segment;
        input [7:0] seed;
        input integer superlane;
        input integer stream_id;
        integer local_lane;
        reg [63:0] value;
        begin
            value = 64'b0;
            for (local_lane = 0; local_lane < LANES;
                 local_lane = local_lane + 1) begin
                value[local_lane*8 +: 8] =
                    source_byte(seed, superlane, stream_id, local_lane);
            end
            source_segment = value;
        end
    endfunction

    function [63:0] transposed_segment;
        input [7:0] seed;
        input integer superlane;
        input integer output_stream;
        integer local_lane;
        integer plane;
        integer output_row;
        reg [63:0] value;
        begin
            value = 64'b0;
            plane = output_stream % 2;
            output_row = output_stream / 2;
            for (local_lane = 0; local_lane < LANES;
                 local_lane = local_lane + 1) begin
                value[local_lane*8 +: 8] = source_byte(
                    seed, superlane, 2*local_lane + plane, output_row);
            end
            transposed_segment = value;
        end
    endfunction

    task clear_stimulus;
        begin
            srf_boundary_input_data_i = 32768'b0;
            srf_boundary_input_valid_i = 4096'b0;
            transpose_cmd_valid_i = 2'b0;
            transpose_cmd_i = 192'b0;
            permute_cmd_valid_i = 2'b0;
            permute_cmd_i = 192'b0;
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk_i);
            rst_ni = 1'b0;
            clear_stimulus();
            repeat (2) @(posedge clk_i);
            #1;
            if (srf_state_valid_o !== 65536'b0 ||
                sxm_busy_o !== 2'b0 || sxm_fault_valid_o !== 2'b0 ||
                dut.sxm_sr_consume !== 128'b0 ||
                dut.sxm_sr_write_valid !== 128'b0 ||
                srf_fabric_collision_o !== 1'b0 ||
                srf_fabric_invalid_consume_o !== 1'b0) begin
                $display("ERROR reset/idle state");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            #1;
        end
    endtask

    task drive_boundary_wave;
        input integer hemisphere;
        input integer direction;
        input [7:0] seed;
        input integer partial_valid;
        integer local_tile;
        integer local_stream;
        integer local_lane;
        integer boundary_index;
        begin
            @(negedge clk_i);
            srf_boundary_input_data_i = 32768'b0;
            srf_boundary_input_valid_i = 4096'b0;
            for (local_tile = 0; local_tile < SUPERLANES;
                 local_tile = local_tile + 1) begin
                for (local_stream = 0; local_stream < 16;
                     local_stream = local_stream + 1) begin
                    for (local_lane = 0; local_lane < LANES;
                         local_lane = local_lane + 1) begin
                        boundary_index = boundary_lane_index(
                            hemisphere, direction, local_tile,
                            local_stream, local_lane);
                        srf_boundary_input_data_i[
                            boundary_index*DATA_BITS +: DATA_BITS] =
                            source_byte(seed, local_tile,
                                        local_stream, local_lane);
                        if (!(partial_valid != 0 && local_tile == 0 &&
                              local_stream == 0 && local_lane == 7)) begin
                            srf_boundary_input_valid_i[boundary_index] = 1'b1;
                        end
                    end
                end
            end
            @(posedge clk_i);
            #1;
            srf_boundary_input_data_i = 32768'b0;
            srf_boundary_input_valid_i = 4096'b0;
        end
    endtask

    task advance_to_sxm_input;
        input integer direction;
        integer hop;
        begin
            // Boundary input commits at column 0 Eastward or column 15
            // Westward. One registered column is one cycle.
            if (direction == 0) begin
                for (hop = 0; hop < 14; hop = hop + 1) begin
                    @(posedge clk_i);
                    #1;
                end
            end
        end
    endtask

    task check_target_segment;
        input integer hemisphere;
        input integer direction;
        input integer superlane;
        input integer stream_id;
        input [7:0] seed;
        input integer expected_all_valid;
        integer local_lane;
        integer state_index;
        integer column;
        reg all_valid;
        begin
            column = direction ? 15 : 14;
            all_valid = 1'b1;
            for (local_lane = 0; local_lane < LANES;
                 local_lane = local_lane + 1) begin
                state_index = state_lane_index(
                    hemisphere, direction, column, superlane,
                    stream_id, local_lane);
                all_valid = all_valid & srf_state_valid_o[state_index];
                if (srf_state_data_o[state_index*8 +: 8] !==
                    source_byte(seed, superlane, stream_id, local_lane)) begin
                    $display("ERROR source state data h=%0d d=%0d t=%0d s=%0d l=%0d",
                             hemisphere, direction, superlane, stream_id,
                             local_lane);
                    errors = errors + 1;
                end
            end
            if (all_valid !== expected_all_valid[0]) begin
                $display("ERROR source state valid h=%0d d=%0d t=%0d s=%0d",
                         hemisphere, direction, superlane, stream_id);
                errors = errors + 1;
            end
        end
    endtask

    task run_direction_flow;
        input integer hemisphere;
        input integer src_direction;
        input integer dst_direction;
        input [7:0] seed;
        integer local_segment;
        integer local_lane;
        integer segment_index;
        integer source_column;
        integer output_column;
        integer control_index;
        integer state_index;
        reg [95:0] transpose_command;
        reg [95:0] permute_command;
        reg [63:0] expected_input;
        reg [63:0] expected_output;
        begin
            reset_dut();
            drive_boundary_wave(hemisphere, src_direction, seed, 0);
            advance_to_sxm_input(src_direction);
            check_target_segment(hemisphere, src_direction, 0, 0,
                                 seed, 1);

            source_column = src_direction ? 15 : 14;
            output_column = dst_direction ? 14 : 15;
            transpose_command = make_command(
                2'd0, src_direction[0], 5'd0, dst_direction[0], 5'd8,
                4'd8, 4'd0, 3'd0, 8'd0);
            @(negedge clk_i);
            transpose_cmd_valid_i[hemisphere] = 1'b1;
            transpose_cmd_i[hemisphere*96 +: 96] = transpose_command;
            #1;

            for (local_segment = 0; local_segment < 16;
                 local_segment = local_segment + 1) begin
                segment_index = sxm_segment_index(
                    hemisphere, 0, local_segment);
                expected_input = source_segment(seed, 0, local_segment);
                if (!dut.sxm_sr_read_valid[segment_index] ||
                    dut.sxm_sr_read_data[segment_index*64 +: 64] !==
                    expected_input || !dut.sxm_sr_consume[segment_index]) begin
                    $display("ERROR read mapping h=%0d src_d=%0d segment=%0d",
                             hemisphere, src_direction, local_segment);
                    errors = errors + 1;
                end
                for (local_lane = 0; local_lane < LANES;
                     local_lane = local_lane + 1) begin
                    control_index = consume_lane_index(
                        hemisphere, src_direction, source_column, 0, 1,
                        local_segment, local_lane);
                    if (!dut.srf_consume[control_index]) begin
                        $display("ERROR consume slot1 expansion segment=%0d lane=%0d",
                                 local_segment, local_lane);
                        errors = errors + 1;
                    end
                end
            end

            // Adapter is combinational: read and consume are visible before
            // the same capture edge. That edge writes the result buffer while
            // SR downstream propagation observes consume.
            @(posedge clk_i);
            #1;
            transpose_cmd_valid_i = 2'b0;
            transpose_cmd_i = 192'b0;
            for (local_lane = 0; local_lane < LANES;
                 local_lane = local_lane + 1) begin
                state_index = state_lane_index(
                    hemisphere, src_direction,
                    src_direction ? 14 : 15, 0, 0, local_lane);
                if (srf_state_valid_o[state_index]) begin
                    $display("ERROR consume failed to block passive propagation lane=%0d",
                             local_lane);
                    errors = errors + 1;
                end
            end

            permute_command = make_command(
                2'd1, dst_direction[0], 5'd8, dst_direction[0], 5'd16,
                4'd0, 4'd8, 3'd0, 8'd0);
            @(negedge clk_i);
            permute_cmd_valid_i[hemisphere] = 1'b1;
            permute_cmd_i[hemisphere*96 +: 96] = permute_command;
            #1;
            for (local_segment = 0; local_segment < 16;
                 local_segment = local_segment + 1) begin
                segment_index = sxm_segment_index(
                    hemisphere, 0, local_segment);
                expected_output = transposed_segment(
                    seed, 0, local_segment);
                if (!dut.sxm_sr_write_valid[segment_index] ||
                    dut.sxm_sr_write_data[segment_index*64 +: 64] !==
                    expected_output) begin
                    $display("ERROR SXM producer segment=%0d", local_segment);
                    errors = errors + 1;
                end
                for (local_lane = 0; local_lane < LANES;
                     local_lane = local_lane + 1) begin
                    control_index = inject_lane_index(
                        hemisphere, dst_direction, output_column, 0, 1,
                        16 + local_segment, local_lane);
                    if (!dut.srf_inject_valid[control_index] ||
                        dut.srf_inject_data[control_index*8 +: 8] !==
                        expected_output[local_lane*8 +: 8]) begin
                        $display("ERROR producer slot1 expansion segment=%0d lane=%0d",
                                 local_segment, local_lane);
                        errors = errors + 1;
                    end
                end
            end

            // SXM write is a current-cycle producer candidate. SR commits it
            // only at this edge; there is no combinational next-state bypass.
            @(posedge clk_i);
            #1;
            permute_cmd_valid_i = 2'b0;
            permute_cmd_i = 192'b0;
            for (local_segment = 0; local_segment < 16;
                 local_segment = local_segment + 1) begin
                expected_output = transposed_segment(seed, 0, local_segment);
                for (local_lane = 0; local_lane < LANES;
                     local_lane = local_lane + 1) begin
                    state_index = state_lane_index(
                        hemisphere, dst_direction, output_column, 0,
                        16 + local_segment, local_lane);
                    if (!srf_state_valid_o[state_index] ||
                        srf_state_data_o[state_index*8 +: 8] !==
                        expected_output[local_lane*8 +: 8]) begin
                        $display("ERROR SR producer commit h=%0d dst_d=%0d s=%0d l=%0d",
                                 hemisphere, dst_direction,
                                 16 + local_segment, local_lane);
                        errors = errors + 1;
                    end
                end
            end
            if (srf_fabric_collision_o ||
                srf_fabric_invalid_consume_o) begin
                $display("ERROR unexpected SR diagnostic in direction flow");
                errors = errors + 1;
            end
        end
    endtask

    task run_partial_valid;
        reg [95:0] command_value;
        integer segment_index;
        begin
            reset_dut();
            drive_boundary_wave(0, 0, 8'h70, 1);
            advance_to_sxm_input(0);
            check_target_segment(0, 0, 0, 0, 8'h70, 0);
            command_value = make_command(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd8,
                4'd8, 4'd0, 3'd0, 8'd0);
            @(negedge clk_i);
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] = command_value;
            #1;
            segment_index = sxm_segment_index(0, 0, 0);
            if (dut.sxm_sr_read_valid[segment_index] !== 1'b0 ||
                sxm_transpose_input_invalid_o[0] !== 1'b1 ||
                dut.sxm_sr_consume[0 +: 16] !== 16'b0) begin
                $display("ERROR partial-lane valid behavior");
                errors = errors + 1;
            end
        end
    endtask

    task run_dual_hemisphere;
        integer hop;
        reg [95:0] command_west;
        reg [95:0] command_east;
        begin
            reset_dut();
            // Start hemi0 East, advance it to column13, then inject hemi1 West
            // so both physical SXM inputs become current in the same cycle.
            drive_boundary_wave(0, 0, 8'h21, 0);
            for (hop = 0; hop < 13; hop = hop + 1) begin
                @(posedge clk_i);
                #1;
            end
            drive_boundary_wave(1, 1, 8'h92, 0);
            check_target_segment(0, 0, 0, 0, 8'h21, 1);
            check_target_segment(1, 1, 0, 0, 8'h92, 1);

            command_east = make_command(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd8,
                4'd8, 4'd0, 3'd0, 8'd0);
            command_west = make_command(
                2'd0, 1'b1, 5'd0, 1'b1, 5'd8,
                4'd8, 4'd0, 3'd0, 8'd0);
            @(negedge clk_i);
            transpose_cmd_valid_i = 2'b11;
            transpose_cmd_i[0 +: 96] = command_east;
            transpose_cmd_i[96 +: 96] = command_west;
            #1;
            if (dut.sxm_sr_read_valid[0 +: 16] !== 16'hFFFF ||
                dut.sxm_sr_read_valid[64 +: 16] !== 16'hFFFF ||
                dut.sxm_sr_consume[0 +: 16] !== 16'hFFFF ||
                dut.sxm_sr_consume[64 +: 16] !== 16'hFFFF ||
                sxm_fault_valid_o !== 2'b00 || sxm_busy_o !== 2'b11) begin
                $display("ERROR dual-hemisphere independence");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b0;
        clear_stimulus();

        $display("RUN_TEST reset_idle");
        before_errors = errors;
        reset_dut();
        if (errors == before_errors) $display("SRF_SXM_RESET PASS");

        $display("RUN_TEST east_read_consume_write_cycle");
        before_errors = errors;
        run_direction_flow(0, 0, 0, 8'h10);
        if (errors == before_errors) begin
            $display("SRF_SXM_EAST_READ PASS");
            $display("SRF_SXM_CONSUME_MAPPING PASS");
            $display("SRF_SXM_EAST_WRITE PASS");
            $display("SRF_SXM_CYCLE_CONTRACT PASS");
        end

        $display("RUN_TEST west_read_consume_write");
        before_errors = errors;
        run_direction_flow(0, 1, 1, 8'h30);
        if (errors == before_errors) begin
            $display("SRF_SXM_WEST_READ PASS");
            $display("SRF_SXM_WEST_WRITE PASS");
        end

        $display("RUN_TEST partial_lane_valid");
        before_errors = errors;
        run_partial_valid();
        if (errors == before_errors) $display("SRF_SXM_PARTIAL_VALID PASS");

        $display("RUN_TEST four_direction_combinations");
        before_errors = errors;
        run_direction_flow(0, 0, 1, 8'h50);
        run_direction_flow(0, 1, 0, 8'h60);
        if (errors == before_errors)
            $display("SRF_SXM_DIRECTION_MATRIX PASS");

        $display("RUN_TEST hemisphere_independence");
        before_errors = errors;
        reset_dut();
        run_direction_flow(0, 0, 0, 8'h75);
        if (srf_state_valid_o[32768 +: 32768] !== 32768'b0 ||
            sxm_fault_valid_o[1] !== 1'b0) begin
            $display("ERROR idle hemisphere changed");
            errors = errors + 1;
        end
        run_dual_hemisphere();
        if (errors == before_errors)
            $display("SRF_SXM_HEMISPHERE_INDEPENDENCE PASS");

        if (errors == 0) begin
            $display("========================================");
            $display("SRF_SXM_INTEGRATION TEST_PASS");
            $display("========================================");
            $finish;
        end

        $display("========================================");
        $display("SRF_SXM_INTEGRATION TEST_FAIL errors=%0d", errors);
        $display("========================================");
        $fatal(1);
    end

endmodule
