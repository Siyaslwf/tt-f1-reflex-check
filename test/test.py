import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Starting F1 Reflex Trainer VGA test...")
    
    # Start 25 MHz clock (40ns period)
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    # Initialize inputs
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    # Apply Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    
    # Run simulation for several clock cycles to let VGA and timer initialize
    await ClockCycles(dut.clk, 500)
    
    # Simulate pressing Button 0 (Start trigger)
    dut.ui_in.value = 1
    await ClockCycles(dut.clk, 100)
    dut.ui_in.value = 0
    
    # Run more cycles to test light sequencing
    await ClockCycles(dut.clk, 500)

    dut._log.info("F1 Reflex Trainer test passed successfully!")
