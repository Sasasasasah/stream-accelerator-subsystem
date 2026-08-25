`timescale 1ns/1ps

module tb_srf_mem_integration;

    localparam P_TEST_DEPTH = 16;
    localparam [2:0] OPCODE_READ  = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;

    reg clk_i;
    reg rst_ni;
    reg [32767:0] srf_boundary_input_data_i;
    reg [4095:0]  srf_boundary_input_valid_i;
    reg [103:0]   west_bank_issue_valid_i;
    reg [3327:0]  west_bank_issue_i;
    reg [103:0]   east_bank_issue_valid_i;
    reg [3327:0]  east_bank_issue_i;

    wire [32767:0] srf_boundary_output_data_o;
    wire [4095:0]  srf_boundary_output_valid_o;
    wire [524287:0] srf_state_data_o;
    wire [65535:0]  srf_state_valid_o;
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
    wire system_fault_reserved_o;

    integer errors;
    integer tile;
    integer lane;
    integer bit_index;
    reg [255:0] row_data;

    srf_mem_integration_top #(
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
        .system_fault_reserved_o(system_fault_reserved_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [31:0] make_cmd;
        input [2:0] opcode;
        input direction;
        input [4:0] stream_index;
        input [14:0] row;
        begin
            make_cmd = 32'b0;
            make_cmd[2:0] = opcode;
            make_cmd[8:3] = {direction, stream_index};
            make_cmd[29:15] = row;
            make_cmd[31] = 1'b0;
        end
    endfunction

    function integer boundary_lane_index;
        input integer path;
        input integer superlane;
        input integer stream;
        input integer lane_id;
        begin
            boundary_lane_index =
                ((path*4 + superlane)*32 + stream)*8 + lane_id;
        end
    endfunction

    function integer state_lane_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer stream;
        input integer lane_id;
        begin
            state_lane_index =
                ((((hemisphere*2 + direction)*16 + column)*4 +
                   superlane)*32 + stream)*8 + lane_id;
        end
    endfunction

    function integer consume_bit_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer consumer;
        input integer stream;
        input integer lane_id;
        begin
            consume_bit_index =
                (((((hemisphere*2 + direction)*16 + column)*4 +
                    superlane)*2 + consumer)*32 + stream)*8 + lane_id;
        end
    endfunction

    function integer inject_bit_index;
        input integer hemisphere;
        input integer direction;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream;
        input integer lane_id;
        begin
            inject_bit_index =
                (((((hemisphere*2 + direction)*16 + column)*4 +
                    superlane)*2 + producer)*32 + stream)*8 + lane_id;
        end
    endfunction

    function integer mem_boundary_cell;
        input integer hemisphere;
        input integer boundary;
        input integer direction;
        input integer stream;
        input integer tile_id;
        begin
            mem_boundary_cell = hemisphere*3584 + boundary*256 +
                                direction*128 + stream*4 + tile_id;
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
        end
    endtask

    task set_west_east_boundary_segment;
        input integer superlane;
        input integer stream;
        input [63:0] data;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = boundary_lane_index(
                    0, superlane, stream, local_lane);
                srf_boundary_input_valid_i[local_index] = 1'b1;
                srf_boundary_input_data_i[
                    local_index*8 +: 8] = data[local_lane*8 +: 8];
            end
        end
    endtask

    task apply_cycle;
        begin
            @(posedge clk_i);
            #1;
        end
    endtask

    task pulse_reset;
        begin
            @(negedge clk_i);
            clear_inputs();
            rst_ni = 1'b0;
            #1;
            if (srf_state_valid_o !== 65536'b0 ||
                mem_hemisphere_busy_o !== 2'b00) begin
                $display("ERROR reset did not clear transient state");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            apply_cycle();
        end
    endtask

    task check_segment_state;
        input integer column;
        input integer superlane;
        input integer stream;
        input [63:0] expected;
        integer local_lane;
        integer local_index;
        begin
            for (local_lane = 0; local_lane < 8;
                 local_lane = local_lane + 1) begin
                local_index = state_lane_index(
                    0, 0, column, superlane, stream, local_lane);
                if (!srf_state_valid_o[local_index] ||
                    srf_state_data_o[local_index*8 +: 8] !==
                        expected[local_lane*8 +: 8]) begin
                    $display("ERROR round-trip state column%0d tile%0d lane%0d",
                             column, superlane, local_lane);
                    errors = errors + 1;
                end
            end
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

        pulse_reset();

        $display("RUN_TEST mem_write_to_srf_consume");
        // Boundary input becomes visible in column0 after one edge. The four
        // superlane segments are staggered to meet the MEM tile0..tile3
        // control wave in consecutive cycles.
        @(negedge clk_i);
        clear_inputs();
        set_west_east_boundary_segment(0, 3, row_data[0 +: 64]);
        apply_cycle();

        for (tile = 0; tile < 4; tile = tile + 1) begin
            @(negedge clk_i);
            clear_inputs();
            if (tile < 3)
                set_west_east_boundary_segment(
                    tile + 1, 3, row_data[(tile+1)*64 +: 64]);
            if (tile == 0) begin
                west_bank_issue_valid_i[0] = 1'b1;
                west_bank_issue_i[0 +: 32] =
                    make_cmd(OPCODE_WRITE, 1'b0, 5'd3, 15'd5);
            end
            apply_cycle();

            if (!dut.mem_boundary_consume[
                    mem_boundary_cell(0,0,0,3,tile)]) begin
                $display("ERROR MEM consume missing tile%0d", tile);
                errors = errors + 1;
            end
            for (lane = 0; lane < 8; lane = lane + 1) begin
                bit_index = consume_bit_index(0,0,0,tile,0,3,lane);
                if (!dut.srf_consume[bit_index]) begin
                    $display("ERROR SRF consume mapping tile%0d lane%0d",
                             tile, lane);
                    errors = errors + 1;
                end
            end
        end

        if (mem_bank_fault_valid_o !== 208'b0 ||
            system_fault_reserved_o !== 1'b0) begin
            $display("ERROR Write generated fault or reserved status");
            errors = errors + 1;
        end

        // Reset clears SRF/control state but intentionally preserves MEM SRAM.
        pulse_reset();

        $display("RUN_TEST mem_read_to_srf_producer0");
        for (tile = 0; tile < 4; tile = tile + 1) begin
            @(negedge clk_i);
            clear_inputs();
            if (tile == 0) begin
                west_bank_issue_valid_i[0] = 1'b1;
                west_bank_issue_i[0 +: 32] =
                    make_cmd(OPCODE_READ, 1'b0, 5'd9, 15'd5);
            end
            apply_cycle();

            if (!dut.mem_producer_valid[tile] ||
                dut.mem_producer_data[tile*64 +: 64] !==
                    row_data[tile*64 +: 64] ||
                dut.mem_producer_stream_dir[tile] !== 1'b0 ||
                dut.mem_producer_stream_idx[tile*5 +: 5] !== 5'd9 ||
                dut.mem_producer_boundary[tile*4 +: 4] !== 4'd1) begin
                $display("ERROR MEM Read producer tile%0d", tile);
                errors = errors + 1;
            end

            for (lane = 0; lane < 8; lane = lane + 1) begin
                bit_index = inject_bit_index(0,0,1,tile,0,9,lane);
                if (!dut.srf_inject_valid[bit_index] ||
                    dut.srf_inject_data[bit_index*8 +: 8] !==
                        row_data[tile*64 + lane*8 +: 8]) begin
                    $display("ERROR producer0 inject tile%0d lane%0d",
                             tile, lane);
                    errors = errors + 1;
                end
            end

            if (tile > 0)
                check_segment_state(1, tile-1, 9,
                                    row_data[(tile-1)*64 +: 64]);
        end

        @(negedge clk_i);
        clear_inputs();
        apply_cycle();
        check_segment_state(1, 3, 9, row_data[3*64 +: 64]);

        $display("RUN_TEST basic_srf_mem_srf_round_trip");
        if (srf_fabric_collision_o ||
            srf_fabric_invalid_consume_o ||
            mem_bank_fault_valid_o !== 208'b0 ||
            mem_hemisphere_fault_valid_o !== 2'b00) begin
            $display("ERROR round-trip status");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
