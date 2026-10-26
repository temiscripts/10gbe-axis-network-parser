#include <cassert>
#include <cstdint>
#include <iostream>
#include <memory>

#include "Vaxis_skid_buffer.h"
#include <verilated.h>

void tick(VerilatedContext *contextp, Vaxis_skid_buffer *top) {
  top->clk = 1;
  contextp->timeInc(1);
  top->eval();

  top->clk = 0;
  contextp->timeInc(1);
  top->eval();
}

int main(int argc, char **argv) {
  auto contextp = std::make_unique<VerilatedContext>();
  contextp->commandArgs(argc, argv);
  auto top = std::make_unique<Vaxis_skid_buffer>(contextp.get());

  std::cout << "[TB] Starting AXI4-Stream Skid Buffer Simulation..."
            << std::endl;

  top->rst_n = 0;
  top->s_axis_tvalid = 0;
  top->s_axis_tdata = 0;
  top->m_axis_tready = 1;

  for (int i = 0; i < 5; ++i) {
    tick(contextp.get(), top.get());
  }

  top->rst_n = 1;
  tick(contextp.get(), top.get());

  assert(top->s_axis_tready == 1 &&
         "ERROR: s_axis_tready should be 1 after reset!");
  assert(top->m_axis_tvalid == 0 &&
         "ERROR: m_axis_tvalid should be 0 after reset!");
  std::cout
      << "[TB] Reset sequence verified (s_axis_tready=1, m_axis_tvalid=0)."
      << std::endl;

  uint64_t test_word_1 = 0xDEADBEEFCAFE0001ULL;
  top->s_axis_tdata = test_word_1;
  top->s_axis_tvalid = 1;

  tick(contextp.get(), top.get());

  std::cout << "[TB] Sent Word 1: 0x" << std::hex << test_word_1 << std::dec
            << std::endl;
  std::cout << "[TB] Output m_axis_tvalid = " << (int)top->m_axis_tvalid
            << ", m_axis_tdata = 0x" << std::hex << top->m_axis_tdata
            << std::dec << std::endl;

  assert(top->m_axis_tvalid == 1 && "ERROR: m_axis_tvalid should be 1!");
  assert(top->m_axis_tdata == test_word_1 && "ERROR: m_axis_tdata mismatch!");

  top->s_axis_tvalid = 0;
  tick(contextp.get(), top.get());

  uint64_t test_word_2 = 0x123456789ABCDEF0ULL;
  uint64_t test_word_3 = 0x5555555555555555ULL;

  top->m_axis_tready = 1;
  top->s_axis_tdata = test_word_2;
  top->s_axis_tvalid = 1;
  tick(contextp.get(), top.get());

  top->m_axis_tready = 0;
  top->s_axis_tdata = test_word_3;
  top->s_axis_tvalid = 1;
  tick(contextp.get(), top.get());

  std::cout
      << "[TB] Downstream Stalled (m_axis_tready=0) and skid register full."
      << std::endl;
  std::cout << "[TB] s_axis_tready = " << (int)top->s_axis_tready
            << " (expected 0)" << std::endl;

  assert(top->s_axis_tready == 0 &&
         "ERROR: s_axis_tready should be 0 during skid buffer stall!");

  top->m_axis_tready = 1;
  tick(contextp.get(), top.get());

  top->s_axis_tvalid = 0;
  tick(contextp.get(), top.get());
  tick(contextp.get(), top.get());

  std::cout << "[TB] Simulation completed successfully! All assertions passed."
            << std::endl;

  top->final();
  return 0;
}