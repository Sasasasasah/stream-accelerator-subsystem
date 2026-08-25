`timescale 1ns/1ps

// Synchronous command FIFO with ready/valid interfaces on both sides.
module sr_command_fifo #(
    parameter DATA_WIDTH = 64,
    parameter DEPTH      = 8
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  cmd_valid,
    output wire                  cmd_ready,
    input  wire [DATA_WIDTH-1:0] cmd_data,
    output wire                  fifo_valid,
    input  wire                  fifo_ready,
    output wire [DATA_WIDTH-1:0] fifo_data
);

    function integer clog2;
        input integer value;
        integer shifted;
        begin
            shifted = value - 1;
            clog2 = 0;
            while (shifted > 0) begin
                shifted = shifted >> 1;
                clog2 = clog2 + 1;
            end
        end
    endfunction

    localparam PTR_WIDTH   = (DEPTH <= 1) ? 1 : clog2(DEPTH);
    localparam COUNT_WIDTH = (DEPTH <= 1) ? 1 : clog2(DEPTH + 1);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0]  write_ptr;
    reg [PTR_WIDTH-1:0]  read_ptr;
    reg [COUNT_WIDTH-1:0] count;

    wire push;
    wire pop;

    assign cmd_ready  = (count < DEPTH);
    assign fifo_valid = (count != 0);
    assign fifo_data  = fifo_valid ? memory[read_ptr] : {DATA_WIDTH{1'b0}};
    assign push = cmd_valid && cmd_ready;
    assign pop  = fifo_valid && fifo_ready;

    always @(posedge clk) begin
        if (rst) begin
            write_ptr <= {PTR_WIDTH{1'b0}};
            read_ptr  <= {PTR_WIDTH{1'b0}};
            count     <= {COUNT_WIDTH{1'b0}};
        end else begin
            if (push) begin
                memory[write_ptr] <= cmd_data;
                if (write_ptr == DEPTH-1)
                    write_ptr <= {PTR_WIDTH{1'b0}};
                else
                    write_ptr <= write_ptr + 1'b1;
            end

            if (pop) begin
                if (read_ptr == DEPTH-1)
                    read_ptr <= {PTR_WIDTH{1'b0}};
                else
                    read_ptr <= read_ptr + 1'b1;
            end

            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
