`timescale 1ns/1ps

module tb_sr_controller;

    localparam COLUMN_NUM    = 4;
    localparam SUPERLANE_NUM = 2;
    localparam STREAM_NUM    = 4;
    localparam LANE_NUM      = 4;
    localparam DATA_WIDTH    = SUPERLANE_NUM * STREAM_NUM * LANE_NUM * 8;
    localparam VALID_WIDTH   = SUPERLANE_NUM * STREAM_NUM * LANE_NUM;

    reg                    clk;
    reg                    rst;
    reg                    direction;
    reg  [63:0]            command;
    reg  [DATA_WIDTH-1:0]  stream_data_in;
    reg  [VALID_WIDTH-1:0] stream_valid_in;
    wire [DATA_WIDTH-1:0]  stream_data_out;
    wire [VALID_WIDTH-1:0] stream_valid_out;
    wire [7:0]             read_data;
    wire                   read_valid;
    wire                   cmd_ready;
    integer errors;

    sr_direction_fabric_ext #(
        .COLUMN_NUM(COLUMN_NUM),
        .SUPERLANE_NUM(SUPERLANE_NUM),
        .STREAM_NUM(STREAM_NUM),
        .LANE_NUM(LANE_NUM),
        .COLUMN_ADDR_WIDTH(2),
        .SUPERLANE_ADDR_WIDTH(1),
        .STREAM_ADDR_WIDTH(2),
        .LANE_ADDR_WIDTH(2)
    ) dut (
        .clk_i(clk),
        .rst_ni(~rst),
        .direction(direction),
        .cmd_valid(command[63:56] != 8'h00),
        .cmd_ready(cmd_ready),
        .cmd_data(command),
        .stream_data_in(stream_data_in),
        .stream_valid_in(stream_valid_in),
        .stream_data_out(stream_data_out),
        .stream_valid_out(stream_valid_out),
        .inject_valid_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .inject_data_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM*8{1'b0}}),
        .consume_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        // Direct  access is idle; this test uses commands only.
        .write_en(1'b0),
        .write_column(2'b00),
        .write_superlane(1'b0),
        .write_stream(2'b00),
        .write_lane(2'b00),
        .write_data(8'h00),
        .read_en(1'b0),
        .read_column(2'b00),
        .read_superlane(1'b0),
        .read_stream(2'b00),
        .read_lane(2'b00),
        .read_data(read_data),
        .read_valid(read_valid)
    );

    always #5 clk = ~clk;

    function integer cell_index;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            cell_index = ((superlane * STREAM_NUM + stream) * LANE_NUM + lane);
        end
    endfunction

    function [63:0] make_write_command;
        input [7:0] column;
        input [7:0] superlane;
        input [7:0] stream;
        input [7:0] lane;
        input [7:0] data;
        begin
            make_write_command = {8'h01, column, superlane, stream,
                                  lane, data, 16'h0000};
        end
    endfunction

    function [63:0] make_read_command;
        input [7:0] column;
        input [7:0] superlane;
        input [7:0] stream;
        input [7:0] lane;
        begin
            make_read_command = {8'h02, column, superlane, stream,
                                 lane, 8'h00, 16'h0000};
        end
    endfunction

    task clear_stream_input;
        begin
            stream_data_in  = {DATA_WIDTH{1'b0}};
            stream_valid_in = {VALID_WIDTH{1'b0}};
        end
    endtask

    task reset_pipeline;
        begin
            @(negedge clk);
            rst = 1'b1;
            command = 64'h0000_0000_0000_0000;
            clear_stream_input;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task issue_write_command;
        input [7:0] column;
        input [7:0] superlane;
        input [7:0] stream;
        input [7:0] lane;
        input [7:0] data;
        begin
            @(negedge clk);
            command = make_write_command(column, superlane, stream, lane, data);
            @(posedge clk);
            #1;
            command = 64'h0000_0000_0000_0000;
        end
    endtask

    task issue_read_and_expect;
        input [7:0] column;
        input [7:0] superlane;
        input [7:0] stream;
        input [7:0] lane;
        input       expected_valid;
        input [7:0] expected_data;
        begin
            command = make_read_command(column, superlane, stream, lane);
            #1;
            if (read_valid !== expected_valid || read_data !== expected_data) begin
                $display("CHECK_FAIL command_read column=%0d superlane=%0d stream=%0d lane=%0d expected_valid=%0d expected_data=%h actual_valid=%0d actual_data=%h",
                         column, superlane, stream, lane,
                         expected_valid, expected_data, read_valid, read_data);
                errors = errors + 1;
            end
            command = 64'h0000_0000_0000_0000;
        end
    endtask

    task set_stream_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] data;
        integer index;
        begin
            index = cell_index(superlane, stream, lane);
            stream_data_in[index*8 +: 8] = data;
            stream_valid_in[index] = 1'b1;
        end
    endtask

    task expect_stream_output;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] expected_data;
        integer index;
        begin
            index = cell_index(superlane, stream, lane);
            if (stream_valid_out[index] !== 1'b1 ||
                stream_data_out[index*8 +: 8] !== expected_data) begin
                $display("CHECK_FAIL pipeline direction=%0d superlane=%0d stream=%0d lane=%0d expected_data=%h actual_valid=%0d actual_data=%h",
                         direction, superlane, stream, lane, expected_data,
                         stream_valid_out[index], stream_data_out[index*8 +: 8]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        direction = 1'b0;
        command = 64'h0000_0000_0000_0000;
        errors = 0;
        clear_stream_input;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Test 1: decode WRITE and READ commands for one cell.
        $display("RUN_TEST controller_write_read");
        issue_write_command(8'd0, 8'd0, 8'd0, 8'd0, 8'h55);
        issue_read_and_expect(8'd0, 8'd0, 8'd0, 8'd0, 1'b1, 8'h55);

        // Test 2: three command writes remain independent while propagating.
        reset_pipeline;
        $display("RUN_TEST controller_multiple_write");
        direction = 1'b0;
        issue_write_command(8'd0, 8'd0, 8'd0, 8'd0, 8'ha1);
        issue_write_command(8'd0, 8'd1, 8'd1, 8'd2, 8'hb2);
        issue_write_command(8'd0, 8'd0, 8'd3, 8'd1, 8'hc3);
        issue_read_and_expect(8'd2, 8'd0, 8'd0, 8'd0, 1'b1, 8'ha1);
        issue_read_and_expect(8'd1, 8'd1, 8'd1, 8'd2, 1'b1, 8'hb2);
        issue_read_and_expect(8'd0, 8'd0, 8'd3, 8'd1, 1'b1, 8'hc3);

        // Test 3: READ reports valid for written state and invalid otherwise.
        reset_pipeline;
        $display("RUN_TEST controller_read_valid");
        issue_read_and_expect(8'd0, 8'd0, 8'd2, 8'd3, 1'b0, 8'h00);
        issue_write_command(8'd0, 8'd0, 8'd2, 8'd3, 8'h66);
        issue_read_and_expect(8'd0, 8'd0, 8'd2, 8'd3, 1'b1, 8'h66);

        // Test 4: command idle;  East and West pipelines remain unchanged.
        reset_pipeline;
        $display("RUN_TEST controller_pipeline_east");
        direction = 1'b0;
        set_stream_cell(0, 0, 0, 8'h5a);
        @(negedge clk);
        clear_stream_input;
        repeat (COLUMN_NUM-1) @(posedge clk);
        #1;
        expect_stream_output(0, 0, 0, 8'h5a);

        reset_pipeline;
        $display("RUN_TEST controller_pipeline_west");
        direction = 1'b1;
        set_stream_cell(1, 2, 3, 8'haa);
        @(negedge clk);
        clear_stream_input;
        repeat (COLUMN_NUM-1) @(posedge clk);
        #1;
        expect_stream_output(1, 2, 3, 8'haa);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
