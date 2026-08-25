`timescale 1ns/1ps

module tb_sr_access;

    localparam COLUMN_NUM            = 4;
    localparam SUPERLANE_NUM         = 2;
    localparam STREAM_NUM            = 4;
    localparam LANE_NUM              = 4;
    localparam COLUMN_ADDR_WIDTH     = 2;
    localparam SUPERLANE_ADDR_WIDTH  = 1;
    localparam STREAM_ADDR_WIDTH     = 2;
    localparam LANE_ADDR_WIDTH       = 2;
    localparam DATA_WIDTH            = SUPERLANE_NUM * STREAM_NUM * LANE_NUM * 8;
    localparam VALID_WIDTH           = SUPERLANE_NUM * STREAM_NUM * LANE_NUM;

    reg                             clk;
    reg                             rst;
    reg                             direction;
    reg  [DATA_WIDTH-1:0]           stream_data_in;
    reg  [VALID_WIDTH-1:0]          stream_valid_in;
    wire [DATA_WIDTH-1:0]           stream_data_out;
    wire [VALID_WIDTH-1:0]          stream_valid_out;
    reg                             write_en;
    reg  [COLUMN_ADDR_WIDTH-1:0]    write_column;
    reg  [SUPERLANE_ADDR_WIDTH-1:0] write_superlane;
    reg  [STREAM_ADDR_WIDTH-1:0]    write_stream;
    reg  [LANE_ADDR_WIDTH-1:0]      write_lane;
    reg  [7:0]                      write_data;
    reg                             read_en;
    reg  [COLUMN_ADDR_WIDTH-1:0]    read_column;
    reg  [SUPERLANE_ADDR_WIDTH-1:0] read_superlane;
    reg  [STREAM_ADDR_WIDTH-1:0]    read_stream;
    reg  [LANE_ADDR_WIDTH-1:0]      read_lane;
    wire [7:0]                      read_data;
    wire                            read_valid;
    integer errors;

    sr_direction_fabric_ext #(
        .COLUMN_NUM(COLUMN_NUM),
        .SUPERLANE_NUM(SUPERLANE_NUM),
        .STREAM_NUM(STREAM_NUM),
        .LANE_NUM(LANE_NUM),
        .COLUMN_ADDR_WIDTH(COLUMN_ADDR_WIDTH),
        .SUPERLANE_ADDR_WIDTH(SUPERLANE_ADDR_WIDTH),
        .STREAM_ADDR_WIDTH(STREAM_ADDR_WIDTH),
        .LANE_ADDR_WIDTH(LANE_ADDR_WIDTH)
    ) dut (
        .clk_i(clk),
        .rst_ni(~rst),
        .direction(direction),
        .cmd_valid(1'b0),
        .cmd_ready(),
        .cmd_data(64'h0000_0000_0000_0000),
        .stream_data_in(stream_data_in),
        .stream_valid_in(stream_valid_in),
        .stream_data_out(stream_data_out),
        .stream_valid_out(stream_valid_out),
        .inject_valid_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .inject_data_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM*8{1'b0}}),
        .consume_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .write_en(write_en),
        .write_column(write_column),
        .write_superlane(write_superlane),
        .write_stream(write_stream),
        .write_lane(write_lane),
        .write_data(write_data),
        .read_en(read_en),
        .read_column(read_column),
        .read_superlane(read_superlane),
        .read_stream(read_stream),
        .read_lane(read_lane),
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

    task clear_stream_input;
        begin
            stream_data_in  = {DATA_WIDTH{1'b0}};
            stream_valid_in = {VALID_WIDTH{1'b0}};
        end
    endtask

    task clear_access;
        begin
            write_en        = 1'b0;
            write_column    = {COLUMN_ADDR_WIDTH{1'b0}};
            write_superlane = {SUPERLANE_ADDR_WIDTH{1'b0}};
            write_stream    = {STREAM_ADDR_WIDTH{1'b0}};
            write_lane      = {LANE_ADDR_WIDTH{1'b0}};
            write_data      = 8'h00;
            read_en         = 1'b0;
            read_column     = {COLUMN_ADDR_WIDTH{1'b0}};
            read_superlane  = {SUPERLANE_ADDR_WIDTH{1'b0}};
            read_stream     = {STREAM_ADDR_WIDTH{1'b0}};
            read_lane       = {LANE_ADDR_WIDTH{1'b0}};
        end
    endtask

    task write_cell;
        input [COLUMN_ADDR_WIDTH-1:0]    column;
        input [SUPERLANE_ADDR_WIDTH-1:0] superlane;
        input [STREAM_ADDR_WIDTH-1:0]    stream;
        input [LANE_ADDR_WIDTH-1:0]      lane;
        input [7:0]                      value;
        begin
            @(negedge clk);
            write_en        = 1'b1;
            write_column    = column;
            write_superlane = superlane;
            write_stream    = stream;
            write_lane      = lane;
            write_data      = value;
            @(posedge clk);
            #1;
            write_en = 1'b0;
        end
    endtask

    task read_and_expect_cell;
        input [COLUMN_ADDR_WIDTH-1:0]    column;
        input [SUPERLANE_ADDR_WIDTH-1:0] superlane;
        input [STREAM_ADDR_WIDTH-1:0]    stream;
        input [LANE_ADDR_WIDTH-1:0]      lane;
        input                            expected_valid;
        input [7:0]                      expected_data;
        begin
            read_en         = 1'b1;
            read_column     = column;
            read_superlane  = superlane;
            read_stream     = stream;
            read_lane       = lane;
            #1;
            if (read_valid !== expected_valid || read_data !== expected_data) begin
                $display("CHECK_FAIL read column=%0d superlane=%0d stream=%0d lane=%0d expected_valid=%0d expected_data=%h actual_valid=%0d actual_data=%h",
                         column, superlane, stream, lane,
                         expected_valid, expected_data, read_valid, read_data);
                errors = errors + 1;
            end
        end
    endtask

    task set_stream_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] value;
        integer index;
        begin
            index = cell_index(superlane, stream, lane);
            stream_data_in[index*8 +: 8] = value;
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

    task reset_pipeline;
        begin
            @(negedge clk);
            rst = 1'b1;
            clear_stream_input;
            clear_access;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        direction = 1'b0;
        errors = 0;
        clear_stream_input;
        clear_access;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Test 1: write and immediately read one physical cell.
        $display("RUN_TEST access_single_write_read");
        write_cell(2'd0, 1'd0, 2'd0, 2'd0, 8'h55);
        read_and_expect_cell(2'd0, 1'd0, 2'd0, 2'd0, 1'b1, 8'h55);

        // Test 2: cells remain independent as data advances through columns.
        reset_pipeline;
        $display("RUN_TEST access_multiple_cells");
        direction = 1'b0;
        write_cell(2'd0, 1'd0, 2'd0, 2'd0, 8'ha1);
        write_cell(2'd0, 1'd1, 2'd1, 2'd2, 8'hb2);
        write_cell(2'd0, 1'd0, 2'd3, 2'd1, 8'hc3);

        // A1, B2, and C3 have advanced to columns 2, 1, and 0 respectively.
        read_and_expect_cell(2'd2, 1'd0, 2'd0, 2'd0, 1'b1, 8'ha1);
        read_and_expect_cell(2'd1, 1'd1, 2'd1, 2'd2, 1'b1, 8'hb2);
        read_and_expect_cell(2'd0, 1'd0, 2'd3, 2'd1, 1'b1, 8'hc3);

        // Test 3: access logic disabled;  East and West propagation remains.
        reset_pipeline;
        $display("RUN_TEST pipeline_east_regression");
        direction = 1'b0;
        set_stream_cell(0, 0, 0, 8'h5a);
        @(negedge clk);
        clear_stream_input;
        repeat (COLUMN_NUM-1) @(posedge clk);
        #1;
        expect_stream_output(0, 0, 0, 8'h5a);

        reset_pipeline;
        $display("RUN_TEST pipeline_west_regression");
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
