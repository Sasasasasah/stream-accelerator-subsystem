`timescale 1ns/1ps

module tb_srf_mem_sxm_integration;

    localparam P_TEST_DEPTH = 16;
    localparam [2:0] OPCODE_READ = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;

    reg clk_i;
    reg rst_ni;
    reg [32767:0] srf_boundary_input_data_i;
    reg [4095:0] srf_boundary_input_valid_i;
    reg [103:0] west_bank_issue_valid_i;
    reg [3327:0] west_bank_issue_i;
    reg [103:0] east_bank_issue_valid_i;
    reg [3327:0] east_bank_issue_i;
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
    wire [207:0] mem_bank_fault_valid_o;
    wire [623:0] mem_bank_fault_code_o;
    wire [25:0] mem_group_fault_valid_o;
    wire [1:0] mem_hemisphere_fault_valid_o;
    wire [25:0] mem_group_busy_o;
    wire [1:0] mem_hemisphere_busy_o;
    wire [1:0] sxm_fault_valid_o;
    wire [7:0] sxm_transpose_input_invalid_o;
    wire [7:0] sxm_transpose_buffer_full_o;
    wire [1:0] sxm_permute_phase_fault_o;
    wire [1:0] sxm_permute_selector_fault_o;
    wire [1:0] sxm_permute_buffer_not_ready_o;
    wire [1:0] sxm_busy_o;
    wire system_fault_reserved_o;

    integer errors;
    integer before_errors;
    integer tile;
    integer lane;
    integer stream;
    integer hop;
    integer bit_index;
    integer segment_index;
    reg [255:0] row_data;
    reg [63:0] expected_segment;
    reg [95:0] command_value;

    srf_mem_sxm_integration_top #(
        .P_MEM_BANK_DEPTH_ROWS(P_TEST_DEPTH)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .srf_boundary_input_data_i(srf_boundary_input_data_i),
        .srf_boundary_input_valid_i(srf_boundary_input_valid_i),
        .srf_boundary_output_data_o(srf_boundary_output_data_o),
        .srf_boundary_output_valid_o(srf_boundary_output_valid_o),
        .west_bank_issue_valid_i(west_bank_issue_valid_i),
        .west_bank_issue_i(west_bank_issue_i),
        .east_bank_issue_valid_i(east_bank_issue_valid_i),
        .east_bank_issue_i(east_bank_issue_i),
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
        .mem_bank_fault_valid_o(mem_bank_fault_valid_o),
        .mem_bank_fault_code_o(mem_bank_fault_code_o),
        .mem_group_fault_valid_o(mem_group_fault_valid_o),
        .mem_hemisphere_fault_valid_o(mem_hemisphere_fault_valid_o),
        .mem_group_busy_o(mem_group_busy_o),
        .mem_hemisphere_busy_o(mem_hemisphere_busy_o),
        .sxm_fault_valid_o(sxm_fault_valid_o),
        .sxm_transpose_input_invalid_o(sxm_transpose_input_invalid_o),
        .sxm_transpose_buffer_full_o(sxm_transpose_buffer_full_o),
        .sxm_permute_phase_fault_o(sxm_permute_phase_fault_o),
        .sxm_permute_selector_fault_o(sxm_permute_selector_fault_o),
        .sxm_permute_buffer_not_ready_o(sxm_permute_buffer_not_ready_o),
        .sxm_busy_o(sxm_busy_o),
        .system_fault_reserved_o(system_fault_reserved_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [31:0] make_mem_cmd;
        input [2:0] opcode;
        input direction;
        input [4:0] stream_index;
        input [14:0] row;
        begin
            make_mem_cmd = 32'b0;
            make_mem_cmd[2:0] = opcode;
            make_mem_cmd[8:3] = {direction, stream_index};
            make_mem_cmd[29:15] = row;
        end
    endfunction

    function [95:0] make_sxm_cmd;
        input [1:0] opcode;
        input src_direction;
        input [4:0] src_base;
        input dst_direction;
        input [4:0] dst_base;
        input [3:0] input_row;
        input [3:0] output_row;
        input [2:0] output_tile;
        input [7:0] phase_id;
        reg [95:0] value;
        begin
            value = 96'b0;
            value[1:0] = opcode;
            value[2] = src_direction;
            value[7:3] = src_base;
            value[8] = dst_direction;
            value[13:9] = dst_base;
            value[17:14] = input_row;
            value[21:18] = output_row;
            value[24:22] = output_tile;
            value[32:25] = phase_id;
            make_sxm_cmd = value;
        end
    endfunction

    function integer boundary_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            boundary_lane_index =
                ((((hemisphere*2 + direction)*4 + superlane)*32 +
                   stream_id)*8 + lane_id);
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
                (((((hemisphere*2 + direction)*16 + column)*4 +
                    superlane)*32 + stream_id)*8 + lane_id);
        end
    endfunction

    function integer owner_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer owner;
        input integer stream_id;
        input integer lane_id;
        begin
            owner_lane_index =
                ((((((hemisphere*2 + direction)*16 + column)*4 +
                     superlane)*2 + owner)*32 + stream_id)*8 + lane_id);
        end
    endfunction

    function integer mem_boundary_cell;
        input integer hemisphere;
        input integer boundary;
        input integer direction;
        input integer stream_id;
        input integer tile_id;
        begin
            mem_boundary_cell = hemisphere*3584 + boundary*256 +
                                direction*128 + stream_id*4 + tile_id;
        end
    endfunction

    function integer sxm_segment_index;
        input integer hemisphere;
        input integer superlane;
        input integer active_stream;
        begin
            sxm_segment_index =
                (hemisphere*4 + superlane)*16 + active_stream;
        end
    endfunction

    function [7:0] sxm_source_byte;
        input [7:0] seed;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            sxm_source_byte = seed + superlane*8'h40 +
                              stream_id*8 + lane_id;
        end
    endfunction

    function [63:0] sxm_transposed_segment;
        input [7:0] seed;
        input integer output_stream;
        integer local_lane;
        integer plane;
        integer output_row;
        reg [63:0] value;
        begin
            value = 64'b0;
            plane = output_stream % 2;
            output_row = output_stream / 2;
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                value[local_lane*8 +: 8] = sxm_source_byte(
                    seed, 0, 2*local_lane + plane, output_row);
            end
            sxm_transposed_segment = value;
        end
    endfunction

    task clear_inputs;
        begin
            srf_boundary_input_data_i = 32768'b0;
            srf_boundary_input_valid_i = 4096'b0;
            west_bank_issue_valid_i = 104'b0;
            west_bank_issue_i = 3328'b0;
            east_bank_issue_valid_i = 104'b0;
            east_bank_issue_i = 3328'b0;
            transpose_cmd_valid_i = 2'b0;
            transpose_cmd_i = 192'b0;
            permute_cmd_valid_i = 2'b0;
            permute_cmd_i = 192'b0;
        end
    endtask

    task pulse_reset;
        begin
            @(negedge clk_i);
            clear_inputs();
            rst_ni = 1'b0;
            repeat (2) @(posedge clk_i);
            #1;
            if (srf_state_valid_o !== 65536'b0 ||
                mem_hemisphere_busy_o !== 2'b0 || sxm_busy_o !== 2'b0 ||
                dut.srf_consume !== 131072'b0 ||
                dut.srf_inject_valid !== 131072'b0 ||
                srf_fabric_collision_o ||
                srf_fabric_invalid_consume_o ||
                mem_bank_fault_valid_o !== 208'b0 ||
                sxm_fault_valid_o !== 2'b0) begin
                $display("ERROR combined reset/idle");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            #1;
        end
    endtask

    task set_boundary_segment;
        input integer hemisphere;
        input integer direction;
        input integer superlane;
        input integer stream_id;
        input [63:0] data;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = boundary_lane_index(
                    hemisphere, direction, superlane,
                    stream_id, local_lane);
                srf_boundary_input_valid_i[local_index] = 1'b1;
                srf_boundary_input_data_i[
                    local_index*8 +: 8] = data[local_lane*8 +: 8];
            end
        end
    endtask

    task set_sxm_tile;
        input integer hemisphere;
        input integer superlane;
        input [7:0] seed;
        integer local_stream;
        integer local_lane;
        integer local_index;
        begin
            for (local_stream = 0; local_stream < 16;
                 local_stream = local_stream + 1) begin
                for (local_lane = 0; local_lane < 8;
                     local_lane = local_lane + 1) begin
                    local_index = boundary_lane_index(
                        hemisphere, 0, superlane,
                        local_stream, local_lane);
                    srf_boundary_input_valid_i[local_index] = 1'b1;
                    srf_boundary_input_data_i[
                        local_index*8 +: 8] = sxm_source_byte(
                            seed, superlane, local_stream, local_lane);
                end
            end
        end
    endtask

    task position_sxm_east_wave;
        input integer hemisphere;
        input [7:0] seed;
        input integer target_column;
        integer local_tile;
        integer local_hop;
        begin
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                @(negedge clk_i);
                srf_boundary_input_data_i = 32768'b0;
                srf_boundary_input_valid_i = 4096'b0;
                set_sxm_tile(hemisphere, local_tile, seed);
                @(posedge clk_i);
                #1;
            end
            srf_boundary_input_data_i = 32768'b0;
            srf_boundary_input_valid_i = 4096'b0;
            for (local_hop = 0; local_hop < target_column-3;
                 local_hop = local_hop + 1) begin
                @(posedge clk_i);
                #1;
            end
        end
    endtask

    task position_sxm_concurrent_wave;
        input integer hemisphere;
        input [7:0] seed;
        integer wave_step;
        integer local_hop;
        begin
            // Two consecutive tile0 waves are required because MEM reports
            // normal-Write consume as a registered one-cycle pulse. The first
            // tile0 wave establishes the issue-edge state; the second reaches
            // column14 in the following cycle and aligns with that pulse.
            for (wave_step = 0; wave_step < 4;
                 wave_step = wave_step + 1) begin
                @(negedge clk_i);
                srf_boundary_input_data_i = 32768'b0;
                srf_boundary_input_valid_i = 4096'b0;
                if (wave_step < 2)
                    set_sxm_tile(hemisphere, 0, seed);
                else
                    set_sxm_tile(hemisphere, wave_step-1, seed);
                @(posedge clk_i);
                #1;
            end
            srf_boundary_input_data_i = 32768'b0;
            srf_boundary_input_valid_i = 4096'b0;
            for (local_hop = 0; local_hop < 10;
                 local_hop = local_hop + 1) begin
                @(posedge clk_i);
                #1;
            end
        end
    endtask

    task check_segment_state;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer stream_id;
        input [63:0] expected;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = state_lane_index(
                    hemisphere, direction, column, superlane,
                    stream_id, local_lane);
                if (!srf_state_valid_o[local_index] ||
                    srf_state_data_o[local_index*8 +: 8] !==
                        expected[local_lane*8 +: 8]) begin
                    $display("ERROR state h=%0d d=%0d c=%0d t=%0d s=%0d l=%0d",
                             hemisphere, direction, column, superlane,
                             stream_id, local_lane);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_column_isolation;
        integer h;
        integer d;
        integer c;
        integer t;
        integer base;
        begin
            for (h = 0; h < 2; h = h + 1) begin
                for (d = 0; d < 2; d = d + 1) begin
                    for (c = 0; c < 16; c = c + 1) begin
                        for (t = 0; t < 4; t = t + 1) begin
                            base = (((h*2+d)*16+c)*4+t)*2*256;
                            if (c >= 14 &&
                                (dut.mem_srf_consume[base +: 256] !== 256'b0 ||
                                 dut.mem_srf_inject_valid[base +: 256] !== 256'b0)) begin
                                $display("ERROR MEM escaped column range c=%0d", c);
                                errors = errors + 1;
                            end
                            if (c < 14 &&
                                (dut.sxm_srf_consume[base+256 +: 256] !== 256'b0 ||
                                 dut.sxm_srf_inject_valid[base+256 +: 256] !== 256'b0)) begin
                                $display("ERROR SXM escaped column range c=%0d", c);
                                errors = errors + 1;
                            end
                        end
                    end
                end
            end
        end
    endtask

    task mem_write_row;
        input [4:0] stream_id;
        input [14:0] row;
        input [255:0] data;
        input integer check_sxm_idle;
        integer local_tile;
        integer local_lane;
        begin
            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 0, 0, stream_id, data[0 +: 64]);
            @(posedge clk_i);
            #1;
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                @(negedge clk_i);
                clear_inputs();
                if (local_tile < 3)
                    set_boundary_segment(
                        0, 0, local_tile+1, stream_id,
                        data[(local_tile+1)*64 +: 64]);
                if (local_tile == 0) begin
                    west_bank_issue_valid_i[0] = 1'b1;
                    west_bank_issue_i[0 +: 32] =
                        make_mem_cmd(OPCODE_WRITE, 1'b0, stream_id, row);
                end
                #1;
                if (check_sxm_idle != 0 &&
                    (dut.sxm_srf_consume !== 131072'b0 ||
                     dut.sxm_srf_inject_valid !== 131072'b0)) begin
                    $display("ERROR SXM slot active during MEM-only write");
                    errors = errors + 1;
                end
                @(posedge clk_i);
                #1;
            end
            clear_inputs();
        end
    endtask

    task mem_read_row;
        input [4:0] stream_id;
        input [14:0] row;
        input [255:0] data;
        input integer check_sxm_idle;
        integer local_tile;
        integer local_lane;
        integer local_bit;
        begin
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                @(negedge clk_i);
                clear_inputs();
                if (local_tile == 0) begin
                    west_bank_issue_valid_i[0] = 1'b1;
                    west_bank_issue_i[0 +: 32] =
                        make_mem_cmd(OPCODE_READ, 1'b0, stream_id, row);
                end
                @(posedge clk_i);
                #1;
                if (!dut.mem_producer_valid[local_tile] ||
                    dut.mem_producer_data[local_tile*64 +: 64] !==
                        data[local_tile*64 +: 64]) begin
                    $display("ERROR MEM read tile=%0d", local_tile);
                    errors = errors + 1;
                end
                for (local_lane = 0; local_lane < 8;
                     local_lane = local_lane + 1) begin
                    local_bit = owner_lane_index(
                        0, 0, 1, local_tile, 0, stream_id, local_lane);
                    if (!dut.srf_inject_valid[local_bit]) begin
                        $display("ERROR MEM slot0 producer tile=%0d lane=%0d",
                                 local_tile, local_lane);
                        errors = errors + 1;
                    end
                end
                if (check_sxm_idle != 0 &&
                    dut.sxm_srf_inject_valid !== 131072'b0) begin
                    $display("ERROR SXM slot active during MEM-only read");
                    errors = errors + 1;
                end
                if (local_tile > 0)
                    check_segment_state(
                        0, 0, 1, local_tile-1, stream_id,
                        data[(local_tile-1)*64 +: 64]);
            end
            @(negedge clk_i);
            clear_inputs();
            @(posedge clk_i);
            #1;
            check_segment_state(0, 0, 1, 3, stream_id,
                                data[3*64 +: 64]);
        end
    endtask

    task sxm_only_flow;
        input [7:0] seed;
        integer local_stream;
        integer local_lane;
        integer local_bit;
        begin
            position_sxm_east_wave(0, seed, 14);
            @(negedge clk_i);
            clear_inputs();
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd8,
                4'd8, 4'd0, 3'd0, 8'd0);
            #1;
            if (dut.sxm_sr_consume[0 +: 16] !== 16'hFFFF ||
                dut.mem_srf_consume !== 131072'b0) begin
                $display("ERROR SXM-only consume/slot isolation");
                errors = errors + 1;
            end
            @(posedge clk_i);
            #1;

            @(negedge clk_i);
            clear_inputs();
            permute_cmd_valid_i[0] = 1'b1;
            permute_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd1, 1'b0, 5'd8, 1'b0, 5'd16,
                4'd0, 4'd8, 3'd0, 8'd0);
            #1;
            if (dut.sxm_sr_write_valid[0 +: 16] !== 16'hFFFF ||
                dut.mem_srf_inject_valid !== 131072'b0) begin
                $display("ERROR SXM-only producer/slot isolation");
                errors = errors + 1;
            end
            check_column_isolation();
            @(posedge clk_i);
            #1;
            for (local_stream = 0; local_stream < 16;
                 local_stream = local_stream + 1) begin
                expected_segment = sxm_transposed_segment(seed, local_stream);
                check_segment_state(0, 0, 15, 0, 16+local_stream,
                                    expected_segment);
            end
        end
    endtask

    task concurrent_consume;
        input integer sxm_hemisphere;
        input [7:0] seed;
        integer local_tile;
        integer local_lane;
        integer mem_bit;
        integer sxm_bit;
        begin
            position_sxm_concurrent_wave(sxm_hemisphere, seed);
            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 0, 0, 4,
                                 64'h1716151413121110);
            @(posedge clk_i);
            #1;

            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 0, 0, 4,
                                 64'h1716151413121110);
            set_boundary_segment(0, 0, 1, 4,
                                 64'h2726252423222120);
            west_bank_issue_valid_i[0] = 1'b1;
            west_bank_issue_i[0 +: 32] =
                make_mem_cmd(OPCODE_WRITE, 1'b0, 5'd4, 15'd6);
            @(posedge clk_i);
            #1;

            // MEM tile0 consume is now a registered pulse. The second SXM
            // tile0 wave is current at column14, so issuing Transpose here
            // makes both consumers active for the same SR commit edge.
            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 0, 1, 4,
                                 64'h2726252423222120);
            set_boundary_segment(0, 0, 2, 4,
                                 64'h3736353433323130);
            transpose_cmd_valid_i[sxm_hemisphere] = 1'b1;
            transpose_cmd_i[sxm_hemisphere*96 +: 96] = make_sxm_cmd(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd8,
                4'd8, 4'd0, 3'd0, 8'd0);
            #1;
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                mem_bit = owner_lane_index(0,0,0,0,0,4,local_lane);
                sxm_bit = owner_lane_index(
                    sxm_hemisphere,0,14,0,1,0,local_lane);
                if (!dut.srf_consume[mem_bit] ||
                    !dut.srf_consume[sxm_bit]) begin
                    $display("ERROR concurrent consume lane=%0d mem=%0b sxm=%0b",
                             local_lane, dut.srf_consume[mem_bit],
                             dut.srf_consume[sxm_bit]);
                    errors = errors + 1;
                end
            end
            check_column_isolation();
            @(posedge clk_i);
            // The command is a one-cycle issue pulse. Drop it immediately
            // after the accepting edge so post-edge diagnostics observe the
            // next-cycle interface state, not a repeated tile0 request.
            transpose_cmd_valid_i[sxm_hemisphere] = 1'b0;
            #1;
            clear_inputs();
        end
    endtask

    task concurrent_produce;
        input [7:0] seed;
        integer local_lane;
        integer mem_bit;
        integer sxm_bit;
        begin
            position_sxm_east_wave(0, seed, 14);
            @(negedge clk_i);
            clear_inputs();
            west_bank_issue_valid_i[0] = 1'b1;
            west_bank_issue_i[0 +: 32] =
                make_mem_cmd(OPCODE_READ, 1'b0, 5'd9, 15'd5);
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd8,
                4'd8, 4'd0, 3'd0, 8'd0);
            @(posedge clk_i);
            #1;

            @(negedge clk_i);
            clear_inputs();
            permute_cmd_valid_i[0] = 1'b1;
            permute_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd1, 1'b0, 5'd8, 1'b0, 5'd16,
                4'd0, 4'd8, 3'd0, 8'd0);
            #1;
            expected_segment = sxm_transposed_segment(seed, 0);
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                mem_bit = owner_lane_index(0,0,1,0,0,9,local_lane);
                sxm_bit = owner_lane_index(0,0,15,0,1,16,local_lane);
                if (!dut.srf_inject_valid[mem_bit] ||
                    !dut.srf_inject_valid[sxm_bit] ||
                    dut.srf_inject_data[mem_bit*8 +: 8] !==
                        row_data[local_lane*8 +: 8] ||
                    dut.srf_inject_data[sxm_bit*8 +: 8] !==
                        expected_segment[local_lane*8 +: 8]) begin
                    $display("ERROR concurrent producer lane=%0d", local_lane);
                    errors = errors + 1;
                end
            end
            check_column_isolation();
            if (srf_fabric_collision_o) begin
                $display("ERROR legal concurrent producers collided");
                errors = errors + 1;
            end
            @(posedge clk_i);
            #1;
            check_segment_state(0,0,1,0,9,row_data[0 +: 64]);
            check_segment_state(0,0,15,0,16,expected_segment);
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b1;
        clear_inputs();
        row_data = {
            64'hD7D6D5D4D3D2D1D0,
            64'hC7C6C5C4C3C2C1C0,
            64'hB7B6B5B4B3B2B1B0,
            64'hA7A6A5A4A3A2A1A0
        };

        $display("RUN_TEST combined_reset");
        before_errors = errors;
        pulse_reset();
        if (errors == before_errors) $display("COMBINED_RESET PASS");

        $display("RUN_TEST combined_mem_only");
        before_errors = errors;
        mem_write_row(5'd3, 15'd5, row_data, 1);
        pulse_reset();
        mem_read_row(5'd9, 15'd5, row_data, 1);
        check_column_isolation();
        if (errors == before_errors) $display("COMBINED_MEM_ONLY PASS");

        $display("RUN_TEST combined_sxm_only");
        before_errors = errors;
        pulse_reset();
        sxm_only_flow(8'h20);
        if (errors == before_errors) $display("COMBINED_SXM_ONLY PASS");

        $display("RUN_TEST combined_concurrent_consume_same_hemisphere");
        before_errors = errors;
        pulse_reset();
        concurrent_consume(0, 8'h50);
        if (errors == before_errors) begin
            $display("COMBINED_CONCURRENT_CONSUME PASS");
            $display("COMBINED_SAME_HEMISPHERE_PARALLEL PASS");
        end

        $display("RUN_TEST combined_concurrent_produce");
        before_errors = errors;
        pulse_reset();
        concurrent_produce(8'h70);
        if (errors == before_errors) begin
            $display("COMBINED_CONCURRENT_PRODUCE PASS");
            $display("COMBINED_CYCLE_CONTRACT PASS");
        end

        $display("RUN_TEST combined_dual_hemisphere_parallel");
        before_errors = errors;
        pulse_reset();
        concurrent_consume(1, 8'h90);
        if (errors == before_errors)
            $display("COMBINED_DUAL_HEMISPHERE_PARALLEL PASS");

        before_errors = errors;
        check_column_isolation();
        if (errors == before_errors) begin
            $display("COMBINED_SLOT_ISOLATION PASS");
            $display("COMBINED_COLUMN_ISOLATION PASS");
        end

        if (mem_bank_fault_valid_o !== 208'b0 ||
            sxm_fault_valid_o !== 2'b0 || srf_fabric_collision_o ||
            srf_fabric_invalid_consume_o ||
            system_fault_reserved_o !== 1'b0) begin
            $display("ERROR final combined diagnostics mem_fault=%0b sxm_fault=%0b collision=%0b invalid_consume=%0b",
                     |mem_bank_fault_valid_o, |sxm_fault_valid_o,
                     srf_fabric_collision_o,
                     srf_fabric_invalid_consume_o);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("========================================");
            $display("SRF_MEM_SXM_COMBINED_INTEGRATION TEST_PASS");
            $display("========================================");
            $finish;
        end

        $display("========================================");
        $display("SRF_MEM_SXM_COMBINED_INTEGRATION TEST_FAIL errors=%0d", errors);
        $display("========================================");
        $fatal(1);
    end

endmodule
