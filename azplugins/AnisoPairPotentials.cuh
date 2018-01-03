// Copyright (c) 2016-2018, Panagiotopoulos Group, Princeton University
// This file is part of the azplugins project, released under the Modified BSD License.

// Maintainer: mphoward

/*!
 * \file AnisoPairPotentials.cuh
 * \brief Declares driver function for computing anisotropic pair forces on the GPU
 *
 * A templated function for each driver should be instantiated in
 * AnisoPairPotentials.cu.
 */

#ifndef AZPLUGINS_ANISO_PAIR_POTENTIAL_DRIVERS_CUH_
#define AZPLUGINS_ANISO_PAIR_POTENTIAL_DRIVERS_CUH_

#include "hoomd/md/AnisoPotentialPairGPU.cuh"
#include "AnisoPairPotentials.h"

namespace azplugins
{
namespace gpu
{
//! Anisotropic pair potential compute kernel driver
/*!
 * \param pair_args Standard anisotropic pair potential arguments
 * \param d_params Specific parameters required for the potential
 * \tparam evaluator Evaluator functor
 */
template<class evaluator>
cudaError_t compute_aniso_pair_potential(const a_pair_args_t& pair_args, const typename evaluator::param_type *d_params);

#ifdef NVCC
/*!
 * This implements the templated kernel driver when compiled in NVCC only. The template
 * must be specifically instantiated per potential in a cu file.
 */
template<class evaluator>
cudaError_t compute_aniso_pair_potential(const a_pair_args_t& pair_args, const typename evaluator::param_type *d_params)
    {
    return ::gpu_compute_pair_aniso_forces<evaluator>(pair_args, d_params);
    }
#endif
} // end namespace gpu
} // end namespace azplugins

#endif // AZPLUGINS_ANISO_PAIR_POTENTIAL_DRIVERS_CUH_
