from pathlib import Path

import cocotb
from cocotb.triggers import Timer


VECTOR_PATH = Path(__file__).resolve().parents[2] / "vectors" / "crc8_parallel.csv"


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        data_hex, crc_bits = line.split(",")
        yield int(data_hex, 16), int(crc_bits, 2), crc_bits


@cocotb.test()
async def matches_matlab_crc8_golden_vectors(dut):
    for data_word, expected_crc, expected_bits in load_vectors():
        dut.data_i.value = data_word
        await Timer(1, unit="ns")

        actual_crc = int(dut.crc_o.value)
        assert actual_crc == expected_crc, (
            f"CRC8 mismatch for 0x{data_word:04X}: "
            f"expected {expected_bits}, got {actual_crc:08b}"
        )
