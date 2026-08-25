`timescale 1ns/1ps

module tb_mem_srf_sxm_loopback_e2e;

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
    integer sxm_input_cycle;
    integer sxm_candidate_cycle;
    integer sxm_commit_cycle;
    integer consumer_cycle;
    integer tile;
    integer stream;
    integer lane;
    integer column;
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

    function integer sxm_segment_index;
        input integer hemisphere;
        input integer superlane;
        input integer active_stream;
        begin
            sxm_segment_index =
                (hemisphere*4 + superlane)*16 + active_stream;
        end
    endfunction

    function [7:0] auxiliary_byte;
        input integer superlane;
        input integer stream_id;
        input integer lane_id;
        begin
            // Output segment0 reads lane0 of streams 0,2,...14. Stream0 is
            // supplied by MEM; even auxiliary streams encode bytes 02..08.
            if ((lane_id == 0) && ((stream_id & 1) == 0))
                auxiliary_byte = (stream_id/2) + 1;
            else
                auxiliary_byte = 8'h40 + superlane*8'h20 +
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
        input integer superlane;
        input integer stream_id;
        input [63:0] data;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = boundary_lane_index(
                    0, 0, superlane, stream_id, local_lane);
                srf_boundary_input_valid_i[local_index] = 1'b1;
                srf_boundary_input_data_i[local_index*8 +: 8] =
                    data[local_lane*8 +: 8];
            end
        end
    endtask

    task set_auxiliary_tile;
        input integer superlane;
        input integer include_stream0;
        integer local_stream;
        integer local_lane;
        integer local_index;
        begin
            for (local_stream = 0; local_stream < 16;
                 local_stream = local_stream + 1) begin
                if (include_stream0 || (local_stream != 0)) begin
                    for (local_lane = 0; local_lane < 8;
                         local_lane = local_lane + 1) begin
                        local_index = boundary_lane_index(
                            0, 0, superlane, local_stream, local_lane);
                        srf_boundary_input_valid_i[local_index] = 1'b1;
                        srf_boundary_input_data_i[local_index*8 +: 8] =
                            auxiliary_byte(
                                superlane, local_stream, local_lane);
                    end
                end
            end
        end
    endtask

    task check_state_segment;
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
                    0, 0, sr_column, superlane,
                    stream_id, local_lane);
                if (srf_state_valid_o[local_index] !== expected_valid ||
                    (expected_valid &&
                     srf_state_data_o[local_index*8 +: 8] !==
                        expected[local_lane*8 +: 8])) begin
                    $display("ERROR SR state c=%0d t=%0d s=%0d l=%0d",
                             sr_column, superlane, stream_id, local_lane);
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
            set_boundary_segment(0, 3, mem_row_data[0 +: 64]);
            @(posedge clk_i);
            #1;
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                @(negedge clk_i);
                clear_inputs();
                if (local_tile < 3)
                    set_boundary_segment(
                        local_tile+1, 3,
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

    task run_loopback;
        integer local_column;
        integer local_lane;
        integer boundary_bit;
        begin
            // Cycle N: launch the 15 auxiliary tile0 streams through the
            // boundary while MEM creates the tracked stream0 producer.
            @(negedge clk_i);
            clear_inputs();
            set_auxiliary_tile(0, 0);
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
                $display("ERROR MEM loopback producer");
                errors = errors + 1;
            end
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                mem_bit = owner_lane_index(
                    0, 0, 1, 0, 0, 0, local_lane);
                if (!dut.mem_srf_inject_valid[mem_bit] ||
                    dut.mem_srf_inject_data[mem_bit*8 +: 8] !==
                        BYTE_PATTERN[local_lane*8 +: 8]) begin
                    $display("ERROR MEM slot0 lane=%0d", local_lane);
                    errors = errors + 1;
                end
            end

            // Launch tile1..tile3 on consecutive cycles. They trail tile0 by
            // one cycle each and satisfy the registered SXM control column.
            for (tile = 1; tile < 4; tile = tile + 1) begin
                @(negedge clk_i);
                clear_inputs();
                set_auxiliary_tile(tile, 1);
                @(posedge clk_i);
                #1;
                if (tile == 1) begin
                    mem_commit_cycle = cycle_count;
                    check_state_segment(1, 0, 0,
                                        BYTE_PATTERN, 1'b1);
                end else begin
                    check_state_segment(tile, 0, 0,
                                        BYTE_PATTERN, 1'b1);
                end
            end

            clear_inputs();
            for (local_column = 4; local_column <= 14;
                 local_column = local_column + 1) begin
                @(posedge clk_i);
                #1;
                check_state_segment(local_column, 0, 0,
                                    BYTE_PATTERN, 1'b1);
            end
            sxm_input_cycle = cycle_count;

            // Current tile0 at column14 contains stream0 from MEM and the
            // auxiliary streams. Observe the normal SXM read interface.
            @(negedge clk_i);
            clear_inputs();
            transpose_cmd_valid_i[0] = 1'b1;
            transpose_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd0, 1'b0, 5'd0, 1'b0, 5'd16,
                4'd0, 3'd0, 8'd0);
            #1;
            segment_index = sxm_segment_index(0, 0, 0);
            if (dut.sxm_sr_read_req[0 +: 6] !== 6'b000000 ||
                dut.sxm_sr_read_valid[0 +: 16] !== 16'hffff ||
                dut.sxm_sr_read_data[segment_index*64 +: 64] !==
                    BYTE_PATTERN) begin
                $display("ERROR SXM loopback input");
                errors = errors + 1;
            end
            @(posedge clk_i);
            transpose_cmd_valid_i[0] = 1'b0;
            #1;

            // Capture the remaining three legal tile waves. On the final
            // capture edge issue another MEM Read; its tile0 response then
            // overlaps the SXM producer for a direct slot-isolation check.
            repeat (2) begin
                @(posedge clk_i);
                #1;
            end
            @(negedge clk_i);
            clear_inputs();
            west_bank_issue_valid_i[0] = 1'b1;
            west_bank_issue_i[0 +: 32] =
                make_mem_cmd(OPCODE_READ, 1'b0, 5'd5, 15'd5);
            @(posedge clk_i);
            #1;

            @(negedge clk_i);
            clear_inputs();
            permute_cmd_valid_i[0] = 1'b1;
            permute_cmd_i[0 +: 96] = make_sxm_cmd(
                2'd1, 1'b0, 5'd0, 1'b0, 5'd16,
                4'd0, 3'd0, 8'd0);
            #1;
            sxm_candidate_cycle = cycle_count;
            segment_index = sxm_segment_index(0, 0, 0);
            if (!dut.sxm_sr_write_valid[segment_index] ||
                dut.sxm_sr_write_sel[0 +: 6] !== 6'b010000 ||
                dut.sxm_sr_write_data[segment_index*64 +: 64] !==
                    BYTE_PATTERN) begin
                $display("ERROR SXM loopback producer");
                errors = errors + 1;
            end
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                mem_bit = owner_lane_index(
                    0, 0, 1, 0, 0, 5, local_lane);
                sxm_bit = owner_lane_index(
                    0, 0, 15, 0, 1, 16, local_lane);
                if (!dut.mem_srf_inject_valid[mem_bit] ||
                    !dut.sxm_srf_inject_valid[sxm_bit] ||
                    dut.sxm_srf_inject_valid[mem_bit] ||
                    dut.mem_srf_inject_valid[sxm_bit] ||
                    dut.sxm_srf_inject_data[sxm_bit*8 +: 8] !==
                        BYTE_PATTERN[local_lane*8 +: 8]) begin
                    $display("ERROR loopback slot isolation lane=%0d",
                             local_lane);
                    errors = errors + 1;
                end
            end
            if (srf_fabric_collision_o) begin
                $display("ERROR loopback collision");
                errors = errors + 1;
            end

            @(posedge clk_i);
            permute_cmd_valid_i[0] = 1'b0;
            #1;
            sxm_commit_cycle = cycle_count;
            consumer_cycle = cycle_count;
            check_state_segment(15, 0, 16,
                                BYTE_PATTERN, 1'b1);
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                boundary_bit = boundary_lane_index(
                    0, 0, 0, 16, local_lane);
                if (!srf_boundary_output_valid_o[boundary_bit] ||
                    srf_boundary_output_data_o[boundary_bit*8 +: 8] !==
                        BYTE_PATTERN[local_lane*8 +: 8]) begin
                    $display("ERROR loopback consumer lane=%0d", local_lane);
                    errors = errors + 1;
                end
            end

            // The East observer consumes the terminal boundary beat. Since
            // column15 has no later internal column, the following bubble
            // must clear the observed stream on the next commit edge.
            clear_inputs();
            @(posedge clk_i);
            #1;
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                boundary_bit = boundary_lane_index(
                    0, 0, 0, 16, local_lane);
                if (srf_boundary_output_valid_o[boundary_bit]) begin
                    $display("ERROR loopback terminal consume lane=%0d",
                             local_lane);
                    errors = errors + 1;
                end
            end

            if (mem_commit_cycle !== mem_candidate_cycle + 1 ||
                sxm_input_cycle !== mem_commit_cycle + 13 ||
                sxm_commit_cycle !== sxm_candidate_cycle + 1 ||
                consumer_cycle !== sxm_commit_cycle) begin
                $display("ERROR loopback cycle contract mem_cand=%0d mem_commit=%0d input=%0d sxm_cand=%0d sxm_commit=%0d consumer=%0d",
                         mem_candidate_cycle, mem_commit_cycle,
                         sxm_input_cycle, sxm_candidate_cycle,
                         sxm_commit_cycle, consumer_cycle);
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
            64'h3837363534333231,
            64'h2827262524232221,
            64'h1817161514131211,
            BYTE_PATTERN
        };

        pulse_reset();
        write_mem_row();
        pulse_reset();

        $display("RUN_TEST mem_srf_sxm_full_loopback");
        before_errors = errors;
        run_loopback();
        if (errors == before_errors) begin
            $display("MEM_INPUT_PASS");
            $display("SR_PROPAGATION_PASS");
            $display("SXM_PROCESS_PASS");
            $display("SXM_OUTPUT_PASS");
            $display("LOOPBACK_SLOT_ISOLATION PASS");
            $display("LOOPBACK_CONSUME PASS");
            $display("CYCLE_CONTRACT PASS");
        end

        if (system_fault_reserved_o !== 1'b0 ||
            srf_fabric_collision_o || srf_fabric_invalid_consume_o ||
            mem_bank_fault_valid_o !== 208'b0 ||
            sxm_fault_valid_o !== 2'b0) begin
            $display("ERROR final loopback diagnostics");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("================================");
            $display("MEM_SRF_SXM_LOOPBACK_E2E TEST_PASS");
            $display("================================");
            $finish;
        end

        $display("================================");
        $display("MEM_SRF_SXM_LOOPBACK_E2E TEST_FAIL errors=%0d", errors);
        $display("================================");
        $fatal(1);
    end

endmodule
