#include "srf_mem_integration_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

constexpr std::size_t kTestDepth = 16;
constexpr std::uint8_t kRead = 0;
constexpr std::uint8_t kWrite = 1;
using RowData = std::array<std::uint64_t,
                           SrfMemIntegrationModel::SUPERLANES>;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << message << '\n';
        ++failures;
    }
}

std::uint32_t make_command(const std::uint8_t opcode,
                           const Direction direction,
                           const std::uint8_t stream,
                           const std::uint16_t row) {
    const bool west = direction == Direction::WEST;
    return ((static_cast<std::uint32_t>(row) & 0x7FFFU) << 15U) |
           (static_cast<std::uint32_t>(west) << 8U) |
           ((static_cast<std::uint32_t>(stream) & 0x1FU) << 3U) |
           (static_cast<std::uint32_t>(opcode) & 0x7U);
}

std::size_t producer_id(const std::uint8_t slice,
                        const std::uint8_t bank,
                        const std::size_t tile) {
    return static_cast<std::size_t>(slice) * 8U +
           static_cast<std::size_t>(bank) * 4U + tile;
}

void write_row_from_srf(SrfMemIntegrationModel& model,
                        const Hemisphere hemisphere,
                        const Direction direction,
                        const std::uint8_t slice,
                        const std::uint8_t bank,
                        const std::uint8_t stream,
                        const std::uint16_t row,
                        const RowData& row_data,
                        const bool check_consume) {
    const std::size_t group =
        slice / MemHemisphereModel::SLICES_PER_GROUP;
    const std::uint8_t boundary = static_cast<std::uint8_t>(
        direction == Direction::WEST ? group + 1U : group);
    const std::size_t direction_index =
        direction == Direction::WEST ? 1U : 0U;

    expect(model.inject_srf_segment(
               hemisphere, direction, 0, boundary, 0, stream, row_data[0]),
           "initial SRF segment injection rejected");
    model.step();

    for (std::size_t tile = 0;
         tile < SrfMemIntegrationModel::SUPERLANES; ++tile) {
        if (tile == 0U) {
            expect(model.issue_mem_command(
                       hemisphere, slice, bank,
                       make_command(kWrite, direction, stream, row)),
                   "MEM Write issue rejected");
        }
        if (tile + 1U < SrfMemIntegrationModel::SUPERLANES) {
            expect(model.inject_srf_segment(
                       hemisphere, direction, 0, boundary,
                       static_cast<std::uint8_t>(tile + 1U), stream,
                       row_data[tile + 1U]),
                   "staggered SRF segment injection rejected");
        }

        model.step();
        if (check_consume) {
            const auto& consumes =
                model.mem_outputs(hemisphere).boundary_consume;
            expect(consumes[boundary][direction_index][stream][tile],
                   "MEM segment consume missing for tile " +
                       std::to_string(tile));
        }
    }
}

void check_mem_read_outputs(SrfMemIntegrationModel& model,
                            const Hemisphere hemisphere,
                            const Direction direction,
                            const std::uint8_t slice,
                            const std::uint8_t bank,
                            const std::uint8_t stream,
                            const std::uint16_t row,
                            const RowData& expected,
                            const bool check_srf_state) {
    const std::size_t group =
        slice / MemHemisphereModel::SLICES_PER_GROUP;
    const std::uint8_t output_boundary = static_cast<std::uint8_t>(
        direction == Direction::WEST ? group : group + 1U);

    for (std::size_t tile = 0;
         tile < SrfMemIntegrationModel::SUPERLANES; ++tile) {
        if (tile == 0U) {
            expect(model.issue_mem_command(
                       hemisphere, slice, bank,
                       make_command(kRead, direction, stream, row)),
                   "MEM Read issue rejected");
        }
        model.step();

        const auto& producer = model.mem_outputs(hemisphere)
                                   .producer[producer_id(slice, bank, tile)];
        expect(producer.valid, "MEM Read producer missing for tile " +
                                   std::to_string(tile));
        expect(producer.data == expected[tile],
               "MEM Read producer data mismatch for tile " +
                   std::to_string(tile));
        expect(producer.boundary == output_boundary &&
                   producer.stream_dir == (direction == Direction::WEST) &&
                   producer.stream_idx == stream && producer.tile == tile,
               "MEM Read producer metadata mismatch for tile " +
                   std::to_string(tile));

        if (check_srf_state) {
            const auto segment = model.read_srf_segment(
                hemisphere, direction, output_boundary,
                static_cast<std::uint8_t>(tile), stream);
            expect(segment.valid && segment.data == expected[tile],
                   "producer0 to SRF segment mapping mismatch for tile " +
                       std::to_string(tile));
        }
    }
}

void test_srf_to_mem_write() {
    std::cout << "RUN_TEST srf_to_mem_write" << '\n';
    SrfMemIntegrationModel model(kTestDepth);
    const RowData data{0x0706050403020100ULL,
                       0x1716151413121110ULL,
                       0x2726252423222120ULL,
                       0x3736353433323130ULL};

    write_row_from_srf(model, Hemisphere::WEST, Direction::EAST,
                       0, 0, 3, 5, data, true);
    check_mem_read_outputs(model, Hemisphere::WEST, Direction::EAST,
                           0, 0, 7, 5, data, false);
}

void test_mem_to_srf_read() {
    std::cout << "RUN_TEST mem_to_srf_read" << '\n';
    SrfMemIntegrationModel model(kTestDepth);
    const RowData data{0xA7A6A5A4A3A2A1A0ULL,
                       0xB7B6B5B4B3B2B1B0ULL,
                       0xC7C6C5C4C3C2C1C0ULL,
                       0xD7D6D5D4D3D2D1D0ULL};

    write_row_from_srf(model, Hemisphere::EAST, Direction::WEST,
                       8, 1, 5, 9, data, false);
    model.reset();
    check_mem_read_outputs(model, Hemisphere::EAST, Direction::WEST,
                           8, 1, 11, 9, data, true);
    expect(model.cycle() == SrfMemIntegrationModel::SUPERLANES,
           "integration cycle count mismatch after MEM Read");
}

void test_srf_mem_srf_round_trip() {
    std::cout << "RUN_TEST srf_mem_srf_round_trip" << '\n';
    SrfMemIntegrationModel model(kTestDepth);
    const RowData data{0x8877665544332211ULL,
                       0x1020304050607080ULL,
                       0xFFEEDDCCBBAA9988ULL,
                       0x5AA55AA5C33CC33CULL};

    write_row_from_srf(model, Hemisphere::WEST, Direction::EAST,
                       24, 0, 13, 12, data, true);
    check_mem_read_outputs(model, Hemisphere::WEST, Direction::EAST,
                           24, 0, 21, 12, data, true);

    expect(!model.srf_model().collision_detected(
               Hemisphere::WEST, Direction::EAST),
           "unexpected SRF collision in collision-free contract");
    expect(!model.srf_model().invalid_consume_detected(
               Hemisphere::WEST, Direction::EAST),
           "unexpected invalid consume in round trip");
    expect(!model.dump_state().empty(), "dump_state returned an empty string");
}

}  // namespace

int main() {
    test_srf_to_mem_write();
    test_mem_to_srf_read();
    test_srf_mem_srf_round_trip();

    if (failures == 0) {
        std::cout << "CMODEL_SRF_MEM_INTEGRATION TEST_PASS" << '\n';
        return 0;
    }
    std::cout << "CMODEL_SRF_MEM_INTEGRATION TEST_FAIL failures="
              << failures << '\n';
    return 1;
}
