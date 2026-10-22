module axis_skid_buffer_sva #(
    parameter int DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic                    s_axis_tvalid,
    input logic                    s_axis_tready,
    input logic [DATA_WIDTH-1:0] m_axis_tdata,
    input logic                    m_axis_tvalid,
    input logic                    m_axis_tready
);

    // Upstream
    property p_no_take_backs_valid;
        @(posedge clk) disable iff (!rst_n)
        (s_axis_tvalid && !s_axis_tready) |=> s_axis_tvalid;
    endproperty

    property p_no_take_backs_data;
        @(posedge clk) disable iff (!rst_n)
        (s_axis_tvalid && !s_axis_tready) |=> ($stable(s_axis_tdata));
    endproperty

    assert property (p_no_take_backs_valid) else $error("AXI VIOLATION: Upstream dropped tvalid during stall!");
    assert property (p_no_take_backs_data) else $error("AXI VIOLATION: Upstream changed tdata during stall!");

    // Downstream
    property p_master_no_take_backs_valid;
        @(posedge clk) disable iff (!rst_n)
        (m_axis_tvalid && !m_axis_tready) |=> m_axis_tvalid;
    endproperty

    property p_master_no_take_backs_data;
        @(posedge clk) disable iff (!rst_n)
        (m_axis_tvalid && !m_axis_tready) |=> ($stable(m_axis_tdata));
    endproperty

    assert property (p_master_no_take_backs_valid) else $error("AXI VIOLATION: We dropped m_axis_tvalid during stall!");
    assert property (p_master_no_take_backs_data) else $error("AXI VIOLATION: We changed m_axis_tdata during stall!");

endmodule

bind axis_skid_buffer axis_skid_buffer_sva #(
    .DATA_WIDTH(DATA_WIDTH)
) u_skid_sva_checker (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready)
);
