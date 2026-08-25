`timescale 1ns/1ps

module tb_mem_sxm_input_boundary_e2e;

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
    integer mem_candidate_cycle;
    integer mem_commit_cycle;
    integer east_visible_cycle;
    integer west_commit_cycle;
    integer west_visible_cycle;
    integer tile;
    integer lane;
    integer stream;
    integer column;
    integer index;
    integer previous_index;
    integer segment_index;
    reg [255:0] row_data;
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
        begin
            make_sxm_cmd = 96'b0;
            make_sxm_cmd[1:0] = opcode;
            make_sxm_cmd[2] = src_direction;
            make_sxm_cmd[7:3] = src_base;
            make_sxm_cmd[8] = dst_direction;
            make_sxm_cmd[13:9] = dst_base;
            make_sxm_cmd[17:14] = 4'd8;
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

    function integer sxm_segment_index;
        input integer hemisphere;
        input integer superlane;
        input integer active_stream;
        begin
            sxm_segment_index =
                (hemisphere*4 + superlane)*16 + active_stream;
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
        input [7:0] lane_valid;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = boundary_lane_index(
                    hemisphere, direction, superlane,
                    stream_id, local_lane);
                srf_boundary_input_valid_i[local_index] =
                    lane_valid[local_lane];
                srf_boundary_input_data_i[local_index*8 +: 8] =
                    data[local_lane*8 +: 8];
            end
        end
    endtask

    task check_state_segment;
        input integer hemisphere;
        input integer direction;
        input integer sr_column;
        input integer superlane;
        input integer stream_id;
        input [63:0] data;
        input [7:0] lane_valid;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = state_lane_index(
                    hemisphere, direction, sr_column, superlane,
                    stream_id, local_lane);
                if (srf_state_valid_o[local_index] !==
                        lane_valid[local_lane] ||
                    srf_state_data_o[local_index*8 +: 8] !==
                        data[local_lane*8 +: 8]) begin
                    $display("ERROR SR state d=%0d c=%0d s=%0d l=%0d",
                             direction, sr_column, stream_id, local_lane);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task write_mem_row;
        integer local_tile;
        begin
            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 0, 0, 3,
                                 row_data[0 +: 64], 8'hff);
            @(posedge clk_i);
            #1;
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                @(negedge clk_i);
                clear_inputs();
                if (local_tile < 3)
                    set_boundary_segment(
                        0, 0, local_tile+1, 3,
                        row_data[(local_tile+1)*64 +: 64], 8'hff);
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

    task run_mem_east_path;
        integer local_column;
        integer local_lane;
        integer producer_bit;
        begin
            write_mem_row();
            // SR/control reset preserves the MEM SRAM contents.
            pulse_reset();

            @(negedge clk_i);
            clear_inputs();
            west_bank_issue_valid_i[0] = 1'b1;
            west_bank_issue_i[0 +: 32] =
                make_mem_cmd(OPCODE_READ, 1'b0, 5'd0, 15'd5);
            @(posedge clk_i);
            #1;
            mem_candidate_cycle = cycle_count;

            if (!dut.mem_producer_valid[0] ||
                dut.mem_producer_data[0 +: 64] !== BYTE_PATTERN ||
                dut.mem_producer_stream_dir[0] !== 1'b0 ||
                dut.mem_producer_stream_idx[0 +: 5] !== 5'd0 ||
                dut.mem_producer_boundary[0 +: 4] !== 4'd1) begin
                $display("ERROR MEM East producer metadata/data");
                errors = errors + 1;
            end
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                producer_bit = owner_lane_index(
                    0, 0, 1, 0, 0, 0, local_lane);
                if (!dut.mem_srf_inject_valid[producer_bit] ||
                    dut.mem_srf_inject_data[producer_bit*8 +: 8] !==
                        BYTE_PATTERN[local_lane*8 +: 8]) begin
                    $display("ERROR MEM producer0 lane=%0d", local_lane);
                    errors = errors + 1;
                end
            end

            clear_inputs();
            for (local_column = 1; local_column <= 14;
                 local_column = local_column + 1) begin
                @(posedge clk_i);
                #1;
                if (local_column == 1)
                    mem_commit_cycle = cycle_count;
                check_state_segment(0, 0, local_column, 0, 0,
                                    BYTE_PATTERN, 8'hff);
                if (local_column > 1) begin
                    previous_index = state_lane_index(
                        0, 0, local_column-1, 0, 0, 0);
                    if (|srf_state_valid_o[previous_index +: 8]) begin
                        $display("ERROR East bubble missing behind column=%0d",
                                 local_column);
                        errors = errors + 1;
                    end
                end
            end
            east_visible_cycle = cycle_count;

            command_value = make_sxm_cmd(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd8);
            @(negedge clk_i);
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] = command_value;
            #1;
            segment_index = sxm_segment_index(0, 0, 0);
            if (dut.sxm_sr_read_req[0 +: 6] !== 6'b000000 ||
                !dut.sxm_sr_read_valid[segment_index] ||
                dut.sxm_sr_read_data[segment_index*64 +: 64] !==
                    BYTE_PATTERN) begin
                $display("ERROR SXM East read interface");
                errors = errors + 1;
            end
            // Observation only: do not commit this incomplete Transpose wave.
            transpose_cmd_valid_i[0] = 1'b0;
            transpose_cmd_i[0 +: 96] = 96'b0;

            if (mem_commit_cycle !== mem_candidate_cycle + 1 ||
                east_visible_cycle !== mem_commit_cycle + 13) begin
                $display("ERROR East cycle contract candidate=%0d commit=%0d visible=%0d",
                         mem_candidate_cycle, mem_commit_cycle,
                         east_visible_cycle);
                errors = errors + 1;
            end
        end
    endtask

    task run_west_boundary_full;
        begin
            pulse_reset();
            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 1, 0, 0, BYTE_PATTERN, 8'hff);
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] =
                make_sxm_cmd(2'd0, 1'b1, 5'd0, 1'b1, 5'd8);
            @(posedge clk_i);
            #1;
            west_commit_cycle = cycle_count;
            west_visible_cycle = cycle_count;
            check_state_segment(0, 1, 15, 0, 0,
                                BYTE_PATTERN, 8'hff);
            index = state_lane_index(0, 1, 14, 0, 0, 0);
            if (|srf_state_valid_o[index +: 8]) begin
                $display("ERROR West data bypassed column15");
                errors = errors + 1;
            end
            segment_index = sxm_segment_index(0, 0, 0);
            if (dut.sxm_sr_read_req[0 +: 6] !== 6'b100000 ||
                !dut.sxm_sr_read_valid[segment_index] ||
                dut.sxm_sr_read_data[segment_index*64 +: 64] !==
                    BYTE_PATTERN) begin
                $display("ERROR SXM West boundary read interface");
                errors = errors + 1;
            end
            transpose_cmd_valid_i[0] = 1'b0;
            transpose_cmd_i[0 +: 96] = 96'b0;
            clear_inputs();
            if (west_visible_cycle !== west_commit_cycle) begin
                $display("ERROR West adapter added a cycle");
                errors = errors + 1;
            end
        end
    endtask

    task run_partial_valid;
        begin
            pulse_reset();
            @(negedge clk_i);
            clear_inputs();
            set_boundary_segment(0, 1, 0, 0, BYTE_PATTERN, 8'h7f);
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] =
                make_sxm_cmd(2'd0, 1'b1, 5'd0, 1'b1, 5'd8);
            @(posedge clk_i);
            #1;
            segment_index = sxm_segment_index(0, 0, 0);
            if (dut.sxm_sr_read_valid[segment_index] !== 1'b0 ||
                dut.sxm_sr_read_data[segment_index*64 +: 64] !==
                    BYTE_PATTERN) begin
                $display("ERROR partial valid or data padding behavior");
                errors = errors + 1;
            end
            transpose_cmd_valid_i[0] = 1'b0;
            transpose_cmd_i[0 +: 96] = 96'b0;
            clear_inputs();
        end
    endtask

    task run_consume_block;
        integer local_stream;
        integer local_lane;
        integer local_index;
        begin
            pulse_reset();
            @(negedge clk_i);
            clear_inputs();
            for (local_stream = 0; local_stream < 16;
                 local_stream = local_stream + 1)
                set_boundary_segment(
                    0, 1, 0, local_stream,
                    BYTE_PATTERN + local_stream, 8'hff);
            @(posedge clk_i);
            #1;

            @(negedge clk_i);
            clear_inputs();
            // The registered Transpose command advances to tile1 at the
            // tile0 consume edge. Supply the legal next superlane wave at
            // column15 so this focused consume test does not manufacture a
            // downstream input-invalid fault.
            for (local_stream = 0; local_stream < 16;
                 local_stream = local_stream + 1)
                set_boundary_segment(
                    0, 1, 1, local_stream,
                    64'h8887868584838281 + local_stream, 8'hff);
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] =
                make_sxm_cmd(2'd0, 1'b1, 5'd0, 1'b1, 5'd8);
            #1;
            if (dut.sxm_sr_read_valid[0 +: 16] !== 16'hffff ||
                dut.sxm_sr_consume[0 +: 16] !== 16'hffff ||
                dut.sxm_srf_consume === 131072'b0) begin
                $display("ERROR SXM successful consume request");
                errors = errors + 1;
            end
            @(posedge clk_i);
            transpose_cmd_valid_i[0] = 1'b0;
            #1;
            clear_inputs();
            for (local_stream = 0; local_stream < 16;
                 local_stream = local_stream + 1) begin
                for (local_lane = 0; local_lane < 8;
                     local_lane = local_lane + 1) begin
                    local_index = state_lane_index(
                        0, 1, 14, 0, local_stream, local_lane);
                    if (srf_state_valid_o[local_index]) begin
                        $display("ERROR consumed West segment propagated s=%0d l=%0d",
                                 local_stream, local_lane);
                        errors = errors + 1;
                    end
                end
            end
            if (srf_fabric_collision_o ||
                srf_fabric_invalid_consume_o || sxm_fault_valid_o !== 2'b0) begin
                $display("ERROR diagnostics during legal consume collision=%0b invalid_consume=%0b sxm_fault=%b input_invalid=%h buffer_full=%h",
                         srf_fabric_collision_o,
                         srf_fabric_invalid_consume_o,
                         sxm_fault_valid_o,
                         sxm_transpose_input_invalid_o,
                         sxm_transpose_buffer_full_o);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        cycle_count = 0;
        rst_ni = 1'b1;
        clear_inputs();
        row_data = {
            64'h3837363534333231,
            64'h2827262524232221,
            64'h1817161514131211,
            BYTE_PATTERN
        };

        $display("RUN_TEST mem_east_to_sxm");
        before_errors = errors;
        pulse_reset();
        run_mem_east_path();
        if (errors == before_errors)
            $display("MEM_EAST_TO_SXM PASS");

        $display("RUN_TEST sr_west_boundary_to_sxm");
        before_errors = errors;
        run_west_boundary_full();
        if (errors == before_errors) begin
            $display("SR_WEST_BOUNDARY_TO_SXM PASS");
            $display("SEGMENT_PACKING PASS");
        end

        $display("RUN_TEST segment_partial_valid");
        before_errors = errors;
        run_partial_valid();
        if (errors == before_errors)
            $display("SEGMENT_VALID PASS");

        $display("RUN_TEST passive_propagation_consume");
        before_errors = errors;
        run_consume_block();
        if (errors == before_errors)
            $display("PASSIVE_PROPAGATION PASS");

        if (mem_commit_cycle == mem_candidate_cycle + 1 &&
            east_visible_cycle == mem_commit_cycle + 13 &&
            west_visible_cycle == west_commit_cycle)
            $display("CYCLE_CONTRACT PASS");
        else begin
            $display("ERROR final cycle contract");
            errors = errors + 1;
        end

        if (mem_bank_fault_valid_o !== 208'b0 ||
            srf_fabric_collision_o || srf_fabric_invalid_consume_o ||
            system_fault_reserved_o !== 1'b0) begin
            $display("ERROR final integration diagnostics");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("================================");
            $display("MEM_SXM_INPUT_BOUNDARY_E2E TEST_PASS");
            $display("================================");
            $finish;
        end

        $display("================================");
        $display("MEM_SXM_INPUT_BOUNDARY_E2E TEST_FAIL errors=%0d", errors);
        $display("================================");
        $fatal(1);
    end

endmodule
