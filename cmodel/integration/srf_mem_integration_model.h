#ifndef SRF_MEM_INTEGRATION_MODEL_H
#define SRF_MEM_INTEGRATION_MODEL_H

#include "mem_hemisphere_model.h"
#include "srf_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

// Lightweight system-level model of the frozen SRF-MEM Integration 
// contract. The SRF and MEM models retain their own state; this class owns
// only integration-cycle bookkeeping and one-cycle command inputs.
class SrfMemIntegrationModel {
public:
    static constexpr std::size_t HEMISPHERES = 2;
    static constexpr std::size_t MEM_BOUNDARIES = 14;
    static constexpr std::size_t SRF_COLUMNS = 16;
    static constexpr std::size_t SUPERLANES = 4;
    static constexpr std::size_t STREAMS = 32;
    static constexpr std::size_t LANES = 8;
    static constexpr std::uint8_t MEM_PRODUCER_SLOT = 0;
    static constexpr std::uint8_t MEM_CONSUMER_SLOT = 0;

    struct SegmentState {
        bool valid = false;
        std::uint64_t data = 0;
    };

    explicit SrfMemIntegrationModel(
        std::size_t mem_depth_rows =
            MemBankSuperlaneLeafModel::P_MEM_BANK_DEPTH_ROWS);

    void reset();
    void step();
    std::uint64_t cycle() const;
    std::string dump_state() const;

    // Queue one SRF local-producer segment for the next step. This helper is
    // used to model integration stimulus; MEM Read traffic always uses slot 0.
    bool inject_srf_segment(Hemisphere hemisphere,
                            Direction direction,
                            std::uint8_t producer,
                            std::uint8_t column,
                            std::uint8_t superlane,
                            std::uint8_t stream,
                            std::uint64_t data);

    SegmentState read_srf_segment(Hemisphere hemisphere,
                                  Direction direction,
                                  std::uint8_t column,
                                  std::uint8_t superlane,
                                  std::uint8_t stream) const;

    // Queue a one-cycle MEM command issue. A second issue to the same
    // Slice/Bank before step() is rejected rather than silently overwritten.
    bool issue_mem_command(Hemisphere hemisphere,
                           std::uint8_t slice,
                           std::uint8_t bank,
                           std::uint32_t raw_command);

    const FullChipModel& srf_model() const;
    const MemHemisphereModel& mem_model(Hemisphere hemisphere) const;
    const MemHemisphereModel::Outputs& mem_outputs(
        Hemisphere hemisphere) const;

private:
    static std::size_t hemisphere_index(Hemisphere hemisphere);
    static Direction direction_from_index(std::size_t direction);

    void update_mem_boundary_inputs(std::size_t hemisphere);
    void route_mem_producers(std::size_t hemisphere);
    void route_mem_consumes(std::size_t hemisphere);

    FullChipModel srf_;
    std::array<MemHemisphereModel, HEMISPHERES> mem_;
    std::array<MemHemisphereModel::Inputs, HEMISPHERES> mem_inputs_{};
    std::array<MemHemisphereModel::Outputs, HEMISPHERES> mem_outputs_{};
    std::uint64_t cycle_ = 0;
};

#endif
