// Copyright (c) 2018-2019, Michael P. Howard
// This file is part of the azplugins project, released under the Modified BSD License.

// Maintainer: astatt

/*!
 * \file MPCDSineGeometryFillerGPU.cu
 * \brief Defines GPU functions and kernels used by azplugins::gpu::SineGeometryFillerGPU
 */

#include "MPCDSineGeometryFillerGPU.cuh"
#include "hoomd/RandomNumbers.h"
#include "RNGIdentifiers.h"
#include "hoomd/mpcd/ParticleDataUtilities.h"


namespace azplugins
{

namespace gpu
{

namespace kernel
{
/*!
 * \param d_pos Particle positions
 * \param d_vel Particle velocities
 * \param d_tag Particle tags
 * \param geom Sine geometry to fill
 * \param m_pi_period_div_L
 * \param m_amplitude
 * \param box Local simulation box
 * \param type Type of fill particles
 * \param N_lo Number of particles to fill in lower region
 * \param N_hi Number of particles to fill in upper region
 * \param first_tag First tag of filled particles
 * \param first_idx First (local) particle index of filled particles
 * \param vel_factor Scale factor for uniform normal velocities consistent with particle mass / temperature
 * \param timestep Current timestep
 * \param seed User seed to PRNG for drawing velocities
 *
 * \b Implementation:
 *
 * Using one thread per particle (in both slabs), the thread is assigned to fill either the lower
 * or upper region. This defines a local cuboid of volume to fill. The thread index is translated into
 * a particle tag and local particle index. A random position is drawn within the cuboid. A random velocity
 * is drawn consistent with the speed of the moving wall.
 */
__global__ void sine_draw_particles(Scalar4 *d_pos,
                                    Scalar4 *d_vel,
                                    unsigned int *d_tag,
                                    const azplugins::detail::SineGeometry geom,
                                    const Scalar m_pi_period_div_L,
                                    const Scalar m_amplitude,
                                    const Scalar m_H_narrow,
                                    const Scalar m_thickness,
                                    const BoxDim box,
                                    const unsigned int type,
                                    const unsigned int N_fill,
                                    const unsigned int first_tag,
                                    const unsigned int first_idx,
                                    const Scalar vel_factor,
                                    const unsigned int timestep,
                                    const unsigned int seed)
    {
    // one thread per particle
    const unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N_fill)
        return;
    Scalar3 lo = box.getLo();
    Scalar3 hi = box.getHi();
    const unsigned int N_half = 0.5*N_fill;


    // particle tag and index
    const unsigned int tag = first_tag + idx;
    const unsigned int pidx = first_idx + idx;
    d_tag[pidx] = tag;

    // initialize random number generator for positions and velocity
    hoomd::RandomGenerator rng(RNGIdentifier::SineGeometryFiller, seed, tag, timestep);
    signed char sign = (idx >= N_half) - (idx < N_half); // bottom -1 or top +1

    Scalar x = hoomd::UniformDistribution<Scalar>(lo.x, hi.x)(rng);
    Scalar y = hoomd::UniformDistribution<Scalar>(lo.y, hi.y)(rng);
    Scalar z = hoomd::UniformDistribution<Scalar>(0, sign*m_thickness)(rng);

    signed char sign = (z >= 0) - (z < 0);  // bottom -1 or top +1

    z = sign*(m_amplitude*fast::cos(x*m_pi_period_div_L)+m_amplitude + m_H_narrow ) + z;


    d_pos[pidx] = make_scalar4(x,
                               y,
                               z,
                               __int_as_scalar(type));

    hoomd::NormalDistribution<Scalar> gen(vel_factor, 0.0);
    Scalar3 vel;
    gen(vel.x, vel.y, rng);
    vel.z = gen(rng);
    // TODO: should these be given zero net-momentum contribution (relative to the frame of reference?)
    d_vel[pidx] = make_scalar4(vel.x + sign * geom.getVelocity(),
                               vel.y,
                               vel.z,
                               __int_as_scalar(mpcd::detail::NO_CELL));
    }
} // end namespace kernel

/*!
 * \param d_pos Particle positions
 * \param d_vel Particle velocities
 * \param d_tag Particle tags
 * \param geom Slit geometry to fill
 * \param z_min Lower bound to lower fill region
 * \param z_max Upper bound to upper fill region
 * \param box Local simulation box
 * \param mass Mass of fill particles
 * \param type Type of fill particles
 * \param N_lo Number of particles to fill in lower region
 * \param N_hi Number of particles to fill in upper region
 * \param first_tag First tag of filled particles
 * \param first_idx First (local) particle index of filled particles
 * \param kT Temperature for fill particles
 * \param timestep Current timestep
 * \param seed User seed to PRNG for drawing velocities
 * \param block_size Number of threads per block
 *
 * \sa kernel::slit_draw_particles
 */
cudaError_t sine_draw_particles(Scalar4 *d_pos,
                                Scalar4 *d_vel,
                                unsigned int *d_tag,
                                const azplugins::detail::SineGeometry& geom,
                                const Scalar m_pi_period_div_L,
                                const Scalar m_amplitude,
                                const Scalar m_H_narrow,
                                const Scalar m_thickness,
                                const BoxDim& box,
                                const Scalar mass,
                                const unsigned int type,
                                const unsigned int N_fill,
                                const unsigned int first_tag,
                                const unsigned int first_idx,
                                const Scalar kT,
                                const unsigned int timestep,
                                const unsigned int seed,
                                const unsigned int block_size)
    {
    if (N_tot == 0) return cudaSuccess;

    static unsigned int max_block_size = UINT_MAX;
    if (max_block_size == UINT_MAX)
        {
        cudaFuncAttributes attr;
        cudaFuncGetAttributes(&attr, (const void*)kernel::sine_draw_particles);
        max_block_size = attr.maxThreadsPerBlock;
        }

    // precompute factor for rescaling the velocities since it is the same for all particles
    const Scalar vel_factor = fast::sqrt(kT / mass);

    unsigned int run_block_size = min(block_size, max_block_size);
    dim3 grid(N_tot / run_block_size + 1);
    kernel::sine_draw_particles<<<grid, run_block_size>>>(d_pos,
                                                          d_vel,
                                                          d_tag,
                                                          geom,
                                                          m_pi_period_div_L,
                                                          m_amplitude,
                                                          m_H_narrow,
                                                          m_thickness,
                                                          box,
                                                          type,
                                                          N_fill,
                                                          first_tag,
                                                          first_idx,
                                                          vel_factor,
                                                          timestep,
                                                          seed);

    return cudaSuccess;
    }

} // end namespace gpu
} // end namespace azplugins