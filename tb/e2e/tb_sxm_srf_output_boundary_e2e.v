`timescale 1ns/1ps

module tb_sxm_srf_output_boundary_e2e;

    localparam P_TEST_DEPTH = 16;
    localparam [2:0] OPCODE_READ  = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;
    localparam [63:0] BYTE_PATTERN = 64'h0807060504030201;

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
    integer cycle_count;
    integer east_candidate_cycle;
    integer east_commit_cycle;
    integer east_visible_cycle;
    integer west_candidate_cycle;
    integer west_commit_cycle;
    integer west_consumer_visible_cycle;
    integer lane;
    integer stream;
    integer tile;
    integer hop;
    integer index;
    integer segment_index;
    integer mem_bit;
    integer sxm_bit;
    reg [255:0] mem_row_data;

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

    always @(posedge clk_i)
        cycle_count = cycle_count + 1;

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
        input [3:0] output_row;
        input [2:0] output_tile;
        input [7:0] phase_id;
        begin
            make_sxm_cmd = 96'b0;
            make_sxm_cmd[1:0] = opcode;
            make_sxm_cmd[2] = src_direction;
            make_sxm_cmd[7:3] = src_base;
            make_sxm_cmd[8] = dst_direction;
            make_sxm_cmd[13:9] = dst_base;
            make_sxm_cmd[17:14] = 4'd8;
            make_sxm_cmd[21:18] = output_row;
            make_sxm_cmd[24:22] = output_tile;
            make_sxm_cmd[32:25] = phase_id;
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
        input integer sr_column;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            state_lane_index =
                (((((hemisphere*2 + direction)*16 + sr_column)*4 +
                    superlane)*32 + stream_id)*8 + lane_id);
        end
    endfunction

    function integer owner_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer sr_column;
        input integer superlane;
        input integer owner;
        input integer stream_id;
        input integer lane_id;
        begin
            owner_lane_index =
                ((((((hemisphere*2 + direction)*16 + sr_column)*4 +
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

    function [7:0] matrix_byte;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            // Transposed output segment 0 reads lane0 from even input
            // streams 0,2,...14. Encode it as 01,02,...08 for every tile.
            if ((lane_id == 0) && ((stream_id & 1) == 0))
                matrix_byte = (stream_id/2) + 1;
            else
                matrix_byte = 8'h40 + superlane*8'h20 +
                              stream_id + lane_id;
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
                srf_fabric_collision_o || srf_fabric_invalid_consume_o ||
                mem_bank_fault_valid_o !== 208'b0 ||
                sxm_fault_valid_o !== 2'b0) begin
                $display("ERROR reset/idle state");
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
                srf_boundary_input_data_i[local_index*8 +: 8] =
                    data[local_lane*8 +: 8];
            end
        end
    endtask

    task set_matrix_tile;
        input integer superlane;
        integer local_stream;
        integer local_lane;
        integer local_index;
        begin
            for (local_stream = 0; local_stream < 16;
                 local_stream = local_stream + 1) begin
                for (local_lane = 0; local_lane < 8;
                     local_lane = local_lane + 1) begin
                    local_index = boundary_lane_index(
                        0, 0, superlane, local_stream, local_lane);
                    srf_boundary_input_valid_i[local_index] = 1'b1;
                    srf_boundary_input_data_i[local_index*8 +: 8] =
                        matrix_byte(superlane, local_stream, local_lane);
                end
            end
        end
    endtask

    task position_matrix_wave;
        integer local_tile;
        integer local_hop;
        begin
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                @(negedge clk_i);
                clear_inputs();
                set_matrix_tile(local_tile);
                @(posedge clk_i);
                #1;
            end
            clear_inputs();
            // After the four launch edges tile0 is at column3. Eleven more
            // registered hops place tile0..tile3 at columns14..11.
            for (local_hop = 0; local_hop < 11;
                 local_hop = local_hop + 1) begin
                @(posedge clk_i);
                #1;
            end
        end
    endtask

    task check_state_segment;
        input integer direction;
        input integer sr_column;
        input integer superlane;
        input integer stream_id;
        input [63:0] expected;
        input expected_valid;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = state_lane_index(
                    0, direction, sr_column, superlane,
                    stream_id, local_lane);
                if (srf_state_valid_o[local_index] !== expected_valid ||
                    (expected_valid &&
                     srf_state_data_o[local_index*8 +: 8] !==
                        expected[local_lane*8 +: 8])) begin
                    $display("ERROR state d=%0d c=%0d t=%0d s=%0d l=%0d",
                             direction, sr_column, superlane,
                             stream_id, local_lane);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task write_mem_seed_row;
        integer local_tile;
        begin
            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 0, 0, 3,
                                 mem_row_data[0 +: 64]);
            @(posedge clk_i);
            #1;
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                @(negedge clk_i);
                clear_inputs();
                if (local_tile < 3)
                    set_boundary_segment(
                        0, 0, local_tile+1, 3,
                        mem_row_data[(local_tile+1)*64 +: 64]);
                if (local_tile == 0) begin
                    west_bank_issue_valid_i[0] = 1'b1;
                    west_bank_issue_i[0 +: 32] =
                        make_mem_cmd(OPCODE_WRITE, 1'b0, 5'd3, 15'd5);
                end
                @(posedge clk_i);
                #1;
            end
            clear_inputs();
        end
    endtask

    task check_sxm_candidate;
        input integer direction;
        input integer target_column;
        integer local_lane;
        integer local_segment;
        integer local_bit;
        begin
            local_segment = sxm_segment_index(0, 0, 0);
            if (!dut.sxm_sr_write_valid[local_segment] ||
                dut.sxm_sr_write_sel[0 +: 6] !==
                    {direction[0], 5'd16} ||
                dut.sxm_sr_write_data[local_segment*64 +: 64] !==
                    BYTE_PATTERN) begin
                $display("ERROR SXM producer candidate d=%0d", direction);
                errors = errors + 1;
            end
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_bit = owner_lane_index(
                    0, direction, target_column, 0, 1, 16, local_lane);
                if (!dut.sxm_srf_inject_valid[local_bit] ||
                    dut.sxm_srf_inject_data[local_bit*8 +: 8] !==
                        BYTE_PATTERN[local_lane*8 +: 8]) begin
                    $display("ERROR SXM slot1 expansion d=%0d l=%0d",
                             direction, local_lane);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task run_east_output;
        integer local_lane;
        integer boundary_bit;
        begin
            position_matrix_wave();

            // MEM Read is issued with the Transpose capture so its registered
            // tile0 producer overlaps the following SXM Permute candidate.
            @(negedge clk_i);
            clear_inputs();
            west_bank_issue_valid_i[0] = 1'b1;
            west_bank_issue_i[0 +: 32] =
                make_mem_cmd(OPCODE_READ, 1'b0, 5'd5, 15'd5);
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd16,
                4'd0, 3'd0, 8'd0);
            @(posedge clk_i);
            transpose_cmd_valid_i[0] = 1'b0;
            #1;

            @(negedge clk_i);
            clear_inputs();
            permute_cmd_valid_i[0] = 1'b1;
            permute_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd1, 1'b0, 5'd0, 1'b0, 5'd16,
                4'd0, 3'd0, 8'd0);
            #1;
            east_candidate_cycle = cycle_count;
            check_sxm_candidate(0, 15);

            // Concurrent ownership check: MEM is active only on slot0 and
            // SXM is active only on slot1 in the same cycle.
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                mem_bit = owner_lane_index(0, 0, 1, 0, 0, 5, local_lane);
                sxm_bit = owner_lane_index(0, 0, 15, 0, 1, 16, local_lane);
                if (!dut.mem_srf_inject_valid[mem_bit] ||
                    !dut.sxm_srf_inject_valid[sxm_bit] ||
                    dut.sxm_srf_inject_valid[mem_bit] ||
                    dut.mem_srf_inject_valid[sxm_bit]) begin
                    $display("ERROR producer slot isolation lane=%0d",
                             local_lane);
                    errors = errors + 1;
                end
            end
            if (srf_fabric_collision_o) begin
                $display("ERROR collision in disjoint slot/column traffic");
                errors = errors + 1;
            end

            @(posedge clk_i);
            permute_cmd_valid_i[0] = 1'b0;
            #1;
            east_commit_cycle = cycle_count;
            east_visible_cycle = cycle_count;
            check_state_segment(0, 15, 0, 16,
                                BYTE_PATTERN, 1'b1);
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                boundary_bit = boundary_lane_index(
                    0, 0, 0, 16, local_lane);
                if (!srf_boundary_output_valid_o[boundary_bit] ||
                    srf_boundary_output_data_o[boundary_bit*8 +: 8] !==
                        BYTE_PATTERN[local_lane*8 +: 8]) begin
                    $display("ERROR East downstream boundary lane=%0d",
                             local_lane);
                    errors = errors + 1;
                end
            end
            if (east_commit_cycle !== east_candidate_cycle + 1 ||
                east_visible_cycle !== east_commit_cycle) begin
                $display("ERROR East cycle contract candidate=%0d commit=%0d visible=%0d",
                         east_candidate_cycle, east_commit_cycle,
                         east_visible_cycle);
                errors = errors + 1;
            end
            clear_inputs();
        end
    endtask

    task run_west_output_and_consume;
        integer local_lane;
        integer consume_cell;
        begin
            pulse_reset();
            position_matrix_wave();

            // Capture tile0, then allow the registered command to capture
            // tile1 on the next edge. Both buffers produce the same explicit
            // byte pattern and are used for two consecutive West candidates.
            @(negedge clk_i);
            clear_inputs();
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd0, 1'b0, 5'd0, 1'b1, 5'd16,
                4'd0, 3'd0, 8'd0);
            @(posedge clk_i);
            transpose_cmd_valid_i[0] = 1'b0;
            #1;
            // Allow the registered Transpose command to capture tile1..tile3
            // so an ALL-tile Permute has four legal source buffers.
            repeat (3) begin
                @(posedge clk_i);
                #1;
            end

            // Phase0 maps source buffer0 to destination superlane0.
            @(negedge clk_i);
            clear_inputs();
            permute_cmd_valid_i[0] = 1'b1;
            permute_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd1, 1'b0, 5'd0, 1'b1, 5'd16,
                4'd0, 3'd4, 8'd0);
            #1;
            check_sxm_candidate(1, 14);
            @(posedge clk_i);
            permute_cmd_valid_i[0] = 1'b0;
            #1;
            check_state_segment(1, 14, 0, 16,
                                BYTE_PATTERN, 1'b1);

            // Phase1 maps source buffer1 to the same destination. This second
            // copy is the one consumed after reaching MEM boundary13.
            @(negedge clk_i);
            clear_inputs();
            permute_cmd_valid_i[0] = 1'b1;
            permute_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd1, 1'b0, 5'd0, 1'b1, 5'd16,
                4'd0, 3'd4, 8'd1);
            #1;
            west_candidate_cycle = cycle_count;
            check_sxm_candidate(1, 14);
            @(posedge clk_i);
            permute_cmd_valid_i[0] = 1'b0;
            #1;
            west_commit_cycle = cycle_count;
            check_state_segment(1, 14, 0, 16,
                                BYTE_PATTERN, 1'b1);
            check_state_segment(1, 13, 0, 16,
                                BYTE_PATTERN, 1'b1);

            // Issue group12/bank0 West Write while the leading copy is at
            // boundary13. Its registered consume pulse aligns with the
            // trailing copy one cycle later.
            @(negedge clk_i);
            clear_inputs();
            west_bank_issue_valid_i[96] = 1'b1;
            west_bank_issue_i[96*32 +: 32] =
                make_mem_cmd(OPCODE_WRITE, 1'b1, 5'd16, 15'd6);
            // A third legal copy commits at column14 on this edge. It keeps
            // tile1 valid at boundary13 when the registered MEM command
            // advances beyond tile0, avoiding a fabricated pipeline fault.
            permute_cmd_valid_i[0] = 1'b1;
            permute_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd1, 1'b0, 5'd0, 1'b1, 5'd16,
                4'd0, 3'd4, 8'd2);
            @(posedge clk_i);
            permute_cmd_valid_i[0] = 1'b0;
            #1;
            west_consumer_visible_cycle = cycle_count;
            consume_cell = mem_boundary_cell(0, 13, 1, 16, 0);
            if (!dut.mem_boundary_consume[consume_cell]) begin
                $display("ERROR MEM downstream consume candidate");
                errors = errors + 1;
            end
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                index = owner_lane_index(
                    0, 1, 13, 0, 0, 16, local_lane);
                if (!dut.srf_consume[index]) begin
                    $display("ERROR consumer0 mapping lane=%0d", local_lane);
                    errors = errors + 1;
                end
            end
            check_state_segment(1, 13, 0, 16,
                                BYTE_PATTERN, 1'b1);

            clear_inputs();
            @(posedge clk_i);
            #1;
            // The leading copy has advanced to column11. The trailing copy
            // was masked at column13 and therefore never enters column12.
            check_state_segment(1, 11, 0, 16,
                                BYTE_PATTERN, 1'b1);
            check_state_segment(1, 12, 0, 16,
                                BYTE_PATTERN, 1'b0);
            if (west_commit_cycle !== west_candidate_cycle + 1 ||
                west_consumer_visible_cycle !== west_commit_cycle + 1) begin
                $display("ERROR West cycle contract candidate=%0d commit=%0d consumer=%0d",
                         west_candidate_cycle, west_commit_cycle,
                         west_consumer_visible_cycle);
                errors = errors + 1;
            end
            if (srf_fabric_collision_o || srf_fabric_invalid_consume_o ||
                mem_bank_fault_valid_o !== 208'b0 ||
                sxm_fault_valid_o !== 2'b0) begin
                $display("ERROR West legal-path diagnostics collision=%0b invalid=%0b mem=%0b sxm=%0b",
                         srf_fabric_collision_o,
                         srf_fabric_invalid_consume_o,
                         |mem_bank_fault_valid_o, |sxm_fault_valid_o);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        cycle_count = 0;
        rst_ni = 1'b1;
        clear_inputs();
        mem_row_data = {
            64'hD8D7D6D5D4D3D2D1,
            64'hC8C7C6C5C4C3C2C1,
            64'hB8B7B6B5B4B3B2B1,
            64'hA8A7A6A5A4A3A2A1
        };

        pulse_reset();
        write_mem_seed_row();
        pulse_reset();

        $display("RUN_TEST sxm_east_output_to_srf");
        before_errors = errors;
        run_east_output();
        if (errors == before_errors) begin
            $display("SXM_EAST_OUTPUT_TO_SRF PASS");
            $display("SLOT_ISOLATION PASS");
            $display("DATA_PACKING PASS");
            $display("VALID_CHECK PASS");
        end

        $display("RUN_TEST sxm_west_output_to_srf_consumer");
        before_errors = errors;
        run_west_output_and_consume();
        if (errors == before_errors) begin
            $display("SXM_WEST_OUTPUT_TO_SRF PASS");
            $display("CONSUME_PROPAGATION PASS");
        end

        if (east_commit_cycle == east_candidate_cycle + 1 &&
            east_visible_cycle == east_commit_cycle &&
            west_commit_cycle == west_candidate_cycle + 1 &&
            west_consumer_visible_cycle == west_commit_cycle + 1)
            $display("CYCLE_CONTRACT PASS");
        else begin
            $display("ERROR final cycle contract");
            errors = errors + 1;
        end

        if (system_fault_reserved_o !== 1'b0 ||
            srf_fabric_collision_o || srf_fabric_invalid_consume_o ||
            mem_bank_fault_valid_o !== 208'b0 ||
            sxm_fault_valid_o !== 2'b0) begin
            $display("ERROR final diagnostics");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("================================");
            $display("SXM_SRF_OUTPUT_BOUNDARY_E2E TEST_PASS");
            $display("================================");
            $finish;
        end

        $display("================================");
        $display("SXM_SRF_OUTPUT_BOUNDARY_E2E TEST_FAIL errors=%0d", errors);
        $display("================================");
        $fatal(1);
    end

endmodule
