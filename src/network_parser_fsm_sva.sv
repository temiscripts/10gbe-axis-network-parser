

module network_parser_fsm_sva #(
    parameter int DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic                  s_axis_tvalid,
    input logic                  s_axis_tlast,
    input logic                  s_axis_tready,
    input logic                  pkt_dropped_flag,
    input logic [DATA_WIDTH-1:0] m_axis_tdata,
    input logic                  m_axis_tvalid,
    input logic                  m_axis_tlast,
    input logic                  m_axis_tready,

    input logic [31:0] cfg_target_ip,
    input logic [15:0] cfg_target_port,
    input logic [ 2:0] network_state,
    input logic [15:0] byte_offset
);

  localparam logic [2:0] ST_IDLE = 3'b000;
  localparam logic [2:0] ST_ETH  = 3'b001;
  localparam logic [2:0] ST_IPV4 = 3'b010;
  localparam logic [2:0] ST_UDP  = 3'b011;
  localparam logic [2:0] ST_DROP = 3'b100;

  default clocking cb @(posedge clk);
  endclocking
  default disable iff (!rst_n);

  property p_egress_valid_only_in_udp;
    m_axis_tvalid |-> (network_state == ST_UDP);
  endproperty

  assert_egress_valid_only_in_udp :
  assert property (p_egress_valid_only_in_udp)
  else $error("SVA Violation: m_axis_tvalid asserted outside of ST_UDP!");


  property p_drop_flag_state_check;
    pkt_dropped_flag |-> (network_state == ST_DROP) || (network_state == ST_IDLE);
  endproperty

  assert_drop_flag_state_check :
  assert property (p_drop_flag_state_check)
  else $error("SVA Violation: pkt_dropped_flag asserted in illegal state!");

  property p_drop_until_tlast;
    (network_state == ST_DROP) && !s_axis_tlast |-> ##1 (network_state == ST_DROP);
  endproperty

  assert_drop_until_tlast :
  assert property (p_drop_until_tlast)
  else $error("SVA Violation: FSM prematurely exited ST_DROP before receiving s_axis_tlast!");

  property p_drop_to_idle_on_tlast;
    (network_state == ST_DROP) && s_axis_tvalid && s_axis_tready && s_axis_tlast |=>
     (network_state == ST_IDLE);
  endproperty

  assert_drop_to_idle_on_tlast :
  assert property (p_drop_to_idle_on_tlast)
  else $error("SVA Violation: FSM failed to return to ST_IDLE after tlast in ST_DROP!");

  property p_eth_mismatch_drop;
    (network_state == ST_ETH) && s_axis_tvalid && s_axis_tready &&
    (({s_axis_tdata[47:40], s_axis_tdata[39:32]} != ETHERTYPE_IPV4) ||
     (s_axis_tdata[55:48] != IPV4_VER_IHL))
    |=> s_axis_tlast ? (network_state == ST_IDLE) : (network_state == ST_DROP);
  endproperty

  assert_eth_mismatch_drop :
  assert property (p_eth_mismatch_drop)
  else $error("SVA Violation: Ethernet header mismatch failed to route to ST_DROP/ST_IDLE!");

  property p_ipv4_proto_mismatch_drop;
    (network_state == ST_IPV4) && (byte_offset == 16'd16) &&
    s_axis_tvalid && s_axis_tready &&
    ((s_axis_tdata[63:56] != IPV4_PROTOCOL) || s_axis_tlast)
    |=> s_axis_tlast ? (network_state == ST_IDLE) : (network_state == ST_DROP);
  endproperty

  assert_ipv4_proto_mismatch_drop :
  assert property (p_ipv4_proto_mismatch_drop)
  else $error("SVA Violation: Non-UDP protocol failed to transition to ST_DROP/ST_IDLE!");

  property p_ipv4_ip_match_to_udp;
    (network_state == ST_IPV4) && (byte_offset == 16'd32) &&
    s_axis_tvalid && s_axis_tready &&
    ({pipe_data[55:48], pipe_data[63:56], s_axis_tdata[7:0], s_axis_tdata[15:8]} == cfg_target_ip)
    |=> (network_state == ST_UDP);
  endproperty


  property p_ipv4_ip_mismatch_drop;
    (network_state == ST_IPV4) && (byte_offset == 16'd32) &&
    s_axis_tvalid && s_axis_tready &&
    ({pipe_data[55:48], pipe_data[63:56], s_axis_tdata[7:0], s_axis_tdata[15:8]} != cfg_target_ip)
    |=> s_axis_tlast ? (network_state == ST_IDLE) : (network_state == ST_DROP);
  endproperty

  assert_ipv4_ip_mismatch_drop :
  assert property (p_ipv4_ip_mismatch_drop)
  else $error("SVA Violation: Target IP mismatch failed to route to ST_DROP/ST_IDLE!");

  assert_ipv4_ip_match_to_udp :
  assert property (p_ipv4_ip_match_to_udp)
  else $error("SVA Violation: Valid Target IP match failed to transition to ST_UDP!");



  property p_udp_port_match_stream;
    (network_state == ST_UDP) && (byte_offset == 16'd40) &&
    s_axis_tvalid && s_axis_tready &&
    ({pipe_data[39:32], pipe_data[47:40]} == cfg_target_port)
    |=> m_axis_tvalid && (s_axis_tlast ? (network_state == ST_IDLE) : (network_state == ST_UDP));
  endproperty

  assert_udp_port_match_stream :
  assert property (p_udp_port_match_stream)
  else
    $error("SVA Violation: Valid target port match failed to assert m_axis_tvalid or hold state!");

  property p_udp_port_mismatch_drop;
    (network_state == ST_UDP) && (byte_offset == 16'd40) &&
    s_axis_tvalid && s_axis_tready &&
    ({pipe_data[39:32], pipe_data[47:40]} != cfg_target_port)
    |=> s_axis_tlast ? (network_state == ST_IDLE) : (network_state == ST_DROP);
  endproperty

  assert_udp_port_mismatch_drop :
  assert property (p_udp_port_mismatch_drop)
  else $error("SVA Violation: UDP port mismatch failed to transition to ST_DROP/ST_IDLE!");

endmodule

bind network_parser_fsm network_parser_fsm_sva #(
    .DATA_WIDTH(DATA_WIDTH)
) sva_inst (
    .clk             (clk),
    .rst_n           (rst_n),
    .s_axis_tdata    (s_axis_tdata),
    .s_axis_tvalid   (s_axis_tvalid),
    .s_axis_tlast    (s_axis_tlast),
    .s_axis_tready   (s_axis_tready),
    .pkt_dropped_flag(pkt_dropped_flag),
    .m_axis_tdata    (m_axis_tdata),
    .m_axis_tvalid   (m_axis_tvalid),
    .m_axis_tlast    (m_axis_tlast),
    .m_axis_tready   (m_axis_tready),
    .cfg_target_ip   (cfg_target_ip),
    .cfg_target_port (cfg_target_port),
    .network_state   (network_state),
    .byte_offset     (byte_offset)
);
