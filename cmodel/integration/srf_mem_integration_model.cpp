#include "srf_mem_integration_model.h"

#include <iomanip>
#include <sstream>

SrfMemIntegrationModel::SrfMemIntegrationModel(
    const std::size_t mem_depth_rows)
    : mem_{MemHemisphereModel(mem_depth_rows),
           MemHemisphereModel(mem_depth_rows)} {
    reset();
}

void SrfMemIntegrationModel::reset() {
    srf_.reset();
    for (auto& hemisphere : mem_) {
        hemisphere.reset();
    }
    mem_inputs_ = {};
    mem_outputs_ = {};
    cycle_ = 0;
}

std::size_t SrfMemIntegrationModel::hemisphere_index(
    const Hemisphere hemisphere) {
    return hemisphere == Hemisphere::WEST ? 0U : 1U;
}

Direction SrfMemIntegrationModel::direction_from_index(
    const std::size_t direction) {
    return direction == 0U ? Direction::EAST : Direction::WEST;
}

bool SrfMemIntegrationModel::inject_srf_segment(
    const Hemisphere hemisphere,
    const Direction direction,
    const std::uint8_t producer,
    const std::uint8_t column,
    const std::uint8_t superlane,
    const std::uint8_t stream,
    const std::uint64_t data) {
    if (producer >= FullChipModel::LOCAL_PRODUCERS ||
        column >= SRF_COLUMNS || superlane >= SUPERLANES ||
        stream >= STREAMS) {
        return false;
    }

    bool accepted = true;
    for (std::size_t lane = 0; lane < LANES; ++lane) {
        const std::uint8_t lane_data = static_cast<std::uint8_t>(
            (data >> (lane * 8U)) & 0xFFU);
        accepted = srf_.inject_cell(
            hemisphere, direction, producer, column, superlane, stream,
            static_cast<std::uint8_t>(lane), lane_data) && accepted;
    }
    return accepted;
}

SrfMemIntegrationModel::SegmentState
SrfMemIntegrationModel::read_srf_segment(
    const Hemisphere hemisphere,
    const Direction direction,
    const std::uint8_t column,
    const std::uint8_t superlane,
    const std::uint8_t stream) const {
    SegmentState segment{};
    if (column >= SRF_COLUMNS || superlane >= SUPERLANES ||
        stream >= STREAMS) {
        return segment;
    }

    bool all_lanes_valid = true;
    for (std::size_t lane = 0; lane < LANES; ++lane) {
        const CommandResult cell = srf_.read_cell(
            hemisphere, direction, column, superlane, stream,
            static_cast<std::uint8_t>(lane));
        all_lanes_valid = all_lanes_valid && cell.success && cell.valid;
        segment.data |= static_cast<std::uint64_t>(cell.data) << (lane * 8U);
    }
    segment.valid = all_lanes_valid;
    return segment;
}

bool SrfMemIntegrationModel::issue_mem_command(
    const Hemisphere hemisphere,
    const std::uint8_t slice,
    const std::uint8_t bank,
    const std::uint32_t raw_command) {
    if (slice >= MemHemisphereModel::SLICES ||
        bank >= MemHemisphereModel::BANKS) {
        return false;
    }

    auto& inputs = mem_inputs_[hemisphere_index(hemisphere)];
    if (inputs.issue_valid[slice][bank]) {
        return false;
    }
    inputs.issue_valid[slice][bank] = true;
    inputs.issue_raw[slice][bank] = raw_command;
    return true;
}

void SrfMemIntegrationModel::update_mem_boundary_inputs(
    const std::size_t hemisphere) {
    const Hemisphere srf_hemisphere =
        hemisphere == 0U ? Hemisphere::WEST : Hemisphere::EAST;
    auto& boundary_state = mem_inputs_[hemisphere].boundary_state;

    for (std::size_t boundary = 0; boundary < MEM_BOUNDARIES; ++boundary) {
        for (std::size_t direction = 0; direction < 2U; ++direction) {
            for (std::size_t stream = 0; stream < STREAMS; ++stream) {
                for (std::size_t superlane = 0;
                     superlane < SUPERLANES; ++superlane) {
                    const SegmentState segment = read_srf_segment(
                        srf_hemisphere, direction_from_index(direction),
                        static_cast<std::uint8_t>(boundary),
                        static_cast<std::uint8_t>(superlane),
                        static_cast<std::uint8_t>(stream));
                    auto& mem_segment =
                        boundary_state[boundary][direction][stream][superlane];
                    mem_segment.valid = segment.valid;
                    mem_segment.data = segment.data;
                }
            }
        }
    }
}

void SrfMemIntegrationModel::route_mem_producers(
    const std::size_t hemisphere) {
    const Hemisphere target_hemisphere =
        hemisphere == 0U ? Hemisphere::WEST : Hemisphere::EAST;

    for (const auto& producer : mem_outputs_[hemisphere].producer) {
        if (!producer.valid || producer.boundary >= MEM_BOUNDARIES ||
            producer.stream_idx >= STREAMS ||
            producer.tile >= SUPERLANES) {
            continue;
        }

        const Direction direction =
            producer.stream_dir ? Direction::WEST : Direction::EAST;
        for (std::size_t lane = 0; lane < LANES; ++lane) {
            const std::uint8_t lane_data = static_cast<std::uint8_t>(
                (producer.data >> (lane * 8U)) & 0xFFU);
            srf_.inject_cell(
                target_hemisphere, direction, MEM_PRODUCER_SLOT,
                producer.boundary, producer.tile, producer.stream_idx,
                static_cast<std::uint8_t>(lane), lane_data);
        }
    }
}

void SrfMemIntegrationModel::route_mem_consumes(
    const std::size_t hemisphere) {
    const Hemisphere target_hemisphere =
        hemisphere == 0U ? Hemisphere::WEST : Hemisphere::EAST;
    const auto& consumes = mem_outputs_[hemisphere].boundary_consume;

    for (std::size_t boundary = 0; boundary < MEM_BOUNDARIES; ++boundary) {
        for (std::size_t direction = 0; direction < 2U; ++direction) {
            for (std::size_t stream = 0; stream < STREAMS; ++stream) {
                for (std::size_t superlane = 0;
                     superlane < SUPERLANES; ++superlane) {
                    if (!consumes[boundary][direction][stream][superlane]) {
                        continue;
                    }
                    for (std::size_t lane = 0; lane < LANES; ++lane) {
                        srf_.consume_cell(
                            target_hemisphere,
                            direction_from_index(direction),
                            MEM_CONSUMER_SLOT,
                            static_cast<std::uint8_t>(boundary),
                            static_cast<std::uint8_t>(superlane),
                            static_cast<std::uint8_t>(stream),
                            static_cast<std::uint8_t>(lane));
                    }
                }
            }
        }
    }
}

void SrfMemIntegrationModel::step() {
    // All MEM instances observe the immutable SRF state at cycle start.
    for (std::size_t hemisphere = 0; hemisphere < HEMISPHERES;
         ++hemisphere) {
        update_mem_boundary_inputs(hemisphere);
        mem_outputs_[hemisphere] =
            mem_[hemisphere].step(mem_inputs_[hemisphere]);
        mem_inputs_[hemisphere].issue_valid = {};
        mem_inputs_[hemisphere].issue_raw = {};
    }

    // The fixed contract maps every MEM Read producer to SRF producer0 and
    // every segment consume to all eight lanes of SRF consumer0. External
    // collision feedback remains zero;  assumes collision-free traffic.
    for (std::size_t hemisphere = 0; hemisphere < HEMISPHERES;
         ++hemisphere) {
        route_mem_producers(hemisphere);
        route_mem_consumes(hemisphere);
    }

    srf_.step();
    ++cycle_;
}

std::uint64_t SrfMemIntegrationModel::cycle() const {
    return cycle_;
}

std::string SrfMemIntegrationModel::dump_state() const {
    std::size_t valid_boundary_segments = 0;
    std::array<std::size_t, HEMISPHERES> producer_count{};
    std::array<std::size_t, HEMISPHERES> consume_count{};

    for (std::size_t hemisphere = 0; hemisphere < HEMISPHERES;
         ++hemisphere) {
        const Hemisphere current =
            hemisphere == 0U ? Hemisphere::WEST : Hemisphere::EAST;
        for (std::size_t boundary = 0; boundary < MEM_BOUNDARIES; ++boundary) {
            for (std::size_t direction = 0; direction < 2U; ++direction) {
                for (std::size_t stream = 0; stream < STREAMS; ++stream) {
                    for (std::size_t superlane = 0;
                         superlane < SUPERLANES; ++superlane) {
                        valid_boundary_segments += read_srf_segment(
                            current, direction_from_index(direction),
                            static_cast<std::uint8_t>(boundary),
                            static_cast<std::uint8_t>(superlane),
                            static_cast<std::uint8_t>(stream)).valid ? 1U : 0U;
                        consume_count[hemisphere] +=
                            mem_outputs_[hemisphere]
                                .boundary_consume[boundary][direction]
                                                 [stream][superlane] ? 1U : 0U;
                    }
                }
            }
        }
        for (const auto& producer : mem_outputs_[hemisphere].producer) {
            producer_count[hemisphere] += producer.valid ? 1U : 0U;
        }
    }

    std::ostringstream output;
    output << "integration_cycle=" << cycle_
           << " srf_cycle=" << srf_.cycle()
           << " west_mem_cycle=" << mem_[0].cycle()
           << " east_mem_cycle=" << mem_[1].cycle() << '\n'
           << "valid_boundary_segments=" << valid_boundary_segments << '\n'
           << "west_producers=" << producer_count[0]
           << " west_consumes=" << consume_count[0] << '\n'
           << "east_producers=" << producer_count[1]
           << " east_consumes=" << consume_count[1] << '\n';
    return output.str();
}

const FullChipModel& SrfMemIntegrationModel::srf_model() const {
    return srf_;
}

const MemHemisphereModel& SrfMemIntegrationModel::mem_model(
    const Hemisphere hemisphere) const {
    return mem_[hemisphere_index(hemisphere)];
}

const MemHemisphereModel::Outputs& SrfMemIntegrationModel::mem_outputs(
    const Hemisphere hemisphere) const {
    return mem_outputs_[hemisphere_index(hemisphere)];
}
