module network_parser_fsm #(
    parameter int DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n,

    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    input  logic                  s_axis_tlast,
    output logic                  s_axis_tready,
    output logic                  pkt_dropped_flag,
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic                  m_axis_tvalid,
    output logic                  m_axis_tlast,
    input  logic                  m_axis_tready,

    input logic [31:0] cfg_target_ip,
    input logic [15:0] cfg_target_port
);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_ETH,
    ST_IPV4,
    ST_UDP,
    ST_DROP
  } state_t;

  state_t network_state;

  localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
  localparam logic [ 7:0] IPV4_VER_IHL   = 8'h45;
  localparam logic [ 7:0] IPV4_PROTOCOL  = 8'h11;
  localparam logic [15:0] BUS_BYTES      = 16'(DATA_WIDTH / 8);

  logic [          15:0] byte_offset;
  logic [DATA_WIDTH-1:0] pipe_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      network_state    <= ST_IDLE;
      byte_offset      <= '0;
      pipe_data        <= '0;

      s_axis_tready    <= 1'b1;
      pkt_dropped_flag <= 1'b0;

      m_axis_tvalid    <= 1'b0;
      m_axis_tlast     <= 1'b0;
      m_axis_tdata     <= '0;
    end else begin
      case (network_state)
        ST_IDLE: begin
          m_axis_tvalid <= 1'b0;
          m_axis_tlast  <= 1'b0;
          if (s_axis_tready && s_axis_tvalid) begin
            network_state    <= ST_ETH;
            pipe_data        <= s_axis_tdata;
            byte_offset      <= byte_offset + BUS_BYTES;
            pkt_dropped_flag <= 1'b0;
          end
        end
        ST_ETH: begin
          if (s_axis_tready && s_axis_tvalid) begin
            if ({s_axis_tdata[47:40], s_axis_tdata[39:32]} == ETHERTYPE_IPV4 &&
                s_axis_tdata[55:48] == IPV4_VER_IHL) begin
              pipe_data     <= s_axis_tdata;
              network_state <= ST_IPV4;
              byte_offset   <= byte_offset + BUS_BYTES;
            end else begin
              pkt_dropped_flag <= 1'b1;
              if (s_axis_tlast) begin
                network_state <= ST_IDLE;
                byte_offset   <= '0;
              end else begin
                network_state <= ST_DROP;
              end
            end
          end
        end
        ST_IPV4: begin
          if (s_axis_tready && s_axis_tvalid) begin
            if (byte_offset == 16'd16) begin
              if (s_axis_tdata[63:56] == IPV4_PROTOCOL && !s_axis_tlast) begin
                byte_offset <= byte_offset + BUS_BYTES;
                pipe_data   <= s_axis_tdata;
              end else begin
                pkt_dropped_flag <= 1'b1;
                if (s_axis_tlast) begin
                  network_state <= ST_IDLE;
                  byte_offset   <= '0;
                end else begin
                  network_state <= ST_DROP;
                end
              end
            end else if (byte_offset == 16'd24) begin
              if (s_axis_tlast) begin
                pkt_dropped_flag <= 1'b1;
                network_state    <= ST_IDLE;
                byte_offset      <= '0;
              end else begin
                byte_offset <= byte_offset + BUS_BYTES;
                pipe_data   <= s_axis_tdata;
              end
            end else if (byte_offset == 16'd32) begin
              if ({pipe_data[55:48], pipe_data[63:56], s_axis_tdata[7:0], s_axis_tdata[15:8]} == cfg_target_ip) begin
                network_state <= ST_UDP;
                pipe_data     <= s_axis_tdata;
                byte_offset   <= byte_offset + BUS_BYTES;
              end else begin
                pkt_dropped_flag <= 1'b1;
                if (s_axis_tlast) begin
                  network_state <= ST_IDLE;
                  byte_offset   <= '0;
                end else begin
                  network_state <= ST_DROP;
                end
              end
            end
          end
        end
        ST_UDP: begin
          if (s_axis_tready && s_axis_tvalid) begin
            if (byte_offset == 16'd40) begin
              if ({pipe_data[39:32], pipe_data[47:40]} == cfg_target_port) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= s_axis_tdata;
                m_axis_tlast  <= s_axis_tlast;
                byte_offset   <= byte_offset + BUS_BYTES;
                if (s_axis_tlast) begin
                  network_state <= ST_IDLE;
                  byte_offset   <= '0;
                end
              end else begin
                pkt_dropped_flag <= 1'b1;
                if (s_axis_tlast) begin
                  network_state <= ST_IDLE;
                  byte_offset   <= '0;
                end else begin
                  network_state <= ST_DROP;
                end
              end
            end else begin
              m_axis_tvalid <= 1'b1;
              m_axis_tdata  <= s_axis_tdata;
              m_axis_tlast  <= s_axis_tlast;
              byte_offset   <= byte_offset + BUS_BYTES;
              if (s_axis_tlast) begin
                network_state <= ST_IDLE;
                byte_offset   <= '0;
              end
            end
          end else begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
          end
        end
        ST_DROP: begin
          pkt_dropped_flag <= 1'b0;
          m_axis_tvalid    <= 1'b0;
          m_axis_tlast     <= 1'b0;
          if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
            network_state <= ST_IDLE;
            byte_offset   <= '0;
          end
        end
        default: network_state <= ST_IDLE;

      endcase
    end
  end
endmodule
