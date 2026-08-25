`timescale 1ns/1ps

module tb_sr_command_fifo;

    localparam DATA_WIDTH    = 64;
    localparam DEPTH         = 8;
    localparam COLUMN_NUM    = 4;
    localparam SUPERLANE_NUM = 2;
    localparam STREAM_NUM    = 4;
    localparam LANE_NUM      = 4;
    localparam STREAM_WIDTH  = SUPERLANE_NUM * STREAM_NUM * LANE_NUM * 8;
    localparam VALID_WIDTH   = SUPERLANE_NUM * STREAM_NUM * LANE_NUM;

    reg                     clk;
    reg                     rst;
    reg                     cmd_valid;
    wire                    cmd_ready;
    reg  [DATA_WIDTH-1:0]   cmd_data;
    wire                    fifo_valid;
    wire                    fifo_ready;
    wire [DATA_WIDTH-1:0]   fifo_data;
    reg                     tb_fifo_ready;
    reg                     integration_mode;
    wire                    controller_cmd_ready;
    reg                     direction;
    reg  [STREAM_WIDTH-1:0] stream_data_in;
    reg  [VALID_WIDTH-1:0]  stream_valid_in;
    wire [STREAM_WIDTH-1:0] stream_data_out;
    wire [VALID_WIDTH-1:0]  stream_valid_out;
    wire [7:0]              read_data;
    wire                    read_valid;
    integer                 errors;
    integer                 index;

    assign fifo_ready = integration_mode ? controller_cmd_ready : tb_fifo_ready;

    sr_command_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) u_fifo (
        .clk(clk),
        .rst(rst),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_data(cmd_data),
        .fifo_valid(fifo_valid),
        .fifo_ready(fifo_ready),
        .fifo_data(fifo_data)
    );

    sr_direction_fabric_ext #(
        .COLUMN_NUM(COLUMN_NUM),
        .SUPERLANE_NUM(SUPERLANE_NUM),
        .STREAM_NUM(STREAM_NUM),
        .LANE_NUM(LANE_NUM),
        .COLUMN_ADDR_WIDTH(2),
        .SUPERLANE_ADDR_WIDTH(1),
        .STREAM_ADDR_WIDTH(2),
        .LANE_ADDR_WIDTH(2)
    ) u_fabric (
        .clk_i(clk),
        .rst_ni(~rst),
        .direction(direction),
        .cmd_valid(integration_mode && fifo_valid),
        .cmd_ready(controller_cmd_ready),
        .cmd_data(fifo_data),
        .stream_data_in(stream_data_in),
        .stream_valid_in(stream_valid_in),
        .stream_data_out(stream_data_out),
        .stream_valid_out(stream_valid_out),
        .inject_valid_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .inject_data_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM*8{1'b0}}),
        .consume_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
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

    task reset_system;
        begin
            @(negedge clk);
            rst = 1'b1;
            cmd_valid = 1'b0;
            cmd_data = {DATA_WIDTH{1'b0}};
            tb_fifo_ready = 1'b0;
            stream_data_in = {STREAM_WIDTH{1'b0}};
            stream_valid_in = {VALID_WIDTH{1'b0}};
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task push_command;
        input [DATA_WIDTH-1:0] value;
        begin
            @(negedge clk);
            if (cmd_ready !== 1'b1) begin
                $display("CHECK_FAIL fifo_not_ready_for_push");
                errors = errors + 1;
            end
            cmd_data = value;
            cmd_valid = 1'b1;
            @(posedge clk);
            #1;
            cmd_valid = 1'b0;
        end
    endtask

    task pop_and_expect;
        input [DATA_WIDTH-1:0] expected;
        begin
            @(negedge clk);
            if (fifo_valid !== 1'b1 || fifo_data !== expected) begin
                $display("CHECK_FAIL fifo_pop expected=%h actual_valid=%0d actual_data=%h",
                         expected, fifo_valid, fifo_data);
                errors = errors + 1;
            end
            tb_fifo_ready = 1'b1;
            @(posedge clk);
            #1;
            tb_fifo_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        cmd_valid = 1'b0;
        cmd_data = {DATA_WIDTH{1'b0}};
        tb_fifo_ready = 1'b0;
        integration_mode = 1'b0;
        direction = 1'b0;
        stream_data_in = {STREAM_WIDTH{1'b0}};
        stream_valid_in = {VALID_WIDTH{1'b0}};
        errors = 0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Test 1: preserve command order across multiple pushes and pops.
        $display("RUN_TEST fifo_push_pop_order");
        push_command(64'h1111_0000_0000_0001);
        push_command(64'h2222_0000_0000_0002);
        push_command(64'h3333_0000_0000_0003);
        pop_and_expect(64'h1111_0000_0000_0001);
        pop_and_expect(64'h2222_0000_0000_0002);
        pop_and_expect(64'h3333_0000_0000_0003);

        // Test 2: fill every entry and verify source backpressure.
        integration_mode = 1'b0;
        reset_system;
        $display("RUN_TEST fifo_full");
        for (index = 0; index < DEPTH; index = index + 1)
            push_command(64'h5000_0000_0000_0000 + index);
        if (cmd_ready !== 1'b0) begin
            $display("CHECK_FAIL fifo_full_ready_high");
            errors = errors + 1;
        end
        for (index = 0; index < DEPTH; index = index + 1)
            pop_and_expect(64'h5000_0000_0000_0000 + index);

        // Test 3: after the final pop the FIFO must report empty.
        $display("RUN_TEST fifo_empty");
        if (fifo_valid !== 1'b0 || fifo_data !== 64'h0000_0000_0000_0000) begin
            $display("CHECK_FAIL fifo_empty_state");
            errors = errors + 1;
        end

        // Test 4: FIFO output drives controller command execution in SRF.
        integration_mode = 1'b1;
        reset_system;
        $display("RUN_TEST fifo_srf_command_execution");
        push_command(make_write_command(8'd0, 8'd0, 8'd0, 8'd0, 8'h55));
        // On the next edge the controller pops WRITE while the source pushes
        // READ. The new FIFO head then reads the cell written on that edge.
        push_command(make_read_command(8'd0, 8'd0, 8'd0, 8'd0));
        // READ is combinational while the command is at the FIFO head.
        #1;
        if (read_valid !== 1'b1 || read_data !== 8'h55) begin
            $display("CHECK_FAIL fifo_srf_read expected=55 actual_valid=%0d actual_data=%h",
                     read_valid, read_data);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
