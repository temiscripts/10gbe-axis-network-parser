module axis_skid_buffer #(
    parameter int DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n,

    // receiving from network/master
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,

    // sending to slave/parser
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic                  m_axis_tvalid,
    input  logic                  m_axis_tready
);

  logic [DATA_WIDTH-1:0] pipe_data, skid_data;
  logic pipe_valid, skid_valid;

  assign s_axis_tready = ~skid_valid;
  assign m_axis_tdata  = pipe_data;
  assign m_axis_tvalid = pipe_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pipe_valid <= 1'b0;
      skid_valid <= 1'b0;
      pipe_data  <= 'b0;
      skid_data  <= 'b0;
    end else begin
      if (m_axis_tready || !pipe_valid) begin
        // normal stream

        if (skid_valid == 1) begin
          pipe_data  <= skid_data;
          pipe_valid <= 1'b1;
          skid_valid <= 1'b0;
        end else begin
          pipe_data  <= s_axis_tdata;
          pipe_valid <= s_axis_tvalid;
        end
      end else begin
        // stall and skid
        if (s_axis_tvalid) begin
          skid_data  <= s_axis_tdata;
          skid_valid <= 1'b1;
        end
      end
    end


  end


endmodule


